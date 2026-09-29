import Foundation
import ImageIO
import Observation
import UIKit
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
    private var resolvedURLCache: [String: URL] = [:]
    private var resolvedMediaCache: [String: [Media]] = [:]
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
            let (data, response) = try await get(feedURL(subreddit: name))
            try Task.checkCancellation()
            guard loadGeneration == mine else { return }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw FeedError.invalidFeed
            }
            let parsed = try FeedParser.parse(data)
            guard loadGeneration == mine else { return }
            posts = parsed
        } catch is CancellationError {
            // Superseded by a newer load; leave the previous posts in place.
        } catch let urlError as URLError where urlError.code == .cancelled {
            // The URLSession task died with its parent task. Same as above.
        } catch let urlError as URLError {
            guard loadGeneration == mine else { return }
            posts = []
            errorMessage = offlineMessage(for: urlError)
        } catch {
            guard loadGeneration == mine else { return }
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
        guard let http = response as? HTTPURLResponse else { throw FeedError.invalidFeed }
        guard (200...299).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }
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

    /// Playable media for one gallery post, in carousel order: images and videos.
    /// `GalleryFeed.parse` only ever emits those two cases.
    func galleryMedia(feedID: String) async throws -> [Media] {
        if let cached = resolvedMediaCache[feedID] { return cached }
        guard let url = GalleryFeed.commentsJSONURL(feedID: feedID) else { throw FeedError.invalidFeed }
        let media = try GalleryFeed.parse(try await checked(url))
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
            resolvedURLCache["redgifs:" + id] = url
            return url
        } catch FeedError.http(401) {
            // The token expired mid-session: drop it once and retry once.
            // Any other error is surfaced as-is, without churning a valid token.
            redgifsToken = nil
            let url = try await attempt()
            resolvedURLCache["redgifs:" + id] = url
            return url
        }
    }
}
