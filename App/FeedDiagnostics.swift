import Foundation
import Observation

/// Records what the feed requests actually did on the device: HTTP status, whether a
/// Reddit session cookie was attached, which cookies exist, and the rate-limit headers.
/// Without this there is no way to tell a missing cookie from a rate-limited IP.
@MainActor @Observable
final class FeedDiagnostics {
    static let shared = FeedDiagnostics()

    private(set) var lines: [String] = []
    private(set) var rateLimitedUntil: Date?

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Returns false when Reddit is still cooling down, so a refresh cannot be wasted.
    func rateLimited() -> Bool {
        guard let until = rateLimitedUntil, until > Date() else { return false }
        return true
    }

    func cooldown(from headers: [AnyHashable: Any], now: Date = Date()) {
        let seconds = (headers["x-ratelimit-reset"] as? String).flatMap(Double.init) ?? 30
        rateLimitedUntil = now.addingTimeInterval(max(5, seconds))
    }

    func record(_ line: String) {
        lines.insert("\(Self.formatter.string(from: Date()))  \(line)", at: 0)
        if lines.count > 24 { lines.removeLast(lines.count - 24) }
    }

    func reset() {
        lines.removeAll()
        rateLimitedUntil = nil
    }
}
