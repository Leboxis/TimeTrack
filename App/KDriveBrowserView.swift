import ImageIO
import SwiftUI
import UIKit
import WellbeingCore

/// One level of the kDrive path, for the breadcrumb.
struct KDrivePathNode: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Grid of kDrive items. Every tile has the same geometry whatever the media, so the
/// name always sits in its own band and never overlaps a neighbour.
struct KDriveBrowserView: View {
    @State private var model = KDriveModel()
    @State private var path: [KDrivePathNode] = [KDrivePathNode(id: "1", name: "Racine")]
    @State private var playing: MediaItem?
    @State private var watching: MediaItem?

    private let spacing: CGFloat = 10
    private let padding: CGFloat = 12
    private let minimumTile: CGFloat = 104
    private let labelHeight: CGFloat = 30

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
        .fullScreenCover(item: $watching) { VideoPlayerScreen(item: $0) }
        .privacyMask()
    }

    private var grid: some View {
        GeometryReader { proxy in
            let available = proxy.size.width - 2 * padding
            // Never more than three across: wider tiles stay tappable and the name band
            // has room for a real file name.
            let count = min(3, max(1, Int((available + spacing) / (minimumTile + spacing))))
            let tile = (available - spacing * CGFloat(count - 1)) / CGFloat(count)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(tile), spacing: spacing), count: count),
                          spacing: spacing) {
                    ForEach(model.items) { item in
                        cell(item, size: tile)
                            .transition(.scale(scale: 0.88).combined(with: .opacity))
                    }
                }
                .padding(padding)
            }
            // Re-keyed on the folder so entering a subfolder zooms in and going back
            // zooms out, instead of a cross-dissolve that hides which tile was tapped.
            .id(current.id)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.92).combined(with: .opacity),
                removal: .scale(scale: 1.06).combined(with: .opacity)))
        }
        .animation(.snappy(duration: 0.28), value: current.id)
    }

    @ViewBuilder
    private func cell(_ item: KDriveItem, size: CGFloat) -> some View {
        VStack(spacing: 0) {
            mediaArea(for: item, size: size)
                .frame(height: size)
                .frame(maxWidth: .infinity)
                .clipped()
            Text(item.name)
                .font(.caption2)
                .foregroundStyle(item.isDirectory ? .primary : .secondary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .frame(height: labelHeight, alignment: .top)
                .padding(.top, 5)
        }
        .frame(width: size)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if item.mediaKind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white, .black.opacity(0.4))
                    .padding(6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isDirectory {
                withAnimation(.snappy(duration: 0.28)) {
                    path.append(KDrivePathNode(id: String(item.id), name: item.name))
                }
            } else {
                open(item)
            }
        }
    }

    @ViewBuilder
    private func mediaArea(for item: KDriveItem, size: CGFloat) -> some View {
        if item.isDirectory {
            Image(systemName: "folder.fill")
                .font(.system(size: 30))
                .foregroundStyle(.teal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if item.mediaKind != nil {
            KDriveThumbnail(url: KDriveClient.thumbnailURL(config: model.config, fileID: item.id),
                            token: model.config.token, maxPixels: Int(size * 3))
        } else {
            Image(systemName: "doc")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Button {
                        withAnimation(.snappy(duration: 0.28)) {
                            path = Array(path.prefix(index + 1))
                        }
                    } label: {
                        Text(node.name).font(.caption).lineLimit(1)
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        }
        .frame(height: 22)
    }

    private func open(_ item: KDriveItem) {
        guard let kind = item.mediaKind else { return }
        let mediaKind: MediaKind = kind == .image ? .image : (kind == .audio ? .audio : .video)
        let entry = MediaItem(
            id: "kdrive-\(item.id)", title: item.name, subtitle: "kDrive",
            kind: mediaKind, resource: nil,
            url: KDriveClient.downloadURL(config: model.config, fileID: item.id),
            // Resolved to a signed URL, then streamed. AVPlayer handles the redirect
            // chain and ranges the file, so no bytes pass through the app.
            streamURL: { try await self.model.streamURL(for: item) })
        if kind == .video {
            watching = entry
        } else {
            playing = entry
        }
    }
}

/// Square thumbnail, decoded downsampled so a large source never bloats memory.
private struct KDriveThumbnail: View {
    let url: URL
    let token: String
    let maxPixels: Int
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url) {
            guard image == nil else { return }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixels)
                  ] as CFDictionary),
                  !Task.isCancelled else { return }
            self.image = UIImage(cgImage: cg)
        }
    }
}
