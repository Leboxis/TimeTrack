import AVFoundation
import AVKit
import SwiftUI

/// Plays one streaming URL, looping, driven by whether its card is visible.
/// Reports playback failures through `onError` so the card can show its error state.
struct AutoPlayVideo: UIViewControllerRepresentable {
    let url: URL
    let active: Bool
    var onError: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = context.coordinator.player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspectFill
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.onError = onError
        context.coordinator.setActive(active)
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.player.pause()
        coordinator.player.replaceCurrentItem(with: nil)
        controller.player = nil
    }

    final class Coordinator {
        let player: AVPlayer
        var onError: () -> Void = {}
        private var active = false
        private var endObserver: NSObjectProtocol?
        private var failedObserver: NSObjectProtocol?
        private var statusObservation: NSKeyValueObservation?

        init(url: URL) {
            player = AVPlayer(url: url)
            player.actionAtItemEnd = .none
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
            failedObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak self] _ in
                self?.onError()
            }
            statusObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
                if item.status == .failed {
                    DispatchQueue.main.async { self?.onError() }
                }
            }
        }

        deinit {
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            if let failedObserver { NotificationCenter.default.removeObserver(failedObserver) }
        }

        func setActive(_ value: Bool) {
            guard active != value else { return }
            active = value
            if value { player.play() } else { player.pause() }
        }
    }
}
