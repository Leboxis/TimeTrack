import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// Full-screen video player. Streams from a resolved URL, native controls, tap the
/// close button to leave. No bytes pass through the app.
struct VideoPlayerScreen: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    /// Created empty on appear so the view controller exists and the screen responds to
    /// the tap immediately; the item is attached as soon as the signed URL resolves.
    @State private var player = AVPlayer()
    @State private var resolving = true
    @State private var failed = false
    /// Held so it can be removed. The token used to be thrown away while the closure
    /// captured the player strongly, so every video opened leaked a player, its item
    /// and its buffer — and the loop-back kept firing on all of them.
    @State private var endObserver: Any?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if failed {
                ContentUnavailableView("Lecture impossible", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.white)
            } else {
                VideoSurface(player: player)
                    .ignoresSafeArea()
                    .overlay {
                        if resolving {
                            ProgressView().tint(.white).scaleEffect(1.4)
                        }
                    }
            }
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Label("Fermer", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .font(.headline)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding()
                Spacer()
            }
        }
        .privacyMask()
        .task {
            guard resolving, !failed else { return }
            do {
                let item = AVPlayerItem(url: try await resolve())
                player.replaceCurrentItem(with: item)
                player.actionAtItemEnd = .none
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak player] _ in
                        player?.seek(to: .zero)
                        player?.play()
                    }
                player.play()
                resolving = false
            } catch {
                failed = true
            }
        }
        .onDisappear { teardown() }
    }

    private func teardown() {
        player.pause()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func resolve() async throws -> URL {
        if let streamURL = item.streamURL { return try await streamURL() }
        guard let remote = item.url else { throw CocoaError(.fileNoSuchFile) }
        return remote
    }
}

/// A resolved streaming URL carries no auth header, so the player asset must not need one.
private struct VideoSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}
