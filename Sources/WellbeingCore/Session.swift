import Foundation

public struct Session: Identifiable, Codable, Equatable {
    public var id: UUID
    public var date: Date
    public var duration: TimeInterval
    public var feeling: Int
    public var notes: String

    public init(id: UUID = UUID(), date: Date = Date(), duration: TimeInterval,
                feeling: Int = 3, notes: String = "") {
        self.id = id
        self.date = date
        self.duration = duration
        self.feeling = feeling
        self.notes = notes
    }

    public var isValid: Bool {
        duration.isFinite && duration > 0 && duration <= 86_400
            && (1...5).contains(feeling) && notes.count <= 10_000
            && date.timeIntervalSince1970.isFinite
    }
}

public enum JournalError: LocalizedError {
    case invalidData
    public var errorDescription: String? {
        "Les données du journal sont invalides. Le fichier existant a été conservé."
    }
}

public enum Journal {
    public static func encode(_ sessions: [Session]) throws -> Data {
        guard sessions.allSatisfy(\.isValid), Set(sessions.map(\.id)).count == sessions.count else {
            throw JournalError.invalidData
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(sessions)
    }

    public static func decode(_ data: Data) throws -> [Session] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sessions = try decoder.decode([Session].self, from: data)
        _ = try encode(sessions)
        return sessions.sorted { $0.date > $1.date }
    }

    public static func csv(_ sessions: [Session]) -> String {
        let formatter = ISO8601DateFormatter()
        let rows = sessions.sorted { $0.date < $1.date }.map { session in
            [formatter.string(from: session.date), String(session.duration),
             String(session.feeling), safeCSVField(session.notes)].joined(separator: ",")
        }
        return "date_utc,duree_secondes,ressenti_sur_5,notes\r\n" + rows.joined(separator: "\r\n")
    }

    private static func safeCSVField(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let guarded = trimmed.first.map { "=+-@".contains($0) } == true ? "'" + text : text
        return "\"" + guarded.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

public struct TimerDraft: Codable, Equatable {
    public var accumulated: TimeInterval = 0
    public var startedAt: Date?
    public init() {}
    public func elapsed(at date: Date = Date()) -> TimeInterval {
        min(86_400, max(0, accumulated + (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)))
    }
    public mutating func start(at date: Date = Date()) {
        guard startedAt == nil else { return }
        startedAt = date
    }
    public mutating func pause(at date: Date = Date()) {
        accumulated = elapsed(at: date)
        startedAt = nil
    }
}

public func durationLabel(_ seconds: TimeInterval) -> String {
    let total = Int(min(86_400, max(0, seconds.isFinite ? seconds : 0)))
    if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
    return String(format: "%02d:%02d", total / 60, total % 60)
}

/// Resolve the chart's continuous date axis to a stable record, including tied dates.
public func nearestSession(to date: Date, in sessions: [Session]) -> Session? {
    sessions.min { left, right in
        let leftDistance = abs(left.date.timeIntervalSince(date))
        let rightDistance = abs(right.date.timeIntervalSince(date))
        if leftDistance != rightDistance { return leftDistance < rightDistance }
        if left.date != right.date { return left.date < right.date }
        return left.id.uuidString < right.id.uuidString
    }
}
