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
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspectFill
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.onError = onError
        context.coordinator.setActive(active)
        // Assigned after the activation, and nil until then: `AVPlayer(url:)` begins
        // fetching the moment it exists, and a lazy stack holds several cards at once,
        // so every off-screen video used to start downloading for nobody.
        controller.player = context.coordinator.player
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.teardown()
        controller.player = nil
    }

    final class Coordinator {
        let url: URL
        private(set) var player: AVPlayer?
        var onError: () -> Void = {}
        private var active = false
        private var endObserver: NSObjectProtocol?
        private var failedObserver: NSObjectProtocol?
        private var statusObservation: NSKeyValueObservation?

        init(url: URL) { self.url = url }

        deinit { teardown() }

        /// Built on first activation rather than at construction.
        private func makePlayer() -> AVPlayer {
            let created = AVPlayer(url: url)
            created.actionAtItemEnd = .none
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: created.currentItem,
                queue: .main
            ) { [weak created] _ in
                created?.seek(to: .zero)
                created?.play()
            }
            failedObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: created.currentItem,
                queue: .main
            ) { [weak self] _ in
                self?.onError()
            }
            statusObservation = created.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
                if item.status == .failed {
                    DispatchQueue.main.async { self?.onError() }
                }
            }
            return created
        }

        func teardown() {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
            if let failedObserver {
                NotificationCenter.default.removeObserver(failedObserver)
                self.failedObserver = nil
            }
            statusObservation?.invalidate()
            statusObservation = nil
            player = nil
        }

        func setActive(_ value: Bool) {
            guard active != value else { return }
            active = value
            if value {
                if player == nil { player = makePlayer() }
                player?.play()
            } else {
                player?.pause()
            }
        }
    }
}
