import SwiftUI
import WellbeingCore

struct FeedView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = FeedModel()
    @State private var visibleID: String?

    private var entries: [FeedEntry] {
        var result: [FeedEntry] = []
        for post in model.posts {
            let media = MediaExtractor.extract(post.html)
            if !media.isEmpty {
                for (index, item) in media.enumerated() {
                    result.append(FeedEntry(id: "\(post.id)-\(index)", post: post, media: item,
                                            thumbnail: MediaExtractor.previewImage(post.html)))
                }
            } else if GalleryFeed.linked(post.html) {
                result.append(FeedEntry(id: "\(post.id)-gallery", post: post, media: nil,
                                        thumbnail: MediaExtractor.previewImage(post.html)))
            }
        }
        return result
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.loading && model.posts.isEmpty {
                ProgressView().tint(.white)
            } else if let message = model.errorMessage, model.posts.isEmpty {
                VStack(spacing: 16) {
                    ContentUnavailableView("Flux indisponible", systemImage: "wifi.exclamationmark",
                        description: Text(message))
                    Button("Réessayer") { model.load() }.buttonStyle(.borderedProminent).tint(.white)
                }
            } else if entries.isEmpty {
                ContentUnavailableView("Aucun média", systemImage: "photo",
                    description: Text("Les posts de ce flux ne contiennent pas de média lisible."))
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            FeedCard(entry: entry, isActive: entry.id == visibleID, model: model)
                                .containerRelativeFrame(.vertical)
                                .id(entry.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $visibleID)
                .scrollIndicators(.hidden)
                .ignoresSafeArea()
                .refreshable { await model.reload() }
            }
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Label("Fermer", systemImage: "chevron.down")
                            .labelStyle(.iconOnly)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Menu {
                        ForEach(FeedLevel.allCases, id: \.self) { level in
                            Menu(level.title) {
                                ForEach(level.subreddits, id: \.self) { sub in
                                    Button {
                                        model.subreddit = sub
                                        model.load()
                                    } label: {
                                        if sub == model.subreddit {
                                            Label(sub, systemImage: "checkmark")
                                        } else {
                                            Text(sub)
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("r/\(model.subreddit)", systemImage: "list.bullet")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                    Button { model.load() } label: {
                        Label("Actualiser", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    if model.loading {
                        ProgressView().tint(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding()
                Spacer()
            }
        }
        .task { model.load() }
        .onChange(of: model.posts.map(\.id)) { _, _ in
            if visibleID == nil || !entries.contains(where: { $0.id == visibleID }) {
                visibleID = entries.first?.id
            }
        }
        .privacyMask()
    }
}
