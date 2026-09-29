import Foundation

struct MediaItem: Identifiable {
    let id: String
    let title: String
}

/// Adding a media item means adding one entry here. No view changes required.
enum MediaCatalog {
    static let all: [MediaItem] = []
}
