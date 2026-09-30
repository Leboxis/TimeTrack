import Foundation
import Observation
import UIKit
import WellbeingCore

/// Loads the feed and resolves playable media. Streaming only: nothing is saved,
/// nothing is downloaded to disk, the only state is a Redgifs token and a memory
/// cache of resolved URLs.
@MainActor @Observable
final class FeedModel {
    private static let userAgent = "RedditMediaPocket/0.1 (iOS; RSS reader)"
    private static let subredditKey = "wellbeing.feed.subreddit"

    var subreddit: String {
        didSet { UserDefaults.standard.set(subreddit, forKey: Self.subredditKey) }
    }
    private(set) var posts: [Post] = []
    /// The feed's playable entries, rebuilt only when the posts actually change.
    ///
    /// `FeedView.body` runs on every scroll step, every save and every reload, and it
    /// was rebuilding this each time: two regular expressions over the HTML of every
    /// post, with `previewImage` re-run once per media item inside the inner loop. That
    /// was the hottest path in the app by a wide margin.
    private(set) var entries: [FeedEntry] = []
    private(set) var loading = false
    private(set) var loadingMore = false
    private(set) var hasMore = true
    var errorMessage: String?

    private var redgifsToken: String?
    private var redgifsTokenDate = Date.distantPast
    private var resolvedURLCache: [String: URL] = [:]
    private var resolvedMediaCache: [String: [Media]] = [:]
    /// Paging a long session grew both caches without bound, and a signed Redgifs URL
    /// that has expired by the time it is reused is worse than no cache at all.
    private static let cacheLimit = 200
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.subredditKey) ?? "feet"
        subreddit = (try? subredditName(saved)) ?? "feet"
    }

    func load() {
        loadTask?.cancel()
        loadTask = Task { await fetch() }
    }

    func reload() async {
        loadTask?.cancel()
        await fetch()
    }

    private func fetch() async {
        loadGeneration &+= 1
        let mine = loadGeneration
        loading = true
        errorMessage = nil
        defer { if loadGeneration == mine { loading = false } }
        do {
            let name = try subredditName(subreddit)
            await RedditSession.shared.refresh()
            let (data, response) = try await get(feedURL(subreddit: name))
            try Task.checkCancellation()
            guard loadGeneration == mine else { return }
            guard let http = response as? HTTPURLResponse else { throw FeedError.invalidFeed }
            if http.statusCode == 429 { throw FeedError.rateLimited }
            guard (200...299).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }
            let parsed = try FeedParser.parse(data)
            guard loadGeneration == mine else { return }
            posts = parsed
            rebuildEntries()
            hasMore = parsed.count >= 25
            await refreshSavedIDs()
        } catch is CancellationError {
            // Superseded by a newer load; leave the previous posts in place.
        } catch let urlError as URLError where urlError.code == .cancelled {
            // The URLSession task died with its parent task. Same as above.
        } catch let urlError as URLError {
            guard loadGeneration == mine else { return }
            posts = []
            rebuildEntries()
            errorMessage = offlineMessage(for: urlError)
        } catch {
            guard loadGeneration == mine else { return }
            posts = []
            rebuildEntries()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Flattens the posts into one entry per media item, directories first. Called only
    /// when the post list changes, never from a view body.
    private func rebuildEntries() {
        var result: [FeedEntry] = []
        for post in posts {
            let media = MediaExtractor.extract(post.html)
            // Once per post, not once per media item.
            let thumbnail = MediaExtractor.previewImage(post.html)
            if !media.isEmpty {
                for (index, item) in media.enumerated() {
                    result.append(FeedEntry(id: "\(post.id)-\(index)", post: post, media: item,
                                            thumbnail: thumbnail))
                }
            } else if GalleryFeed.linked(post.html) {
                result.append(FeedEntry(id: "\(post.id)-gallery", post: post, media: nil,
                                        thumbnail: thumbnail))
            }
        }
        entries = result
    }

    /// Appends the next page, walking Reddit's `after` cursor from the last post seen.
    func loadMore() {
        guard !loadingMore, !loading, hasMore, let last = posts.last else { return }
        loadingMore = true
        // A reload replaces `posts` wholesale. Without pinning the generation, a page
        // still in flight appended the old subreddit's posts to the new list.
        let mine = loadGeneration
        let name = subreddit
        Task {
            defer { loadingMore = false }
            do {
                let valid = try subredditName(name)
                let (data, response) = try await get(feedURL(subreddit: valid, after: last.id))
                guard loadGeneration == mine, subreddit == name else { return }
                guard let http = response as? HTTPURLResponse else { throw FeedError.invalidFeed }
                if http.statusCode == 429 { hasMore = false; return }
                guard (200...299).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }
                let parsed = try FeedParser.parse(data)
                guard !parsed.isEmpty else { hasMore = false; return }
                let known = Set(posts.map(\.id))
                let fresh = parsed.filter { !known.contains($0.id) }
                posts.append(contentsOf: fresh)
                rebuildEntries()
                if parsed.count < 25 || fresh.isEmpty { hasMore = false }
            } catch {
                guard loadGeneration == mine else { return }
                hasMore = false
            }
        }
    }

    /// Post fullnames saved from this app, kept even if the remote list no longer has
    /// them. Reddit's own list is merged in so saves made elsewhere are reflected.
    private(set) var savedIDs: Set<String> = RedditAccount.savedSet(
        from: UserDefaults.standard.string(forKey: "wellbeing.reddit.saved") ?? "[]")

    private static let savedRefreshKey = "wellbeing.reddit.savedRefreshed"
    private var didFetchSavedThisSession = false
    private(set) var refreshingSaved = false

    func isSaved(_ postID: String) -> Bool { savedIDs.contains(postID) }

    /// Fetches the whole saved list: one request, throttled to once per hour and never
    /// more than once per session, so scrolling and paging the feed cost nothing extra.
    func refreshSavedIDs(force: Bool = false) async {
        guard !refreshingSaved, RedditSession.shared.hasSession else { return }
        if !force {
            if didFetchSavedThisSession { return }
            let last = UserDefaults.standard.object(forKey: Self.savedRefreshKey) as? Date
            guard RedditSaved.isStale(last) else { return }
        }
        refreshingSaved = true
        defer { refreshingSaved = false }
        do {
            let remote = try await RedditSession.shared.savedIDs()
            guard !Task.isCancelled else { return }
            savedIDs = RedditSaved.merge(local: savedIDs, remote: remote)
            UserDefaults.standard.set(Date(), forKey: Self.savedRefreshKey)
            // Armed only once the list actually arrived. Marking it in a `defer` meant
            // a single network blip locked the heart out of syncing for the whole
            // session, while the hourly stamp correctly stayed unset.
            didFetchSavedThisSession = true
        } catch {
            // A failed sync must never clear the locally known saves, and must stay
            // retryable.
        }
    }

    private(set) var savingPostID: String?
    private(set) var saveErrorMessage: String?

    /// Toggles the post in the signed-in account's Reddit saves.
    func toggleSaved(postID: String) async {
        guard savingPostID == nil else { return }
        savingPostID = postID
        saveErrorMessage = nil
        let target = !savedIDs.contains(postID)
        defer { savingPostID = nil }
        do {
            try await RedditSession.shared.setSaved(fullname: postID, saved: target)
            if target { savedIDs.insert(postID) } else { savedIDs.remove(postID) }
            UserDefaults.standard.set(RedditAccount.encodeSavedSet(savedIDs), forKey: "wellbeing.reddit.saved")
        } catch {
            saveErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func offlineMessage(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Connexion impossible. Vérifiez votre réseau puis réessayez."
        default:
            return error.localizedDescription
        }
    }

    private func get(_ url: URL, headers: [String: String] = [:]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        var cookie = await RedditSession.shared.cookieHeader(for: url)
        if url.host?.hasSuffix("reddit.com") == true {
            // Reddit gates NSFW subreddit feeds on the `over18` consent cookie, which
            // the login WebView never sets on its own. The user's account is
            // adult-enabled; asserting it here mirrors what the web interstitial does.
            if cookie?.contains("over18=") != true {
                cookie = [cookie, "over18=1"].compactMap { $0 }.joined(separator: "; ")
            }
            if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        }
        return try await session.data(for: request)
    }

    /// URLSession copies headers onto the redirect request, so a 302 to a CDN would
    /// replay the session cookie. Strip it and re-add it only for Reddit hosts.
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            var redirected = request
            redirected.setValue(nil, forHTTPHeaderField: "Cookie")
            if let url = request.url, RedditCookiePolicy.allows(url) {
                Task { @MainActor in
                    if let cookie = await RedditSession.shared.cookieHeader(for: url) {
                        redirected.setValue(cookie, forHTTPHeaderField: "Cookie")
                    }
                    completionHandler(redirected)
                }
            } else {
                completionHandler(redirected)
            }
        }
    }

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1800
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
    }()

    private func checked(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        let (data, response) = try await get(url, headers: headers)
        guard let http = response as? HTTPURLResponse else { throw FeedError.invalidFeed }
        guard (200...299).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }
        return data
    }

    func loadImage(_ url: URL, maxPixels: Int) async throws -> UIImage {
        let data = try await checked(url)
        try Task.checkCancellation()
        guard let image = await ImageDecoder.image(from: data, maxPixels: maxPixels) else {
            throw FeedError.invalidFeed
        }
        return image
    }

    /// Playable media for one gallery post, in carousel order: images and videos.
    /// `GalleryFeed.parse` only ever emits those two cases.
    func galleryMedia(feedID: String) async throws -> [Media] {
        if let cached = resolvedMediaCache[feedID] { return cached }
        guard let url = GalleryFeed.commentsJSONURL(feedID: feedID) else { throw FeedError.invalidFeed }
        let media = try GalleryFeed.parse(try await checked(url))
        if resolvedMediaCache.count >= Self.cacheLimit { resolvedMediaCache.removeAll(keepingCapacity: true) }
        resolvedMediaCache[feedID] = media
        return media
    }

    private func token() async throws -> String {
        if let token = redgifsToken, Date().timeIntervalSince(redgifsTokenDate) < 1800 { return token }
        struct Auth: Decodable { let token: String }
        let data = try await checked(URL(string: "https://api.redgifs.com/v2/auth/temporary")!)
        let token = try JSONDecoder().decode(Auth.self, from: data).token
        redgifsToken = token
        redgifsTokenDate = Date()
        return token
    }

    func redgifsStreamURL(id: String) async throws -> URL {
        if let cached = resolvedURLCache["redgifs:" + id] { return cached }
        struct Response: Decodable {
            struct Gif: Decodable {
                struct URLs: Decodable { let hd: URL?; let sd: URL? }
                let urls: URLs
            }
            let gif: Gif
        }
        let attempt: () async throws -> URL = {
            let bearer = try await self.token()
            let data = try await self.checked(RedgifsAPI.gifURL(id: id),
                headers: ["Authorization": "Bearer " + bearer].merging(RedgifsAPI.headers(id: id)) { current, _ in current })
            let urls = try JSONDecoder().decode(Response.self, from: data).gif.urls
            let candidates = QualityPolicy.redgifsCandidates(hd: urls.hd, sd: urls.sd).filter {
                $0.host == "redgifs.com" || ($0.host?.hasSuffix(".redgifs.com") ?? false)
            }
            guard let first = candidates.first else { throw FeedError.invalidFeed }
            return first
        }
        do {
            let url = try await attempt()
            if resolvedURLCache.count >= Self.cacheLimit { resolvedURLCache.removeAll(keepingCapacity: true) }
            resolvedURLCache["redgifs:" + id] = url
            return url
        } catch FeedError.http(401) {
            // The token expired mid-session: drop it once and retry once.
            // Any other error is surfaced as-is, without churning a valid token.
            redgifsToken = nil
            let url = try await attempt()
            if resolvedURLCache.count >= Self.cacheLimit { resolvedURLCache.removeAll(keepingCapacity: true) }
            resolvedURLCache["redgifs:" + id] = url
            return url
        }
    }
}
