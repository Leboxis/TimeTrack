import AVFoundation
import SwiftUI
import UIKit
import WellbeingCore

/// Plays one bundled or streamed media file. Audio has no system control centre
/// integration and no background mode: the app is unsigned and foreground-only.
struct MediaPlayerView: View {
    let item: MediaItem
    /// Offered only when presented modally. A pushed view already has a back button, and
    /// two dismissals in one bar is a trap rather than a convenience.
    var showsCloseButton = false
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var image: UIImage?
    @State private var playing = false
    @State private var failed = false
    /// Playback time and asset length, kept in state by a periodic observer. Reading
    /// them straight from the player in `body` returned a value nothing had changed, so
    /// the clock stayed at 00:00 and the slider never moved.
    @State private var position: Double = 0
    @State private var duration: Double = 0
    /// Retained so it can be removed on the way out.
    @State private var timeObserver: Any?

    /// Enough for a 3x phone screen without decoding a 48-megapixel original.
    private static let imagePixelCap = 2560

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
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .privacyMask()
        .task {
            if item.kind == .image {
                await loadImage()
            } else {
                await startPlayback()
            }
        }
        .onDisappear { teardown() }
    }

    private var imageBody: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if failed {
                VStack(spacing: 16) {
                    ContentUnavailableView("Image indisponible", systemImage: "photo")
                        .foregroundStyle(.white)
                    Button("Réessayer") { Task { await loadImage() } }
                        .buttonStyle(.borderedProminent).tint(.white)
                }
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
                    get: { position },
                    set: { target in
                        position = target
                        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
                    }),
                    in: 0...max(duration, 1))
                .disabled(duration <= 0)

                Text("\(durationLabel(position)) / \(durationLabel(duration))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)

                HStack(spacing: 32) {
                    Button { seek(by: -15) } label: {
                        Image(systemName: "gobackward.15").frame(minWidth: 44, minHeight: 44)
                    }
                    Button { toggle() } label: {
                        Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                    }
                    Button { seek(by: 15) } label: {
                        Image(systemName: "goforward.15").frame(minWidth: 44, minHeight: 44)
                    }
                }
                .foregroundStyle(.teal)
            } else {
                VStack(spacing: 16) {
                    ContentUnavailableView(failed ? "Lecture impossible" : "Chargement…",
                                            systemImage: failed ? "exclamationmark.triangle" : "waveform")
                    if failed {
                        Button("Réessayer") {
                            failed = false
                            Task { await startPlayback() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func startPlayback() async {
        guard player == nil, !failed else { return }
        do {
            let created = try await makePlayer()
            player = created
            position = 0
            duration = Self.knownDuration(of: created)
            observeTime(on: created)
            created.play()
            playing = true
        } catch {
            failed = true
        }
    }

    private func makePlayer() async throws -> AVPlayer {
        if let resource = item.resource,
           let url = Bundle.main.url(forResource: resource, withExtension: item.kind == .audio ? "m4a" : "mp4") {
            return AVPlayer(url: url)
        }
        guard item.url != nil || item.streamURL != nil else { throw CocoaError(.fileNoSuchFile) }
        return AVPlayer(url: try await resolvedURL())
    }

    /// Streaming source. AVPlayer follows the redirect chain itself and ranges the
    /// file, so nothing is buffered in full and no bytes pass through the app.
    private func resolvedURL() async throws -> URL {
        if let streamURL = item.streamURL { return try await streamURL() }
        guard let remote = item.url else { throw CocoaError(.fileNoSuchFile) }
        return remote
    }

    private func loadImage() async {
        failed = false
        guard item.url != nil || item.streamURL != nil else { failed = true; return }
        guard let url = try? await resolvedURL(), !Task.isCancelled else {
            failed = true
            return
        }
        var request = URLRequest(url: url)
        for (field, value) in item.headers { request.setValue(value, forHTTPHeaderField: field) }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let decoded = await ImageDecoder.image(from: data, maxPixels: Self.imagePixelCap),
              !Task.isCancelled else {
            failed = true
            return
        }
        image = decoded
    }

    /// A remote asset has no duration at first render, so the seek control was disabled
    /// on a value that never changed and stayed disabled for the whole playback.
    private func observeTime(on player: AVPlayer) {
        let observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { time in
            let seconds = time.seconds
            if seconds.isFinite, seconds >= 0 { self.position = seconds }
            let total = Self.knownDuration(of: player)
            if total > 0 { self.duration = total }
        }
        timeObserver = observer
    }

    private static func knownDuration(of player: AVPlayer) -> Double {
        let seconds = player.currentItem?.asset.duration.seconds ?? 0
        return (seconds.isFinite && seconds > 0) ? seconds : 0
    }

    private func teardown() {
        player?.pause()
        playing = false
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func seek(by offset: Double) {
        guard let player else { return }
        let target = min(max(0, position + offset), duration)
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
}
