import Foundation

/// Reads the account's Reddit saved list as one Atom feed, so the heart can reflect
/// posts saved anywhere — in this app, on reddit.com, or in another client — for the
/// price of a single request rather than one per post.
public enum RedditSaved {
    /// `saved.rss` is only in the v2 tree, like download. The username comes from
    /// `/api/me.json`, so no prefs-page scraping is needed.
    public static func feedURL(username: String, limit: Int = 100, after: String? = nil) -> URL? {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.range(of: "^[A-Za-z0-9_-]{3,20}$", options: .regularExpression) != nil else { return nil }
        var components = URLComponents(string: "https://www.reddit.com/user/\(trimmed)/saved.rss")!
        var items = [URLQueryItem(name: "limit", value: String(max(1, min(100, limit))))]
        if let after, !after.isEmpty { items.append(URLQueryItem(name: "after", value: after)) }
        components.queryItems = items
        return components.url
    }

    public static func ids(from posts: [Post]) -> Set<String> {
        Set(posts.map(\.id).filter { $0.hasPrefix("t3_") })
    }

    /// Union, not intersection: a post saved in the app but no longer in the remote
    /// list stays marked until the user unsaves it here.
    public static func merge(local: Set<String>, remote: Set<String>) -> Set<String> {
        local.union(remote)
    }

    /// One hour. Long enough that scrolling a feed never triggers it, short enough that
    /// saves made on reddit.com show up within a session.
    public static let ttl: TimeInterval = 3600

    public static func isStale(_ date: Date?, now: Date = Date()) -> Bool {
        guard let date else { return true }
        return now.timeIntervalSince(date) >= ttl
    }
}
