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
    @State private var gallery: [URL]?
    @State private var failed = false

    static func isVideo(_ url: URL) -> Bool {
        ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if let videoURL {
                AutoPlayVideo(url: videoURL, active: isActive)
            } else if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let gallery {
                TabView {
                    ForEach(gallery, id: \.self) { url in
                        GalleryImage(url: url, model: model)
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
                ContentUnavailableView("Média indisponible", systemImage: "photo")
                    .foregroundStyle(.white)
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
                let urls = try await model.galleryImageURLs(feedID: entry.post.id)
                guard !urls.isEmpty else { throw FeedError.invalidFeed }
                gallery = urls
            }
        } catch is CancellationError {
            // The card scrolled away; a newer task owns the state now.
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

private struct GalleryImage: View {
    let url: URL
    let model: FeedModel
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task {
            image = try? await model.loadImage(url, maxPixels: 2048)
        }
    }
}
