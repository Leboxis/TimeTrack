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
    public var notes: String

    public init(id: UUID = UUID(), date: Date = Date(), duration: TimeInterval,
                feeling: Int = 3, orgasm: Int = 3, mental: Int = 3,
                ejaculation: Ejaculation = .aucune, notes: String = "") {
        self.id = id
        self.date = date
        self.duration = duration
        self.feeling = feeling
        self.orgasm = orgasm
        self.mental = mental
        self.ejaculation = ejaculation
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
        _ = try encode(sessions)
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
             safeCSVField(session.notes)].joined(separator: ",")
        }
        return "date_utc,duree_secondes,ressenti_sur_5,orgasme_sur_5,ressenti_mental_sur_5,type_ejaculation,notes\r\n" + rows.joined(separator: "\r\n")
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
