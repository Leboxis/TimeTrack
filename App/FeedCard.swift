import SwiftUI
import UIKit
import WellbeingCore

struct FeedEntry: Identifiable {
    let id: String
    let post: Post
    let media: Media?
    let thumbnail: URL?
}

struct FeedCard: View {
    let entry: FeedEntry
    let isActive: Bool
    let model: FeedModel

    @State private var thumb: UIImage?
    @State private var image: UIImage?
    @State private var videoURL: URL?
    @State private var gallery: [Media]?
    @State private var galleryIndex = 0
    @State private var failed = false

    static func isVideo(_ url: URL) -> Bool {
        ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if let videoURL {
                AutoPlayVideo(url: videoURL, active: isActive) { failed = true }
            } else if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let gallery {
                TabView(selection: $galleryIndex) {
                    ForEach(Array(gallery.enumerated()), id: \.offset) { position, item in
                        GalleryPage(media: item,
                                    active: isActive && position == galleryIndex,
                                    preloads: abs(position - galleryIndex) <= 1,
                                    model: model)
                            .tag(position)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            } else if let thumb {
                Image(uiImage: thumb).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if !failed {
                            ProgressView().tint(.white)
                        }
                    }
            } else if failed {
                VStack(spacing: 16) {
                    ContentUnavailableView("Média indisponible", systemImage: "photo")
                        .foregroundStyle(.white)
                    Button("Réessayer") { Task { await retry() } }
                        .buttonStyle(.borderedProminent).tint(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.post.title).font(.headline).foregroundStyle(.white).lineLimit(3)
                if let date = entry.post.publishedAt {
                    Text(date, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
        }
        .task(id: entry.id) { await load() }
    }

    private func load() async {
        // The two requests run together. They used to be sequential, so the poster of a
        // video or a photo was fully downloaded before the media itself even started.
        let preview = Task { try? await loadPreview() }
        var failedToLoad = false
        do {
            try await loadMedia()
        } catch is CancellationError {
            preview.cancel()
        } catch {
            preview.cancel()
            failedToLoad = !Task.isCancelled
        }
        // Still awaited on the happy path: it is the small one, and showing the poster
        // is what fills the gap until the media arrives.
        if let image = await preview.value, !Task.isCancelled { thumb = image }
        if failedToLoad { failed = true }
    }

    private func loadPreview() async throws -> UIImage? {
        guard let thumbURL = entry.thumbnail else { return nil }
        return try await model.loadImage(thumbURL, maxPixels: 960)
    }

    private func loadMedia() async throws {
        switch entry.media {
        case .direct(let url):
            if Self.isVideo(url) {
                videoURL = url
            } else {
                image = try await model.loadImage(url, maxPixels: 2048)
            }
        case .redditVideo(let base):
            videoURL = base.appending(path: "HLSPlaylist.m3u8")
        case .redgifs(let id):
            videoURL = try await model.redgifsStreamURL(id: id)
        case nil:
            let items = try await model.galleryMedia(feedID: entry.post.id)
            guard !items.isEmpty else { throw FeedError.invalidFeed }
            gallery = items
        }
    }

    private func retry() async {
        failed = false
        gallery = nil
        image = nil
        videoURL = nil
        await load()
    }
}

private struct GalleryPage: View {
    let media: Media
    let active: Bool
    /// A `TabView` builds every page at once, so a 20-image gallery used to start 20
    /// full-size downloads before the user had swiped anywhere. Only the current page
    /// and its two neighbours are fetched.
    let preloads: Bool
    let model: FeedModel
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            switch media {
            case .direct(let url):
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if failed {
                    VStack(spacing: 12) {
                        Image(systemName: "photo").font(.largeTitle).foregroundStyle(.white.opacity(0.6))
                        Button("Réessayer") { Task { await load(url: url) } }
                            .buttonStyle(.bordered).tint(.white)
                    }
                } else {
                    ProgressView().tint(.white)
                }
            case .redditVideo(let base):
                AutoPlayVideo(url: base.appending(path: "HLSPlaylist.m3u8"), active: active)
            case .redgifs:
                // Unreachable: GalleryFeed.parse only emits direct and redditVideo.
                ContentUnavailableView("Média indisponible", systemImage: "photo")
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task(id: preloads) {
            guard preloads, image == nil, case .direct(let url) = media else { return }
            await load(url: url)
        }
    }

    private func load(url: URL) async {
        failed = false
        if let image = try? await model.loadImage(url, maxPixels: 2048), !Task.isCancelled {
            self.image = image
        } else if !Task.isCancelled {
            failed = true
        }
    }
}
