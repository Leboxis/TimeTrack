import Foundation
import ImageIO
import Observation
import WellbeingCore

/// Loads the feed and resolves playable media. Streaming only: nothing is saved,
/// nothing is downloaded to disk, the only state is a Redgifs token and a memory
/// cache of resolved URLs.
@MainActor @Observable
final class FeedModel {
    private static let userAgent = "Wellbeing/1.6 (iOS; RSS reader)"
    private static let subredditKey = "wellbeing.feed.subreddit"

    var subreddit: String {
        didSet { UserDefaults.standard.set(subreddit, forKey: Self.subredditKey) }
    }
    private(set) var posts: [Post] = []
    private(set) var loading = false
    var errorMessage: String?

    private var redgifsToken: String?
    private var redgifsTokenDate = Date.distantPast
    private var resolvedCache: [String: [URL]] = [:]
    private var loadTask: Task<Void, Never>?

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
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let name = try subredditName(subreddit)
            let (data, response) = try await get(feedURL(subreddit: name))
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw FeedError.invalidFeed
            }
            posts = try FeedParser.parse(data)
        } catch is CancellationError {
            // Superseded by a newer load; leave the previous posts in place.
        } catch let urlError as URLError {
            posts = []
            errorMessage = offlineMessage(for: urlError)
        } catch {
            posts = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return try await URLSession.shared.data(for: request)
    }

    private func checked(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        let (data, response) = try await get(url, headers: headers)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw FeedError.invalidFeed
        }
        return data
    }

    func loadImage(_ url: URL, maxPixels: Int) async throws -> UIImage {
        let data = try await checked(url)
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels
              ] as CFDictionary) else {
            throw FeedError.invalidFeed
        }
        return UIImage(cgImage: cg)
    }

    /// Playable URLs for one gallery post. Gallery videos are dropped: carousels
    /// here are overwhelmingly images, and a mixed pager would need the full player.
    func galleryImageURLs(feedID: String) async throws -> [URL] {
        if let cached = resolvedCache[feedID] { return cached }
        guard let url = GalleryFeed.commentsJSONURL(feedID: feedID) else { throw FeedError.invalidFeed }
        let urls = try GalleryFeed.parse(try await checked(url)).compactMap { media -> URL? in
            if case .direct(let url) = media { return url }
            return nil
        }
        resolvedCache[feedID] = urls
        return urls
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
        if let cached = resolvedCache["redgifs:" + id]?.first { return cached }
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
            resolvedCache["redgifs:" + id] = [url]
            return url
        } catch {
            // The token may have expired mid-session: drop it once and retry once.
            redgifsToken = nil
            let url = try await attempt()
            resolvedCache["redgifs:" + id] = [url]
            return url
        }
    }
}
