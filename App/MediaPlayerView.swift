import AVFoundation
import SwiftUI
import UIKit

/// Plays one bundled or streamed media file. Audio has no system control centre
/// integration and no background mode: the app is unsigned and foreground-only.
struct MediaPlayerView: View {
    let item: MediaItem
    @State private var player: AVPlayer?
    @State private var image: UIImage?
    @State private var playing = false
    @State private var failed = false

    var body: some View {
        Group {
            if item.kind == .image {
                imageBody
            } else {
                playerBody
            }
        }
        .frame(maxWidth: 600).frame(maxWidth: .infinity)
        .padding()
        .navigationTitle("Lecture")
        .navigationBarTitleDisplayMode(.inline)
        .privacyMask()
        .task {
            if item.kind == .image {
                await loadImage()
            } else {
                guard player == nil, !failed else { return }
                do {
                    player = try await makePlayer()
                    player?.play()
                    playing = true
                } catch { failed = true }
            }
        }
        .onDisappear { player?.pause() }
    }

    private var imageBody: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if failed {
                ContentUnavailableView("Image indisponible", systemImage: "photo")
                    .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
    }

    private var playerBody: some View {
        VStack(spacing: 24) {
            if let player {
                VStack(spacing: 8) {
                    Text(item.title).font(.headline).multilineTextAlignment(.center)
                    Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                Slider(value: Binding(
                    get: { position(player) },
                    set: { player.seek(to: CMTime(seconds: $0, preferredTimescale: 600)) }
                ), in: 0...max(duration(player), 1))
                .disabled(duration(player) <= 0)

                Text("\(format(position(player))) / \(format(duration(player)))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)

                HStack(spacing: 32) {
                    Button { seek(player, by: -15) } label: {
                        Image(systemName: "gobackward.15").frame(minWidth: 44, minHeight: 44)
                    }
                    Button { toggle() } label: {
                        Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                    }
                    Button { seek(player, by: 15) } label: {
                        Image(systemName: "goforward.15").frame(minWidth: 44, minHeight: 44)
                    }
                }
                .foregroundStyle(.teal)
            } else {
                ContentUnavailableView(failed ? "Lecture impossible" : "Chargement…",
                                        systemImage: failed ? "exclamationmark.triangle" : "waveform")
            }
        }
    }

    private func makePlayer() async throws -> AVPlayer {
        if let resource = item.resource,
           let url = Bundle.main.url(forResource: resource, withExtension: item.kind == .audio ? "m4a" : "mp4") {
            return AVPlayer(url: url)
        }
        guard let remote = item.url else { throw CocoaError(.fileNoSuchFile) }
        let cached = FileManager.default.temporaryDirectory.appending(path: "\(item.id).media")
        var request = URLRequest(url: remote)
        for (field, value) in item.headers { request.setValue(value, forHTTPHeaderField: field) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try data.write(to: cached, options: .atomic)
        return AVPlayer(url: cached)
    }

    private func loadImage() async {
        guard let remote = item.url else { failed = true; return }
        var request = URLRequest(url: remote)
        for (field, value) in item.headers { request.setValue(value, forHTTPHeaderField: field) }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let image = UIImage(data: data), !Task.isCancelled else {
            failed = true
            return
        }
        self.image = image
    }

    private func position(_ player: AVPlayer?) -> Double {
        let seconds = player?.currentTime().seconds ?? 0
        return (seconds.isFinite && seconds > 0) ? seconds : 0
    }

    private func duration(_ player: AVPlayer?) -> Double {
        let seconds = player?.currentItem?.asset.duration.seconds ?? 0
        return (seconds.isFinite && seconds > 0) ? seconds : 0
    }

    private func seek(_ player: AVPlayer?, by offset: Double) {
        guard let player else { return }
        let target = min(max(0, position(player) + offset), duration(player))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    private func toggle() {
        guard let player else { return }
        if playing {
            player.pause()
        } else {
            player.play()
        }
        playing.toggle()
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
