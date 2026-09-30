import Foundation
import Observation
import WebKit
import WellbeingCore

/// Holds the Reddit login session. The cookie lives in WebKit's own persistent store
/// (`WKWebsiteDataStore.default()`), never in app-readable storage, exactly like the
/// reference app. The app can only read it to build a request header.
@MainActor @Observable
final class RedditSession {
    static let shared = RedditSession()

    private(set) var hasSession = false
    private(set) var clearing = false
    private(set) var account: RedditAccount?

    let store = WKWebsiteDataStore.default()
    private var observer: (any WKHTTPCookieStoreObserver)?
    /// Reddit rewrites its cookies constantly, and every change used to trigger a full
    /// cookie fetch plus a possible `/api/me.json` round trip. One login writes a dozen
    /// cookies, so a single sign-in meant a dozen account requests.
    private var refreshTask: Task<Void, Never>?

    private init() {
        let observer = CookieObserver { [weak self] in
            self?.scheduleRefresh()
        }
        self.observer = observer
        store.httpCookieStore.add(observer)
        scheduleRefresh()
    }

    /// Collapses a burst of cookie writes into one refresh.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    func refresh() async {
        let cookies = await allCookies()
        let valid = cookies.contains {
            $0.name == "reddit_session"
                && RedditCookiePolicy.header(cookies: [$0], for: URL(string: "https://www.reddit.com/")!) != nil
        }
        hasSession = valid
        if valid, account == nil { await loadAccount() }
    }

    /// `/api/me.json` is the only way to learn the modhash that Reddit's write
    /// endpoints demand, and it also tells us whether the session really works.
    func loadAccount() async {
        do {
            var request = URLRequest(url: RedditAccount.meURL())
            if let cookie = await cookieHeader(for: RedditAccount.meURL()) {
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                account = nil
                return
            }
            account = try RedditAccount.decode(data)
        } catch {
            account = nil
        }
    }

    /// The account's whole saved list, every page. The caller is responsible for rate
    /// limiting; see `FeedModel.refreshSavedIDs`.
    func savedIDs() async throws -> Set<String> {
        guard hasSession else { throw RedditAccountError.anonymous }
        if account == nil { await loadAccount() }
        guard let account else { throw RedditAccountError.anonymous }
        return try await RedditSaved.walkAllIDs { after in
            guard let url = RedditSaved.feedURL(username: account.username, limit: 100, after: after) else {
                throw RedditAccountError.anonymous
            }
            var request = URLRequest(url: url)
            if let cookie = await self.cookieHeader(for: url) {
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw RedditAccountError.refused((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            return try FeedParser.parse(data)
        }
    }

    /// Saves or unsaves a post on the signed-in Reddit account.
    func setSaved(fullname: String, saved: Bool) async throws {
        guard hasSession else { throw RedditAccountError.anonymous }
        if account == nil { await loadAccount() }
        guard let account else { throw RedditAccountError.anonymous }
        let action: SaveAction = saved ? .save : .unsave
        let url = account.actionURL(action)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let cookie = await cookieHeader(for: url) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        request.httpBody = try account.saveBody(fullname: fullname).data(using: .utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RedditAccountError.refused((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func cookieHeader(for url: URL) async -> String? {
        guard !clearing else { return nil }
        return RedditCookiePolicy.header(cookies: await allCookies(), for: url)
    }

    /// Narrower than the reference, which wipes all website data. Only the cookies go.
    func logout() async {
        clearing = true
        refreshTask?.cancel()
        for cookie in await allCookies() {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.httpCookieStore.delete(cookie) { continuation.resume() }
            }
        }
        hasSession = false
        // The account carried the username and the modhash used by every write. Keeping
        // it meant reconnecting as somebody else still showed, and still saved to, the
        // previous account.
        account = nil
        clearing = false
    }
}

private final class CookieObserver: NSObject, WKHTTPCookieStoreObserver {
    /// Typed `@Sendable` rather than inferred: the closure is built inside a
    /// `@MainActor` initialiser, so without the annotation its type stayed
    /// main-actor-isolated and calling it from the `nonisolated` delegate callback was
    /// a warning here and an error under the Swift 6 language mode.
    private let onChange: @Sendable () -> Void
    init(onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        onChange()
    }
}
