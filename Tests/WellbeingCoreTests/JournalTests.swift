import XCTest
@testable import WellbeingCore

final class JournalTests: XCTestCase {
    func testChartSelectionEmptySingleAndBetweenDates() {
        let early = Session(date: Date(timeIntervalSince1970: 100), duration: 10)
        let late = Session(date: Date(timeIntervalSince1970: 200), duration: 20)
        XCTAssertNil(nearestSession(to: .now, in: []))
        XCTAssertEqual(nearestSession(to: .distantFuture, in: [early])?.id, early.id)
        XCTAssertEqual(nearestSession(to: Date(timeIntervalSince1970: 180), in: [early, late])?.id, late.id)
        XCTAssertEqual(nearestSession(to: Date(timeIntervalSince1970: 150), in: [late, early])?.id, early.id)
    }

    func testChartSelectionTiedDatesHasStableIdentity() {
        let date = Date(timeIntervalSince1970: 100)
        let first = Session(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: date, duration: 10)
        let second = Session(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, date: date, duration: 20)
        XCTAssertEqual(nearestSession(to: date, in: [second, first])?.id, first.id)
        XCTAssertEqual(nearestSession(to: date, in: [first, second])?.id, first.id)
    }

    func testJournalRoundTripPreservesContentAndSortsNewestFirst() throws {
        let first = Session(date: Date(timeIntervalSince1970: 100), duration: 42, notes: "Calme, reposé")
        let second = Session(date: Date(timeIntervalSince1970: 200), duration: 75, feeling: 5)
        XCTAssertEqual(try Journal.decode(Journal.encode([first, second])), [second, first])
    }

    func testRejectsInvalidAndDuplicateRecords() {
        for duration in [0, -1, Double.infinity, 86_401] {
            XCTAssertThrowsError(try Journal.encode([Session(duration: duration)]))
        }
        XCTAssertThrowsError(try Journal.encode([Session(duration: 10, feeling: 6)]))
        let session = Session(duration: 10)
        XCTAssertThrowsError(try Journal.encode([session, session]))
        XCTAssertThrowsError(try Journal.decode(Data("broken".utf8)))
    }

    func testRejectsSubSecondDurations() throws {
        XCTAssertThrowsError(try Journal.encode([Session(duration: 0.4)]))
        XCTAssertNoThrow(try Journal.encode([Session(duration: 1)]))
    }

    func testRecoveryKeepsReadableRecordsWhenStrictDecodingFails() throws {
        let keeper = Session(date: Date(timeIntervalSince1970: 100), duration: 42, notes: "Intacte")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode([keeper])
        var objects = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        let outOfRange: [String: Any] = [
            "id": UUID().uuidString,
            "date": "2024-01-01T00:00:00Z",
            "duration": 99_999,
            "feeling": 3,
            "notes": "Hors limites"
        ]
        objects.append(outOfRange)
        let data = try JSONSerialization.data(withJSONObject: objects)

        XCTAssertThrowsError(try Journal.decode(data))
        let recovered = Journal.decodeRecovering(data)
        XCTAssertEqual(recovered.sessions, [keeper])
        XCTAssertEqual(recovered.rejected, 1)
    }

    func testRecoveryDropsDuplicatesAndSortsNewestFirst() throws {
        let older = Session(date: Date(timeIntervalSince1970: 100), duration: 10)
        let newer = Session(date: Date(timeIntervalSince1970: 200), duration: 20)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let objects = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try encoder.encode([older, newer, newer])) as? [[String: Any]])
        XCTAssertEqual(objects.count, 3)

        let recovered = Journal.decodeRecovering(try JSONSerialization.data(withJSONObject: objects))
        XCTAssertEqual(recovered.rejected, 1)
        XCTAssertEqual(recovered.sessions.map(\.id), [newer.id, older.id])
    }

    func testRecoveryYieldsNothingWhenTheFileIsNotAJSONArray() {
        let result = Journal.decodeRecovering(Data("broken".utf8))
        XCTAssertTrue(result.sessions.isEmpty)
        XCTAssertEqual(result.rejected, 0)
    }

    func testDecodesJournalWrittenBeforeTheNewFields() throws {
        // Exactly the JSON shape a 1.3.0 build wrote: six keys, three missing.
        let legacy = """
        [{"id":"11111111-1111-1111-1111-111111111111","date":"2024-01-01T00:00:00Z","duration":42,"feeling":4,"notes":"Avant"}]
        """
        let sessions = try Journal.decode(Data(legacy.utf8))
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].orgasm, 3)
        XCTAssertEqual(sessions[0].mental, 3)
        XCTAssertEqual(sessions[0].ejaculation, .aucune)
        XCTAssertEqual(sessions[0].notes, "Avant")
    }

    func testRejectsOutOfRangeNewScales() {
        XCTAssertThrowsError(try Journal.encode([Session(duration: 10, orgasm: 0)]))
        XCTAssertThrowsError(try Journal.encode([Session(duration: 10, orgasm: 6)]))
        XCTAssertThrowsError(try Journal.encode([Session(duration: 10, mental: 0)]))
        XCTAssertThrowsError(try Journal.encode([Session(duration: 10, mental: 6)]))
        XCTAssertNoThrow(try Journal.encode([Session(duration: 10, orgasm: 1, mental: 5)]))
    }

    func testRoundTripsTheNewFields() throws {
        // Whole-second date: the ISO8601 encoder drops sub-second precision, so a
        // `Date()` default would make this compare unequal for a reason unrelated
        // to the new fields.
        let session = Session(date: Date(timeIntervalSince1970: 100), duration: 42, feeling: 4,
                              orgasm: 5, mental: 2, ejaculation: .jet, notes: "Net")
        let decoded = try Journal.decode(Journal.encode([session]))
        XCTAssertEqual(decoded, [session])
    }

    func testRecoveryKeepsLegacyRecordsAlongsideACorruptOne() throws {
        let legacy = """
        [{"id":"11111111-1111-1111-1111-111111111111","date":"2024-01-01T00:00:00Z","duration":42,"feeling":4,"notes":"Avant"},
         {"id":"22222222-2222-2222-2222-222222222222","date":"2024-01-02T00:00:00Z","duration":99999,"feeling":3,"notes":"Hors limites"}]
        """
        XCTAssertThrowsError(try Journal.decode(Data(legacy.utf8)))
        let recovered = Journal.decodeRecovering(Data(legacy.utf8))
        XCTAssertEqual(recovered.sessions.count, 1)
        XCTAssertEqual(recovered.sessions[0].orgasm, 3)
        XCTAssertEqual(recovered.sessions[0].ejaculation, .aucune)
        XCTAssertEqual(recovered.rejected, 1)
    }

    func testCSVExposesEveryMeasure() {
        let csv = Journal.csv([Session(duration: 12, feeling: 4, orgasm: 5, mental: 2, ejaculation: .baveuse, notes: "Note")])
        XCTAssertTrue(csv.hasPrefix("date_utc,duree_secondes,ressenti_sur_5,orgasme_sur_5,ressenti_mental_sur_5,type_ejaculation,notes\r\n"))
        let row = csv.components(separatedBy: "\r\n")[1]
        XCTAssertTrue(row.hasSuffix(",4,5,2,baveuse,\"Note\""))
    }

    func testCSVQuotesNewlinesAndNeutralizesFormulas() {
        let csv = Journal.csv([Session(duration: 12, notes: " =SUM(1,2)\n\"note\"")])
        XCTAssertTrue(csv.contains("\"' =SUM(1,2)\n\"\"note\"\"\""))
        XCTAssertTrue(csv.hasPrefix("date_utc,duree_secondes,ressenti_sur_5,orgasme_sur_5,ressenti_mental_sur_5,type_ejaculation,notes\r\n"))
    }

    func testTimerResumesAfterSerializationAndExcludesPausedTime() throws {
        let zero = Date(timeIntervalSince1970: 0)
        var timer = TimerDraft()
        timer.start(at: zero)
        timer.start(at: zero.addingTimeInterval(5))
        timer.pause(at: zero.addingTimeInterval(12))
        XCTAssertEqual(timer.elapsed(at: zero.addingTimeInterval(30)), 12)
        timer.start(at: zero.addingTimeInterval(30))
        let restored = try JSONDecoder().decode(TimerDraft.self, from: JSONEncoder().encode(timer))
        XCTAssertEqual(restored.elapsed(at: zero.addingTimeInterval(37)), 19)
        XCTAssertEqual(restored.elapsed(at: zero), 12)
    }

    func testDurationFormattingAndLimit() {
        XCTAssertEqual(durationLabel(65), "01:05")
        XCTAssertEqual(durationLabel(3661), "1:01:01")
        var timer = TimerDraft()
        timer.start(at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(timer.elapsed(at: Date(timeIntervalSince1970: 100_000)), 86_400)
    }
}
