import AVFoundation
import SwiftUI
import UIKit

/// Full-screen video player. Streams from a resolved URL, native controls, tap the
/// close button to leave. No bytes pass through the app.
struct VideoPlayerScreen: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoSurface(player: player)
                    .ignoresSafeArea()
            } else if failed {
                ContentUnavailableView("Lecture impossible", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
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
            guard player == nil, !failed else { return }
            do {
                let url = try await resolve()
                let av = AVPlayer(url: url)
                av.actionAtItemEnd = .none
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime, object: av.currentItem, queue: .main) { _ in
                        av.seek(to: .zero)
                        av.play()
                    }
                av.play()
                player = av
            } catch {
                failed = true
            }
        }
        .onDisappear { player?.pause() }
    }

    private func resolve() async throws -> URL {
        if let streamURL = item.streamURL { return try await streamURL() }
        guard let remote = item.url else { throw CocoaError(.fileNoSuchFile) }
        return remote
    }
}

/// A signed kDrive URL carries no auth header, so the player asset must not need one.
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
