import SwiftUI
import WellbeingCore

/// One level of the kDrive path, for the breadcrumb.
struct KDrivePathNode: Identifiable, Hashable {
    let id: String
    let name: String
}

struct KDriveBrowserView: View {
    @State private var model = KDriveModel()
    @State private var path: [KDrivePathNode] = [KDrivePathNode(id: "1", name: "Racine")]
    @State private var playing: MediaItem?
    @State private var showImage = false

    private var current: KDrivePathNode { path[path.count - 1] }

    var body: some View {
        List {
            if model.loading && model.items.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let message = model.errorMessage {
                ContentUnavailableView("kDrive indisponible", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(message))
                Button("Réessayer") { Task { await model.load(directoryID: current.id) } }
            } else if model.items.isEmpty {
                ContentUnavailableView("Dossier vide", systemImage: "folder",
                    description: Text("Ce dossier ne contient aucun fichier lisible."))
            }
            ForEach(model.items) { item in
                if item.isDirectory {
                    Button {
                        path.append(KDrivePathNode(id: String(item.id), name: item.name))
                    } label: {
                        row(icon: "folder.fill", title: item.name, tint: .teal)
                    }
                } else if item.mediaKind != nil {
                    Button {
                        open(item)
                    } label: {
                        row(icon: icon(for: item.mediaKind!), title: item.name,
                             tint: .secondary, detail: ByteCountFormatter.string(fromByteCount: Int64(item.size ?? 0), countStyle: .file))
                    }
                } else {
                    row(icon: "doc", title: item.name, tint: .secondary)
                }
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                breadcrumb
            }
        }
        .task(id: current.id) { await model.load(directoryID: current.id) }
        .sheet(item: $playing) { MediaPlayerView(item: $0) }
        .privacyMask()
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(node.name).font(.caption).lineLimit(1)
                }
            }
        }
        .frame(height: 22)
    }

    private func open(_ item: KDriveItem) {
        guard let kind = item.mediaKind else { return }
        let mediaKind: MediaKind
        switch kind {
        case .image: mediaKind = .image
        case .video: mediaKind = .video
        case .audio: mediaKind = .audio
        }
        playing = MediaItem(
            id: "kdrive-\(item.id)", title: item.name, subtitle: "kDrive",
            kind: mediaKind, resource: nil,
            url: KDriveClient.downloadURL(config: model.config, fileID: item.id),
            headers: ["Authorization": "Bearer \(model.config.token)"])
    }

    private func icon(for kind: KDriveMediaKind) -> String {
        switch kind {
        case .image: "photo"
        case .video: "play.rectangle"
        case .audio: "waveform"
        }
    }

    private func row(icon: String, title: String, tint: Color, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
