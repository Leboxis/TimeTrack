import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

// MARK: - Model

public struct Post: Identifiable {
    public let id: String
    public let title: String
    public let html: String
    public let publishedAt: Date?
    public let link: String?
    public init(id: String, title: String, html: String, publishedAt: Date? = nil, link: String? = nil) {
        self.id = id; self.title = title; self.html = html; self.publishedAt = publishedAt; self.link = link
    }
}

public enum Media: Hashable, Sendable {
    case direct(URL), redditVideo(URL), redgifs(String)
    public var key: String {
        switch self {
        case .direct(let url): return url.absoluteString
        case .redditVideo(let url): return url.absoluteString
        case .redgifs(let id): return "redgifs:" + id
        }
    }
}

public enum FeedError: LocalizedError {
    case invalidFeed, invalidSubreddit, http(Int), rateLimited
    public var errorDescription: String? {
        switch self {
        case .invalidFeed:
            return "Réponse RSS invalide : Reddit peut refuser cet accès anonyme."
        case .invalidSubreddit:
            return "Subreddit invalide (2 à 21 lettres, chiffres ou underscores, ex. r/feet)."
        case .http(let code):
            return "Accès refusé par le serveur (HTTP \(code))."
        case .rateLimited:
            return "Reddit limite les requêtes. Patiente quelques secondes puis réessaie."
        }
    }
}

// MARK: - Feed URL and subreddit validation

public func feedURL(subreddit name: String) -> URL {
    var components = URLComponents(string: "https://www.reddit.com/r/\(name)/new.rss")!
    components.queryItems = [URLQueryItem(name: "limit", value: "25")]
    return components.url!
}

public func subredditName(_ text: String) throws -> String {
    let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard name.range(of: "^[A-Za-z0-9_]{2,21}$", options: .regularExpression) != nil else {
        throw FeedError.invalidSubreddit
    }
    return name
}

// MARK: - Atom parser

public final class FeedParser: NSObject, XMLParserDelegate {
    private var posts: [Post] = []
    private var inEntry = false
    private var elementStack: [String] = []
    private var element: String { elementStack.last ?? "" }
    private var id = "", title = "", html = "", published = "", link: String?
    private var isFeed = false

    private static func parseDate(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    public static func parse(_ data: Data) throws -> [Post] {
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.isFeed else { throw FeedError.invalidFeed }
        return delegate.posts
    }

    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        elementStack.append(name)
        if name == "feed" { isFeed = true }
        if name == "entry" { inEntry = true; id = ""; title = ""; html = ""; published = ""; link = nil }
        if inEntry, name == "link", link == nil, let href = attributes["href"]?.trimmingCharacters(in: .whitespacesAndNewlines), !href.isEmpty {
            link = href
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters text: String) {
        guard inEntry else { return }
        switch element { case "id": id += text; case "title": title += text; case "content": html += text; case "published": published += text; default: break }
    }

    public func parser(_ parser: XMLParser, foundCDATA data: Data) { self.parser(parser, foundCharacters: String(decoding: data, as: UTF8.self)) }
    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "entry" { if !id.isEmpty { posts.append(Post(id: id, title: title, html: html, publishedAt: Self.parseDate(published), link: link)) }; inEntry = false }
        _ = elementStack.popLast()
    }
}

// MARK: - Media extraction

public enum MediaExtractor {
    private static let imgRegex = try! NSRegularExpression(pattern: #"(?i)<img\b[^>]*?\s+src\s*=\s*["']([^"']+)["']"#)
    private static let hrefRegex = try! NSRegularExpression(pattern: #"(?i)href\s*=\s*["']([^"']+)["']"#)

    public static func previewImage(_ html: String) -> URL? {
        let ns = html as NSString
        for match in imgRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: raw), url.scheme == "https", let host = url.host?.lowercased(),
                  ["preview.redd.it", "external-preview.redd.it", "i.redd.it", "i.imgur.com",
                   "a.thumbs.redditmedia.com", "b.thumbs.redditmedia.com"].contains(host) else { continue }
            return url
        }
        return nil
    }

    public static func extract(_ html: String) -> [Media] {
        let ns = html as NSString
        var seen = Set<Media>()
        let linked = hrefRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match -> Media? in
            let raw = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: raw), url.scheme == "https", let host = url.host?.lowercased() else { return nil }
            var media: Media?
            if host == "v.redd.it", let id = url.pathComponents.dropFirst().first, !id.isEmpty {
                guard let videoURL = URL(string: "https://v.redd.it/\(id)") else { return nil }
                media = .redditVideo(videoURL)
            } else if host == "redgifs.com" || host == "www.redgifs.com" {
                let parts = url.pathComponents
                if parts.count >= 3, ["watch", "ifr"].contains(parts[1]), parts[2].range(of: "^[a-zA-Z0-9]+$", options: .regularExpression) != nil {
                    media = .redgifs(parts[2].lowercased())
                }
            } else if ["i.redd.it", "i.imgur.com"].contains(host), ["jpg", "jpeg", "png", "gif", "webp", "mp4"].contains(url.pathExtension.lowercased()) {
                media = .direct(QualityPolicy.originalImageURL(url))
            }
            guard let media, seen.insert(media).inserted else { return nil }
            return media
        }
        if !linked.isEmpty { return linked }

        // Quarantined NSFW subreddits serve a feed whose entries only carry a
        // preview.redd.it image and no original link. Accepting the preview keeps
        // those posts playable instead of reporting an empty feed. The HTML arrives
        // entity-decoded once, but its attribute values stay escaped, so a second
        // unescape is what the reference applies before matching hosts.
        let previews = imgRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match -> Media? in
            let raw = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            guard var components = URLComponents(string: raw),
                  components.scheme == "https",
                  let host = components.host?.lowercased() else { return nil }
            guard ["preview.redd.it", "external-preview.redd.it"].contains(host) else { return nil }
            components.host = "i.redd.it"
            guard let original = components.url, !original.pathExtension.isEmpty else { return nil }
            guard seen.insert(.direct(original)).inserted else { return nil }
            return .direct(original)
        }
        return previews
    }
}

// MARK: - Gallery posts

public enum GalleryFeed {
    private static let linkedRegex = try! NSRegularExpression(pattern: #"(?i)href\s*=\s*["']https://www\.reddit\.com/gallery/[A-Za-z0-9]+["']"#)
    private static let linkedIDRegex = try! NSRegularExpression(pattern: #"(?i)href\s*=\s*["']https://www\.reddit\.com/gallery/([A-Za-z0-9]+)["']"#)

    public static func linked(_ html: String) -> Bool {
        linkedRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) != nil
    }

    public static func linkedID(_ html: String) -> String? {
        let ns = html as NSString
        guard let match = linkedIDRegex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    public static func commentsJSONURL(feedID: String) -> URL? {
        let id = feedID.hasPrefix("t3_") ? String(feedID.dropFirst(3)) : feedID
        guard id.range(of: "^[A-Za-z0-9]{4,12}$", options: .regularExpression) != nil else { return nil }
        var components = URLComponents(string: "https://www.reddit.com/comments/\(id).json")!
        components.queryItems = [URLQueryItem(name: "raw_json", value: "1"), URLQueryItem(name: "limit", value: "1")]
        return components.url
    }

    public static func parse(_ data: Data) throws -> [Media] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let post = ((root.first?["data"] as? [String: Any])?["children"] as? [[String: Any]])?.first?["data"] as? [String: Any] else {
            throw FeedError.invalidFeed
        }
        var container = post
        if container["gallery_data"] == nil,
           let parents = container["crosspost_parent_list"] as? [[String: Any]],
           let fallback = parents.last(where: { $0["gallery_data"] != nil }) {
            container = fallback
        }
        guard let gallery = container["gallery_data"] as? [String: Any],
              let items = gallery["items"] as? [[String: Any]],
              let metadata = container["media_metadata"] as? [String: Any] else {
            return []
        }
        let extByMime = ["image/jpg": "jpg", "image/jpeg": "jpg", "image/png": "png",
                         "image/webp": "webp", "image/gif": "gif"]
        var seen = Set<Media>()
        var result: [Media] = []
        for item in items {
            guard let id = item["media_id"] as? String,
                  let meta = metadata[id] as? [String: Any],
                  (meta["status"] as? String ?? "valid") == "valid" else { continue }
            let mime = ((meta["m"] as? String) ?? "").lowercased()
            let kind = meta["e"] as? String
            let s = meta["s"] as? [String: Any]
            var media: Media?
            if kind == "RedditVideo" || mime == "video/mp4" {
                let manifest = (s?["dashUrl"] as? String) ?? (s?["hlsUrl"] as? String) ?? ""
                if let url = URL(string: manifest), url.scheme == "https", url.host == "v.redd.it",
                   let videoID = url.pathComponents.dropFirst().first, !videoID.isEmpty,
                   let base = URL(string: "https://v.redd.it/\(videoID)") {
                    media = .redditVideo(base)
                }
            } else if let ext = extByMime[mime] {
                let raw = ((s?["u"] as? String) ?? (s?["gif"] as? String)) ?? ""
                if var components = URLComponents(string: raw),
                   components.scheme == "https",
                   ["preview.redd.it", "i.redd.it"].contains(components.host?.lowercased()) {
                    components.query = nil
                    let stem = components.url?.deletingPathExtension().lastPathComponent ?? ""
                    if !stem.isEmpty, let rebuilt = URL(string: "https://i.redd.it/\(stem).\(ext)") {
                        media = .direct(QualityPolicy.originalImageURL(rebuilt))
                    }
                }
            }
            if let media, seen.insert(media).inserted { result.append(media) }
        }
        return result
    }
}

// MARK: - Quality and Redgifs API shapes

public enum QualityPolicy {
    public static func originalImageURL(_ url: URL) -> URL {
        guard url.host?.lowercased() == "i.imgur.com",
              ["jpg", "jpeg", "png", "gif", "webp"].contains(url.pathExtension.lowercased()) else { return url }
        let stem = url.deletingPathExtension().lastPathComponent
        guard stem.range(of: "^(?:[A-Za-z0-9]{5}|[A-Za-z0-9]{7})[sbtmlh]$", options: .regularExpression) != nil,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let original = String(stem.dropLast()) + "." + url.pathExtension
        parts.path = "/" + original
        return parts.url ?? url
    }

    public static func redgifsCandidates(hd: URL?, sd: URL?) -> [URL] {
        [hd, sd].compactMap { $0 }
    }
}

public enum RedgifsAPI {
    public static func gifURL(id: String) -> URL {
        var components = URLComponents(string: "https://api.redgifs.com/v2/gifs/\(id.lowercased())")!
        components.queryItems = [URLQueryItem(name: "views", value: "yes")]
        return components.url!
    }

    public static func headers(id: String) -> [String: String] {
        let lowered = id.lowercased()
        return [
            "Referer": "https://www.redgifs.com/",
            "Origin": "https://www.redgifs.com",
            "x-customheader": "https://www.redgifs.com/watch/\(lowered)"
        ]
    }
}
