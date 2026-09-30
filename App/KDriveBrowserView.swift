import SwiftUI
import UIKit
import WellbeingCore

/// One level of the kDrive path, for the breadcrumb.
struct KDrivePathNode: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Grid of kDrive items: folders plus media with their kDrive thumbnail.
struct KDriveBrowserView: View {
    @State private var model = KDriveModel()
    @State private var path: [KDrivePathNode] = [KDrivePathNode(id: "1", name: "Racine")]
    @State private var playing: MediaItem?

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 12)]

    private var current: KDrivePathNode { path[path.count - 1] }

    var body: some View {
        Group {
            if model.loading && model.items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = model.errorMessage {
                ContentUnavailableView("kDrive indisponible", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(message))
                    .overlay(alignment: .bottom) {
                        Button("Réessayer") { Task { await model.load(directoryID: current.id) } }
                            .buttonStyle(.borderedProminent)
                            .padding(.bottom, 40)
                    }
            } else if model.items.isEmpty {
                ContentUnavailableView("Dossier vide", systemImage: "folder",
                    description: Text("Ce dossier ne contient aucun fichier lisible."))
            } else {
                grid
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { breadcrumb }
        }
        .task(id: current.id) { await model.load(directoryID: current.id) }
        .sheet(item: $playing) { MediaPlayerView(item: $0) }
        .privacyMask()
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.items) { item in
                    if item.isDirectory {
                        Button {
                            path.append(KDrivePathNode(id: String(item.id), name: item.name))
                        } label: {
                            tile {
                                VStack(spacing: 6) {
                                    Image(systemName: "folder.fill").font(.title2)
                                    Text(item.name).font(.caption).lineLimit(2)
                                }
                                .foregroundStyle(.teal)
                            }
                        }
                    } else if item.mediaKind != nil {
                        Button { open(item) } label: {
                            tile {
                                KDriveThumbnail(url: KDriveClient.thumbnailURL(config: model.config, fileID: item.id),
                                                 token: model.config.token)
                                Text(item.name).font(.caption2).lineLimit(2)
                                    .foregroundStyle(.primary).padding(.top, 4)
                            }
                        }
                    } else {
                        tile {
                            VStack(spacing: 6) {
                                Image(systemName: "doc").font(.title2)
                                Text(item.name).font(.caption2).lineLimit(2)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .opacity(0.6)
                    }
                }
            }
            .padding(12)
        }
    }

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 104)
            .padding(8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Button {
                        path = Array(path.prefix(index + 1))
                    } label: {
                        Text(node.name).font(.caption).lineLimit(1)
                    }
                }
            }
        }
        .frame(height: 22)
    }

    private func open(_ item: KDriveItem) {
        guard let kind = item.mediaKind else { return }
        let mediaKind: MediaKind = kind == .image ? .image : (kind == .audio ? .audio : .video)
        playing = MediaItem(
            id: "kdrive-\(item.id)", title: item.name, subtitle: "kDrive",
            kind: mediaKind, resource: nil,
            url: KDriveClient.downloadURL(config: model.config, fileID: item.id),
            headers: ["Authorization": "Bearer \(model.config.token)"],
            loader: { try await model.download(item) })
    }
}

private struct KDriveThumbnail: View {
    let url: URL
    let token: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            }
        }
        .frame(height: 88)
        .frame(maxWidth: .infinity)
        .clipped()
        .task(id: url) {
            guard image == nil else { return }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let loaded = UIImage(data: data), !Task.isCancelled else { return }
            image = loaded
        }
    }
}
