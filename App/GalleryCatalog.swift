import Foundation

struct Gallery: Identifiable {
    let id: String
    let title: String
    /// Asset names bundled with the app, in display order.
    let imageNames: [String]
}

/// Adding a gallery means adding one entry here. No view changes required.
enum GalleryCatalog {
    static let all: [Gallery] = []
}
