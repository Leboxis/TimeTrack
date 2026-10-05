import Foundation

/// Porn-free day counts derived from the journal. See
/// `abstinence(sessions:now:calendar:)` for the rules; every field here follows from one.
public struct Abstinence: Equatable {
    /// Current streak, in days. Zero once today carries a porn session.
    public let days: Int
    /// Longest streak anywhere in the covered history.
    public let longest: Int
    /// Number of days carrying at least one porn session.
    public let relapses: Int
    /// Clean days over covered days, 0...1.
    public let cleanRate: Double
    /// Start of the most recent dirty day.
    public let lastRelapse: Date?
}

/// Counts porn-free days from the sessions.
///
/// The window starts at the earliest session and ends today: a journal with three days of
/// history says "3 jours" and never "1 700 jours", because days before the journal existed
/// carry no observation at all. A day with no session counts as clean — the user does not
/// have to declare every sober day, which is what would otherwise keep the counter stuck
/// at zero.
///
/// Deliberately free of SwiftUI: the day-boundary rules are the part worth testing, and
/// they live in the package where `swift test` can reach them.
public func abstinence(sessions: [Session], now: Date = Date(),
                       calendar: Calendar = .current) -> Abstinence {
    guard let first = sessions.map(\.date).min() else {
        return Abstinence(days: 0, longest: 0, relapses: 0, cleanRate: 0, lastRelapse: nil)
    }
    let today = calendar.startOfDay(for: now)
    let start = calendar.startOfDay(for: first)
    guard today >= start else {
        // Every session is dated in the future, so there is no history to count yet.
        return Abstinence(days: 0, longest: 0, relapses: 0, cleanRate: 0, lastRelapse: nil)
    }

    // The day is the unit, not the session: three porn sessions on one day are one
    // relapse. A session dated in the future sits outside the window and must not break a
    // streak that has not happened yet, which is what a clock skewed ahead would do.
    var dirtyDays: Set<Date> = []
    for session in sessions where session.hasPorn {
        let day = calendar.startOfDay(for: session.date)
        guard day <= today else { continue }
        dirtyDays.insert(day)
    }

    let covered = (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1
    let relapses = dirtyDays.count
    let cleanDays = max(0, covered - relapses)
    let cleanRate = covered > 0 ? Double(cleanDays) / Double(covered) : 0

    // Longest run of clean days anywhere in the window. Walking it day by day is not worth
    // optimising: a year of history is 366 iterations.
    var longest = 0
    var run = 0
    var cursor = start
    while cursor <= today {
        if dirtyDays.contains(cursor) {
            longest = max(longest, run)
            run = 0
        } else {
            run += 1
            longest = max(longest, run)
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
        cursor = next
    }

    // Today dirty means the streak is already broken. Otherwise it runs back to the most
    // recent dirty day, stopping at the start of the journal.
    var days = 0
    if !dirtyDays.contains(today) {
        var cursor = today
        while !dirtyDays.contains(cursor), cursor >= start {
            days += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
    }

    return Abstinence(days: days, longest: longest, relapses: relapses,
                      cleanRate: cleanRate, lastRelapse: dirtyDays.max())
}