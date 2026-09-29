import XCTest
@testable import WellbeingCore

final class JournalTests: XCTestCase {
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

    func testCSVQuotesNewlinesAndNeutralizesFormulas() {
        let csv = Journal.csv([Session(duration: 12, notes: " =SUM(1,2)\n\"note\"")])
        XCTAssertTrue(csv.contains("\"' =SUM(1,2)\n\"\"note\"\"\""))
        XCTAssertTrue(csv.hasPrefix("date_utc,duree_secondes,ressenti_sur_5,notes\r\n"))
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
