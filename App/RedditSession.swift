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
    /// Set when Reddit answers 401/403 with a cookie we believed was valid.
    private(set) var expired = false

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
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.httpCookieStore.getAllCookies { cookies in
                self.store.httpCookieStore.delete(cookies) {
                    self.store.httpCookieStore.setCookies([]) { continuation.resume() }
                }
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
