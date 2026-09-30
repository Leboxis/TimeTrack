import Foundation

enum MediaKind: String {
    case audio, video, image
}

struct MediaItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let kind: MediaKind
    /// Bundled asset name without extension, for offline content.
    let resource: String?
    /// Direct media URL, for streamed content.
    let url: URL?
    /// Extra request headers, e.g. the kDrive bearer token.
    var headers: [String: String] = [:]
    /// Preferred fetch path, e.g. kDrive's direct-then-signed fallback. When nil the
    /// item is fetched straight from `url` with `headers`.
    var loader: (() async throws -> Data)?

    init(id: String, title: String, subtitle: String, kind: MediaKind,
         resource: String?, url: URL?, headers: [String: String] = [:],
         loader: (() async throws -> Data)? = nil) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.kind = kind
        self.resource = resource; self.url = url; self.headers = headers
        self.loader = loader
    }
}

struct MediaCategory: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let items: [MediaItem]
}

/// Adding content means adding one entry here. No view changes required.
enum MediaCatalog {
    static let categories: [MediaCategory] = [audio]

    static let audio = MediaCategory(
        id: "audio",
        title: "Audio",
        systemImage: "waveform",
        items: [
            MediaItem(id: "prejac-f4a", title: "Prejac and Beta Brainwashing 101",
                      subtitle: "Professor Nichole · F4A",
                      kind: .audio, resource: "prejac-beta-101-f4a", url: nil),
            MediaItem(id: "prejac-f4m", title: "Prejac and Beta Brainwashing 101",
                      subtitle: "Professor Nichole · F4M",
                      kind: .audio, resource: "prejac-beta-101-f4m", url: nil),
            MediaItem(id: "itty-bitty", title: "itty bitty premie",
                      subtitle: "Audio",
                      kind: .audio, resource: "itty-bitty-premie", url: nil)
        ]
    )
}
