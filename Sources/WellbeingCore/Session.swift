import Foundation

public enum Ejaculation: String, Codable, CaseIterable {
    case aucune, baveuse, jet

    public var label: String {
        switch self {
        case .aucune: return "Aucune"
        case .baveuse: return "Baveuse"
        case .jet: return "Jet"
        }
    }
}

public struct Session: Identifiable, Codable, Equatable {
    public var id: UUID
    public var date: Date
    public var duration: TimeInterval
    public var feeling: Int
    public var orgasm: Int
    public var mental: Int
    public var ejaculation: Ejaculation
    /// Whether this session involved pornography. Absent from journals written before the
    /// field existed, so it decodes as `false` and those days count as clean.
    public var hasPorn: Bool
    public var notes: String

    public init(id: UUID = UUID(), date: Date = Date(), duration: TimeInterval,
                feeling: Int = 3, orgasm: Int = 3, mental: Int = 3,
                ejaculation: Ejaculation = .aucune, hasPorn: Bool = false,
                notes: String = "") {
        self.id = id
        self.date = date
        self.duration = duration
        self.feeling = feeling
        self.orgasm = orgasm
        self.mental = mental
        self.ejaculation = ejaculation
        self.hasPorn = hasPorn
        self.notes = notes
    }

    /// Hand-written so a journal written before 1.4.0, which has no `orgasm`, `mental`
    /// or `ejaculation` key, still decodes instead of failing the whole file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        feeling = try container.decode(Int.self, forKey: .feeling)
        orgasm = try container.decodeIfPresent(Int.self, forKey: .orgasm) ?? 3
        mental = try container.decodeIfPresent(Int.self, forKey: .mental) ?? 3
        ejaculation = try container.decodeIfPresent(Ejaculation.self, forKey: .ejaculation) ?? .aucune
        // `try?` around `decodeIfPresent`, because `decodeIfPresent` alone only tolerates a
        // *missing* key: a hand-edited `"hasPorn": "oui"` throws `typeMismatch`, which
        // would fail the whole journal and cost the user every session in it.
        hasPorn = (try? container.decodeIfPresent(Bool.self, forKey: .hasPorn)) ?? false
        notes = try container.decode(String.self, forKey: .notes)
    }

    public var isValid: Bool {
        duration.isFinite && duration >= 1 && duration <= 86_400
            && (1...5).contains(feeling) && (1...5).contains(orgasm) && (1...5).contains(mental)
            && notes.count <= 10_000
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
        // A record can decode cleanly and still be out of range, which used to be caught
        // by re-encoding the whole journal purely to validate it and throwing the bytes
        // away. The same checks, without the serialisation.
        guard sessions.allSatisfy(\.isValid),
              Set(sessions.map(\.id)).count == sessions.count else {
            throw JournalError.invalidData
        }
        return sessions.sorted { $0.date > $1.date }
    }

    /// Salvage pass for a journal that fails strict decoding: keeps every record that
    /// can be read back instead of hiding the whole history behind one bad entry.
    /// A file that is not a JSON array at all yields nothing to recover.
    public static func decodeRecovering(_ data: Data) -> (sessions: [Session], rejected: Int) {
        guard let records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return ([], 0)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var seen = Set<UUID>()
        var sessions: [Session] = []
        var rejected = 0
        for record in records {
            guard let raw = try? JSONSerialization.data(withJSONObject: record),
                  let session = try? decoder.decode(Session.self, from: raw),
                  session.isValid, seen.insert(session.id).inserted else {
                rejected += 1
                continue
            }
            sessions.append(session)
        }
        return (sessions.sorted { $0.date > $1.date }, rejected)
    }

    public static func csv(_ sessions: [Session]) -> String {
        let formatter = ISO8601DateFormatter()
        let rows = sessions.sorted { $0.date < $1.date }.map { session in
            [formatter.string(from: session.date), String(session.duration),
             String(session.feeling), String(session.orgasm), String(session.mental),
             session.ejaculation.rawValue,
             session.hasPorn ? "1" : "0",
             safeCSVField(session.notes)].joined(separator: ",")
        }
        return "date_utc,duree_secondes,ressenti_sur_5,orgasme_sur_5,ressenti_mental_sur_5,type_ejaculation,avec_porno,notes\r\n" + rows.joined(separator: "\r\n")
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

/// /// The five bands a 1-5 rating falls into.
///
/// Deliberately free of SwiftUI: the clamping rule is the part worth testing, and it
/// lives in the package where `swift test` can reach it. The colour itself belongs to
/// the app layer.
public enum RatingBand: Int, CaseIterable, Sendable {
    case lowest = 1, low, middle, high, highest

    /// Out-of-range ratings are clamped to an end rather than rejected, so a legacy or
    /// hand-edited record still gets a colour instead of none.
    public init(value: Int) {
        self = RatingBand(rawValue: min(5, max(1, value))) ?? .middle
    }

    /// Position along the red-to-green ramp, 0...1.
    public var intensity: Double { Double(rawValue - 1) / 4 }
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
