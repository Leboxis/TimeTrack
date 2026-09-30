import SwiftUI
import WellbeingCore

struct FeedView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = FeedModel()
    @State private var visibleID: String?

    private var entries: [FeedEntry] { model.entries }

    private var current: FeedEntry? {
        guard let visibleID else { return entries.first }
        return entries.first { $0.id == visibleID } ?? entries.first
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
            } else if model.posts.isEmpty {
                ContentUnavailableView("Aucun post", systemImage: "text.bubble",
                    description: Text("r/\(model.subreddit) ne renvoie aucun post. Le subreddit peut être vide, privé, ou ton compteReddit n’y a pas accès."))
            } else if entries.isEmpty {
                ContentUnavailableView("Aucun média", systemImage: "photo",
                    description: Text("\(model.posts.count) post(s) reçu(s) sur r/\(model.subreddit), mais aucun ne contient de média lisible."))
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            FeedCard(entry: entry, isActive: entry.id == visibleID, model: model)
                                .containerRelativeFrame(.vertical)
                                .id(entry.id)
                                .onAppear {
                                    if entry.id == entries.last?.id { model.loadMore() }
                                }
                        }
                        if model.loadingMore {
                            ProgressView().tint(.white)
                                .containerRelativeFrame(.vertical)
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
                    if let current {
                        let isSaved = model.isSaved(current.post.id)
                        Button {
                            Task { await model.toggleSaved(postID: current.post.id) }
                        } label: {
                            Label(isSaved ? "Retirer des sauvegardes" : "Enregistrer",
                                  systemImage: isSaved ? "heart.fill" : "heart")
                                .labelStyle(.iconOnly)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .foregroundStyle(isSaved ? .pink : .primary)
                        .disabled(model.savingPostID != nil)
                        .accessibilityLabel(isSaved ? "Retirer des sauvegardes Reddit" : "Enregistrer dans les sauvegardes Reddit")
                    }
                    Button { model.load() } label: {
                        Label("Actualiser", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .accessibilityLabel("Actualiser le flux et synchroniser les sauvegardes")
                    if model.loading {
                        ProgressView().tint(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding()
                Spacer()
            }
            if let message = model.saveErrorMessage {
                Text(message)
                    .font(.caption).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.red.opacity(0.85), in: Capsule())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
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
