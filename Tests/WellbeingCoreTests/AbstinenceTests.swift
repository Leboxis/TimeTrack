import XCTest
@testable import WellbeingCore

final class AbstinenceTests: XCTestCase {
    /// Pinned so a DST boundary or a timezone change cannot move a day out from under an
    /// assertion.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-09-07T00:00:00Z.
    private let epoch = Date(timeIntervalSince1970: 1_788_739_200)

    /// A session `offset` days from the epoch.
    private func day(_ offset: Int, hasPorn: Bool = false) -> Session {
        Session(id: UUID(), date: calendar.date(byAdding: .day, value: offset, to: epoch)!,
                duration: 60, hasPorn: hasPorn)
    }

    func testAnEmptyJournalCountsNothing() {
        let result = abstinence(sessions: [], now: epoch, calendar: calendar)
        XCTAssertEqual(result, Abstinence(days: 0, longest: 0, relapses: 0,
                                          cleanRate: 0, lastRelapse: nil))
    }

    /// Today already dirty means the streak is broken, rather than kept alive until
    /// midnight.
    func testARelapseTodayResetsTheCurrentStreak() {
        let result = abstinence(sessions: [day(0, hasPorn: true)], now: epoch, calendar: calendar)
        XCTAssertEqual(result.days, 0)
    }

    func testACleanFirstDayCountsAsOne() {
        XCTAssertEqual(abstinence(sessions: [day(0)], now: epoch, calendar: calendar).days, 1)
    }

    /// The window starts at the first session, so silence before any record cannot be
    /// credited as clean days.
    func testDaysBeforeTheFirstSessionAreNotCounted() {
        let result = abstinence(sessions: [day(0, hasPorn: true)], now: epoch, calendar: calendar)
        XCTAssertEqual(result.longest, 0)
        XCTAssertEqual(result.cleanRate, 0, accuracy: 0.0001)
    }

    func testARelapseThreeDaysAgoLeavesAThreeDayStreak() {
        let result = abstinence(sessions: [day(-3, hasPorn: true)], now: epoch, calendar: calendar)
        XCTAssertEqual(result.days, 3)
    }

    func testTheLongestStreakSurvivesALaterRelapse() {
        let result = abstinence(sessions: [day(-6, hasPorn: true), day(0, hasPorn: true)],
                                now: epoch, calendar: calendar)
        XCTAssertEqual(result.days, 0)
        XCTAssertEqual(result.longest, 6)
    }

    /// Three porn sessions on one day are one failure, not three.
    func testTwoRelapsesOnTheSameDayCountOnce() {
        let result = abstinence(sessions: [day(0, hasPorn: true), day(0, hasPorn: true)],
                                now: epoch, calendar: calendar)
        XCTAssertEqual(result.relapses, 1)
    }

    /// A clean session beside a dirty one does not rescue the day.
    func testACleanSessionDoesNotRescueADirtyDay() {
        let result = abstinence(sessions: [day(0, hasPorn: true), day(0, hasPorn: false)],
                                now: epoch, calendar: calendar)
        XCTAssertEqual(result.relapses, 1)
        XCTAssertEqual(result.days, 0)
    }

    /// Ten covered days, one dirty: the rate is over covered days, never over a calendar
    /// span that includes the days before the journal existed.
    func testTheCleanRateIsOverCoveredDaysOnly() {
        let sessions = (0...9).map { day(-$0) } + [day(0, hasPorn: true)]
        let result = abstinence(sessions: sessions, now: epoch, calendar: calendar)
        XCTAssertEqual(result.relapses, 1)
        XCTAssertEqual(result.cleanRate, 0.9, accuracy: 0.0001)
    }

    func testTheLastRelapseDateIsReported() {
        let expected = calendar.date(byAdding: .day, value: -2, to: epoch)!
        let result = abstinence(sessions: [day(-2, hasPorn: true)], now: epoch, calendar: calendar)
        XCTAssertEqual(result.lastRelapse, expected)
    }

    /// Forty clean days out of a single record: a streak is not derivable from the number
    /// of sessions.
    func testALongStreakIsNotCappedByTheSessionCount() {
        let result = abstinence(sessions: [day(-40, hasPorn: true)], now: epoch, calendar: calendar)
        XCTAssertEqual(result.days, 40)
    }

    /// A clock skewed ahead puts every session in the future. There is nothing to count
    /// yet, and the answer is zeros rather than a crash or a negative streak.
    func testAFutureDatedSessionCountsNothing() {
        let result = abstinence(sessions: [day(2, hasPorn: true)], now: epoch, calendar: calendar)
        XCTAssertEqual(result, Abstinence(days: 0, longest: 0, relapses: 0,
                                          cleanRate: 0, lastRelapse: nil))
    }

    /// A future-dated relapse must not break a streak that has genuinely happened.
    func testAFutureDatedRelapseDoesNotBreakTodaysStreak() {
        let result = abstinence(sessions: [day(-5), day(2, hasPorn: true)],
                                now: epoch, calendar: calendar)
        XCTAssertEqual(result.relapses, 0, "le futur est hors de la fenêtre")
        XCTAssertEqual(result.days, 6, "5 jours propres et aujourd'hui")
    }

    /// Two relapses ten minutes apart across midnight are two distinct days.
    func testSessionsAreGroupedByCalendarDayNotBy24HourWindow() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: epoch)!
        let late = calendar.date(bySetting: .hour, value: 23, of: yesterday)!
            .addingTimeInterval(50 * 60)
        let early = calendar.date(bySetting: .hour, value: 0, of: epoch)!
            .addingTimeInterval(10 * 60)
        XCTAssertLessThan(late.timeIntervalSince(early), 60 * 60)

        let sessions = [
            Session(id: UUID(), date: late, duration: 60, hasPorn: true),
            Session(id: UUID(), date: early, duration: 60, hasPorn: true)
        ]
        let result = abstinence(sessions: sessions, now: epoch, calendar: calendar)
        XCTAssertEqual(result.relapses, 2)
    }

    /// The window is bounded by data and stops at today: days with no session at all still
    /// count as clean, so three clean days before a relapse five days back is a ten-day
    /// streak, not a four-day one.
    func testTheStreakNeverRunsPastToday() {
        let result = abstinence(sessions: [day(-3), day(-10, hasPorn: true)],
                                now: epoch, calendar: calendar)
        XCTAssertEqual(result.days, 10, "de -9 à aujourd'hui, aucun jour sale")
        XCTAssertEqual(result.longest, 10)
        XCTAssertEqual(result.relapses, 1)
    }

    /// A day with several clean sessions and no porn anywhere is entirely clean, which is
    /// the case the "a day is dirty if any session is" rule must not over-reach on.
    func testSeveralCleanSessionsOnOneDayKeepItClean() {
        let result = abstinence(sessions: [day(0), day(0), day(-1)],
                                now: epoch, calendar: calendar)
        XCTAssertEqual(result.relapses, 0)
        XCTAssertEqual(result.days, 2)
        XCTAssertEqual(result.cleanRate, 1, accuracy: 0.0001)
    }
}