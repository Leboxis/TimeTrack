import ImageIO
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
                        GalleryPage(media: item, active: isActive && position == galleryIndex, model: model)
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
        if let thumbURL = entry.thumbnail,
           let thumb = try? await model.loadImage(thumbURL, maxPixels: 960),
           !Task.isCancelled {
            self.thumb = thumb
        }
        guard !Task.isCancelled else { return }
        do {
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
        } catch is CancellationError {
            // The card scrolled away; a newer task owns the state now.
        } catch {
            if !Task.isCancelled { failed = true }
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
        .task {
            if case .direct(let url) = media { await load(url: url) }
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
