import AVFoundation
import AVKit
import SwiftUI

/// Plays one streaming URL, looping, driven by whether its card is visible.
struct AutoPlayVideo: UIViewControllerRepresentable {
    let url: URL
    let active: Bool

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = context.coordinator.player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspectFill
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.setActive(active)
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.player.pause()
        coordinator.player.replaceCurrentItem(with: nil)
        controller.player = nil
    }

    final class Coordinator {
        let player: AVPlayer
        private var active = false
        private var observer: NSObjectProtocol?

        init(url: URL) {
            player = AVPlayer(url: url)
            player.actionAtItemEnd = .none
            observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func setActive(_ value: Bool) {
            guard active != value else { return }
            active = value
            if value { player.play() } else { player.pause() }
        }
    }
}
