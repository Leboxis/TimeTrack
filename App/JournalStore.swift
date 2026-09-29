import Foundation
import Observation
import WellbeingCore

@MainActor @Observable
final class JournalStore {
    private(set) var sessions: [Session] = []
    private(set) var loadFailed = false
    /// Records that could not be read back while recovering a damaged journal.
    private(set) var rejectedCount = 0
    var errorMessage: String?
    private let fileURL: URL

    init() {
        let directory = URL.documentsDirectory.appending(path: "Wellbeing", directoryHint: .isDirectory)
        fileURL = directory.appending(path: "journal.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                do {
                    sessions = try Journal.decode(data)
                } catch {
                    // Strict decoding failed. Salvage the readable records so the journal
                    // stays visible and exportable, but keep every mutation disabled so
                    // the damaged file is never silently rewritten.
                    let recovered = Journal.decodeRecovering(data)
                    sessions = recovered.sessions
                    rejectedCount = recovered.rejected
                    loadFailed = true
                    errorMessage = loadFailureMessage
                }
            }
        } catch {
            loadFailed = true
            errorMessage = "Lecture impossible. Le journal existant est conservé. \(error.localizedDescription)"
        }
    }

    var loadFailureMessage: String {
        if sessions.isEmpty {
            return "Le journal est illisible et aucune séance n’a pu être récupérée. Le fichier n’a pas été modifié. Vous pouvez le réinitialiser depuis Réglages."
        }
        return "\(sessions.count) séance(s) récupérée(s), \(rejectedCount) illisible(s). Le fichier n’a pas été modifié : exportez-le depuis Réglages avant toute réinitialisation."
    }

    /// Deliberately ignores `loadFailed`: the user asked to start over, which is the
    /// only way to replace a file that strict decoding can no longer read.
    @discardableResult func resetJournal() -> Bool {
        do {
            try Journal.encode([]).write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            sessions = []
            rejectedCount = 0
            loadFailed = false
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Réinitialisation impossible. \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult func save(_ session: Session) -> Bool {
        guard !loadFailed else { return false }
        var updated = sessions.filter { $0.id != session.id }
        updated.append(session)
        return persist(updated)
    }

    func delete(_ id: UUID) {
        guard !loadFailed else { return }
        _ = persist(sessions.filter { $0.id != id })
    }

    @discardableResult func deleteAll() -> Bool {
        guard !loadFailed else { return false }
        return persist([])
    }

    private func persist(_ updated: [Session]) -> Bool {
        do {
            let data = try Journal.encode(updated)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            sessions = updated.sorted { $0.date > $1.date }
            return true
        } catch {
            errorMessage = "Enregistrement impossible. \(error.localizedDescription)"
            return false
        }
    }
}

@MainActor @Observable
final class SessionTimer {
    private(set) var draft: TimerDraft
    private let key = "wellbeing.timer.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: "wellbeing.timer.v1"),
           let saved = try? JSONDecoder().decode(TimerDraft.self, from: data),
           saved.accumulated.isFinite, (0...86_400).contains(saved.accumulated) {
            draft = saved
        } else {
            draft = TimerDraft()
        }
    }

    func toggle() {
        if draft.startedAt == nil { draft.start() } else { draft.pause() }
        persist()
    }
    func pause() { draft.pause(); persist() }
    func reset() { draft = TimerDraft(); persist() }
    private func persist() {
        if let data = try? JSONEncoder().encode(draft) { UserDefaults.standard.set(data, forKey: key) }
    }
}
