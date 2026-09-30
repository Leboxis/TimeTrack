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

    private init() {
        let observer = CookieObserver { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        self.observer = observer
        store.httpCookieStore.add(observer)
        Task { await refresh() }
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
        for cookie in await allCookies() {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.httpCookieStore.delete(cookie) { continuation.resume() }
            }
        }
        hasSession = false
        clearing = false
    }
}

private final class CookieObserver: NSObject, WKHTTPCookieStoreObserver {
    private let onChange: () -> Void
    init(onChange: @escaping () -> Void) { self.onChange = onChange }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        onChange()
    }
}
