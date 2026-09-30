import Foundation
import Observation
import WebKit
import WellbeingCore

struct CookieVerdict: Identifiable {
    let name: String
    let attachable: Bool
    let expired: Bool
    var id: String { name }
}

/// Holds the Reddit login session. The cookie lives in WebKit's own persistent store
/// (`WKWebsiteDataStore.default()`), never in app-readable storage, exactly like the
/// reference app. The app can only read it to build a request header.
@MainActor @Observable
final class RedditSession {
    static let shared = RedditSession()

    private(set) var hasSession = false
    private(set) var clearing = false
    /// Set when Reddit answers 401/403 with a cookie we believed was valid.
    private(set) var expired = false
    /// Per-cookie verdict against the feed URL: attached by the policy, or dropped,
    /// and whether it is already expired. This is what turns "9 cookies" into a cause.
    private(set) var cookieReport: [CookieVerdict] = []

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
        if !valid { expired = false }
        hasSession = valid
        let target = feedURL(subreddit: "feet")
        // Only cookies this app could ever send to Reddit matter. Cloudflare's
        // cf_clearance lives on another domain and is dropped by the policy, so
        // showing it as a failure would be noise.
        cookieReport = cookies
            .sorted { $0.name < $1.name }
            .filter { $0.domain.lowercased().contains("reddit.com") }
            .map { cookie in
                CookieVerdict(
                    name: cookie.name,
                    attachable: RedditCookiePolicy.header(cookies: [cookie], for: target) != nil,
                    expired: cookie.expiresDate.map { $0 <= Date() } ?? false)
            }
    }

    func markExpired() {
        hasSession = false
        expired = true
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
        expired = false
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
