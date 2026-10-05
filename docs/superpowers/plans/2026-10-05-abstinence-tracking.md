# Porn-Free Day Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user see how many porn-free days they have, derived from the sessions already in the journal, without adding a screen or a data file.

**Architecture:** One `Bool` field on `Session` (`hasPorn`, defaults to `false` so every existing journal still decodes). One pure function `abstinence(sessions:now:calendar:)` in `WellbeingCore`, which is the whole contract and is unit-tested. Three SwiftUI touch points: a toggle in `SessionEditor`, a card in `TrendsView`, a chip in `JournalView`. No new tab, no new navigation destination, no network, no dependency.

**Tech Stack:** Swift 5.9 / SwiftPM (`WellbeingCore` package + XcodeGen iOS app), SwiftUI, Charts, XCTest. Deployment target iOS 17, macOS 13 (package tests run on macOS).

**Spec:** `docs/superpowers/specs/2026-10-05-abstinence-tracking-design.md` — the plan argues from the spec, so the spec travels with it; executors read both.

## Global Constraints

- **No real app blocking.** iOS only grants the "Family Controls" entitlement to App Store builds; this app ships as an unencrypted IPA (LiveContainer, SideStore). No code here may close another app or Safari. Do not add a Network Extension or a `FamilyControls` import.
- **No new data file, no new tab, no new navigation destination, no new dependency.** The journal stays one `journal.json`.
- **`hasPorn` must default to `false` on decode.** Use `decodeIfPresent(Bool.self) ?? false`, matching how `orgasm`, `mental` and `ejaculation` already backfill in `Session.init(from:)`.
- **All copy is French.** No English user-facing string, including accessibility labels.
- **Core code stays free of SwiftUI.** `Abstinence.swift` must not import SwiftUI, exactly like `RatingBand` in `Session.swift`. The colour and layout belong to the app layer.
- **Tests must pin the calendar.** Build test calendars with `gregorian` and `UTC`, otherwise a machine crossing a DST boundary fails them.
- **`swift test` is the only local gate.** There is no iOS simulator here; `xcodebuild` for iOS runs in CI (`Build iOS IPA`) on push to `main`.

## Review Focus

Five inputs the spec implies but does not spell out, most likely to bite first. Each gets a test in the task that owns the code.

1. **A session backdated into an earlier month.** Relapse counting must group by calendar day, not by ordering or by 24-hour windows — a session at 23:50 and one at 00:10 are two days, and the record must not merge them.
2. **The device clock moving backwards.** A session dated in the future is legal (`SessionEditor`'s `DatePicker` allows `...Date()`, but a synced clock can land ahead). Counting must never return a negative `days` or a crash; a future-dated relapse must not be treated as today.
3. **An empty but existing journal versus an empty period.** `abstinence` on `sessions: []` must return zeros, not a crash on `min()` of an empty sequence, and `TrendsView` must show its empty message rather than "0 jours".
4. **A streak longer than the session count.** Many clean days and one relapse means `days` can far exceed `sessions.count`. Any code that infers day count from session count breaks here.
5. **A hand-edited journal with a missing or wrongly-typed `hasPorn`.** `"has_porn": "oui"` must be treated as absent (`decodeIfPresent` fails on a type mismatch) and fall back to `false`, not throw and cost the user the whole file through `JournalError.invalidData`.

---

## File Structure

- `Sources/WellbeingCore/Session.swift` — modified: `hasPorn` field, decoder backfill, CSV column.
- `Sources/WellbeingCore/Abstinence.swift` — **created**. `Abstinence` struct + `abstinence(sessions:now:calendar:)` free function. Pure, no SwiftUI.
- `Tests/WellbeingCoreTests/AbstinenceTests.swift` — **created**. All counting rules.
- `Tests/WellbeingCoreTests/JournalTests.swift` — modified: decode-backfill test and CSV-column test for `hasPorn`.
- `App/AbstinenceCard.swift` — **created**. The TrendsView card: two metrics, a 30-day band, a context line.
- `App/SessionEditor.swift` — modified: the toggle.
- `App/TrendsView.swift` — modified: insert the card above the period `Picker`.
- `App/JournalView.swift` — modified: chip + accessibility summary.
- `README.md` — modified: one feature bullet.

The card is its own file because `TrendsView.swift` is already 263 lines and holds two other private chart types; adding a third inline view would make it the place where everything lives.

---

### Task 1: `hasPorn` on Session

**Files:**
- Modify: `Sources/WellbeingCore/Session.swift:15-58` (struct, `init`, `init(from:)`), `Sources/WellbeingCore/Session.swift:115-124` (`csv`)
- Test: `Tests/WellbeingCoreTests/JournalTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `Session.hasPorn: Bool` (var, default `false`), readable and writable. `Session.init(id:date:duration:feeling:orgasm:mental:ejaculation:hasPorn:notes:)` gains `hasPorn: Bool = false` between `ejaculation` and `notes`, so every existing call site compiles unchanged.

- [ ] **Step 1: Write the failing test**

Append to `Tests/WellbeingCoreTests/JournalTests.swift`:

```swift
func testASessionWithoutThePornKeyDecodesAsClean() throws {
    let json = """
    [{"id":"6C1E0B0A-0000-4000-8000-000000000001","date":"2026-09-01T10:00:00Z",
      "duration":60,"feeling":3,"notes":"note"}]
    """
    let sessions = try Journal.decode(Data(json.utf8))
    XCTAssertEqual(sessions.count, 1)
    XCTAssertFalse(sessions[0].hasPorn)
}

func testASessionWithThePornKeyDecodes() throws {
    let json = """
    [{"id":"6C1E0B0A-0000-4000-8000-000000000001","date":"2026-09-01T10:00:00Z",
      "duration":60,"feeling":3,"notes":"","has_porn":true}]
    """
    let sessions = try Journal.decode(Data(json.utf8))
    XCTAssertTrue(sessions[0].hasPorn)
}

/// A hand-edited file can hold the wrong type. `decodeIfPresent` must swallow it as
/// absent rather than throw, or one bad value costs the whole journal.
func testAMistypedPornKeyIsTreatedAsClean() throws {
    let json = """
    [{"id":"6C1E0B0A-0000-4000-8000-000000000001","date":"2026-09-01T10:00:00Z",
      "duration":60,"feeling":3,"notes":"","has_porn":"oui"}]
    """
    let sessions = try Journal.decode(Data(json.utf8))
    XCTAssertFalse(sessions[0].hasPorn)
}

func testTheCsvCarriesThePornColumn() {
    let csv = Journal.csv([Session(id: UUID(uuidString: "6C1E0B0A-0000-4000-8000-000000000001")!,
                                    date: Date(timeIntervalSince1970: 0),
                                    duration: 60, hasPorn: true)])
    let lines = csv.split(separator: "\r\n")
    XCTAssertTrue(lines[0].hasPrefix("date_utc,duree_secondes,ressenti_sur_5,orgasme_sur_5,ressenti_mental_sur_5,type_ejaculation,"))
    XCTAssertTrue(lines[1].contains(",1,"), "la ligne porte la valeur, attendu : \(lines[1])")
}

func testTheCsvColumnIsZeroForACleanSession() {
    let csv = Journal.csv([Session(duration: 60)])
    XCTAssertTrue(csv.split(separator: "\r\n")[1].contains(",0,"))
}

func testThePornFlagSurvivesAnEncodeDecodeRoundTrip() throws {
    let original = [Session(duration: 60, hasPorn: true), Session(duration: 30, hasPorn: false)]
    let decoded = try Journal.decode(Journal.encode(original))
    XCTAssertEqual(decoded.map(\.hasPorn), [true, false])
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter JournalTests`
Expected: compile error, `value of type 'Session' has no member 'hasPorn'` and `extra argument 'hasPorn' in call`.

- [ ] **Step 3: Add the field and the decoder backfill**

In `Sources/WellbeingCore/Session.swift`, add to the struct after `ejaculation`:

```swift
    /// True when the session involved pornography. Missing on journals written before
    /// this field existed, so it decodes as false and those days count as clean.
    public var hasPorn: Bool
```

Extend `init` with `hasPorn: Bool = false` between `ejaculation` and `notes`, and assign `self.hasPorn = hasPorn` in the body.

In `init(from decoder: Decoder)`, add after the `ejaculation` line:

```swift
        hasPorn = try container.decodeIfPresent(Bool.self, forKey: .hasPorn) ?? false
```

The synthesized `CodingKeys` picks up `hasPorn` as `"hasPorn"`, matching the camelCase keys already used by `orgasm` and `mental`.

- [ ] **Step 4: Add the CSV column**

In `Journal.csv`, append `session.hasPorn ? "1" : "0"` to the row array after `session.ejaculation.rawValue`, and extend the header to end with `avec_porno` after `type_ejaculation`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter JournalTests`
Expected: PASS, all tests in the filter green.

- [ ] **Step 6: Commit**

```bash
git add Sources/WellbeingCore/Session.swift Tests/WellbeingCoreTests/JournalTests.swift
git commit -m "feat: record whether a session involved pornography"
```

---

### Task 2: The counting function

**Files:**
- Create: `Sources/WellbeingCore/Abstinence.swift`
- Test: `Tests/WellbeingCoreTests/AbstinenceTests.swift`

**Interfaces:**
- Consumes: `Session.hasPorn` and `Session.date` from Task 1.
- Produces:
  ```swift
  public struct Abstinence: Equatable {
      public let days: Int
      public let longest: Int
      public let relapses: Int
      public let cleanRate: Double
      public let lastRelapse: Date?
  }

  public func abstinence(sessions: [Session], now: Date = Date(),
                         calendar: Calendar = .current) -> Abstinence
  ```
  Task 3 and Task 4 consume `abstinence(sessions:)` and nothing else.

The rules this encodes, from the spec:

1. Bounded by data — the counted window starts at the earliest session, never earlier.
2. A day with any porn session is dirty, whatever else happened that day.
3. A day with no session at all is clean.
4. `days` is 0 if today is already dirty.
5. `relapses` counts dirty days, not sessions.
6. `cleanRate` is over covered days only.

- [ ] **Step 1: Write the failing test file**

Create `Tests/WellbeingCoreTests/AbstinenceTests.swift`:

```swift
import XCTest
@testable import WellbeingCore

final class AbstinenceTests: XCTestCase {
    /// Pinned so a DST boundary or a timezone change cannot move a day under the
    /// assertions.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let epoch = Date(timeIntervalSince1970: 1_788_739_200) // 2026-09-07T00:00:00Z

    private func day(_ offset: Int, hasPorn: Bool = false) -> Session {
        let date = calendar.date(byAdding: .day, value: offset, to: epoch)!
        return Session(id: UUID(), date: date, duration: 60, hasPorn: hasPorn)
    }

    func testAnEmptyJournalCountsNothing() {
        let result = abstinence(sessions: [], now: epoch, calendar: calendar)
        XCTAssertEqual(result, Abstinence(days: 0, longest: 0, relapses: 0,
                                          cleanRate: 0, lastRelapse: nil))
    }

    /// Rule 4: today dirty means zero, not "still counting until midnight".
    func testARelapseTodayResetsTheCurrentStreak() {
        let result = abstinence(sessions: [day(0, hasPorn: true)], now: epoch, calendar: calendar)
        XCTAssertEqual(result.days, 0)
    }

    func testACleanFirstDayCountsAsOne() {
        XCTAssertEqual(abstinence(sessions: [day(0)], now: epoch, calendar: calendar).days, 1)
    }

    /// Rule 1: the window starts at the first session, so five days of silence before
    /// any record cannot be credited.
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

    /// Rule 5, and Review Focus 1: the day is the unit, not the session.
    func testTwoRelapsesOnTheSameDayCountOnce() {
        let result = abstinence(sessions: [day(0, hasPorn: true), day(0, hasPorn: true)],
                                now: epoch, calendar: calendar)
        XCTAssertEqual(result.relapses, 1)
    }

    /// Rule 2: the day is dirty if any session on it is, even beside a clean one.
    func testACleanSessionDoesNotRescueADirtyDay() {
        let result = abstinence(sessions: [day(0, hasPorn: true), day(0, hasPorn: false)],
                                now: epoch, calendar: calendar)
        XCTAssertEqual(result.relapses, 1)
        XCTAssertEqual(result.days, 0)
    }

    /// Rule 6: 10 covered days, 1 dirty.
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

    func testALongStreakIsNotCappedByTheSessionCount() {
        // Review Focus 4: 40 clean days from a single record.
        let result = abstinence(sessions: [day(-40, hasPorn: true)], now: epoch, calendar: calendar)
        XCTAssertEqual(result.days, 40)
    }

    /// Review Focus 2: a clock skewed ahead puts every session in the future. Nothing can
    /// be counted yet, and the answer is zeros — never a negative streak, never a crash.
    func testAFutureDatedSessionCountsNothing() {
        let result = abstinence(sessions: [day(2, hasPorn: true)], now: epoch, calendar: calendar)
        XCTAssertEqual(result, Abstinence(days: 0, longest: 0, relapses: 0,
                                          cleanRate: 0, lastRelapse: nil))
    }

    /// A future-dated relapse must not also break today's streak when the window does
    /// start in the past.
    func testAFutureDatedRelapseDoesNotBreakTodaysStreak() {
        let result = abstinence(sessions: [day(-5), day(2, hasPorn: true)],
                                now: epoch, calendar: calendar)
        XCTAssertEqual(result.relapses, 0, "le futur est hors de la fenêtre")
        XCTAssertEqual(result.days, 6, "5 jours propres + aujourd'hui")
    }

    func testSessionsAreGroupedByCalendarDayNotBy24HourWindow() {
        // 23:50 yesterday and 00:10 today are 10 minutes apart and two distinct days.
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
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AbstinenceTests`
Expected: compile error, `cannot find 'abstinence' in scope`.

- [ ] **Step 3: Implement `Abstinence.swift`**

Create `Sources/WellbeingCore/Abstinence.swift`:

```swift
import Foundation

/// Porn-free day counts derived from the journal. See `abstinence(sessions:now:calendar:)`
/// for the rules; every field here is a consequence of one of them.
public struct Abstinence: Equatable {
    /// Current streak. Zero once today carries a porn session.
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
/// history says "3 jours", never "1 700 jours", because days before the journal existed
/// carry no observation at all. A day with no session counts as clean — the user does not
/// have to declare every sober day, which is what would keep the counter stuck at zero.
public func abstinence(sessions: [Session], now: Date = Date(),
                       calendar: Calendar = .current) -> Abstinence {
    guard let first = sessions.map(\.date).min() else {
        return Abstinence(days: 0, longest: 0, relapses: 0, cleanRate: 0, lastRelapse: nil)
    }
    let today = calendar.startOfDay(for: now)
    let start = calendar.startOfDay(for: first)
    guard today >= start else {
        return Abstinence(days: 0, longest: 0, relapses: 0, cleanRate: 0, lastRelapse: nil)
    }

    // A day is dirty if any session on it is. Days are the unit, so three porn sessions
    // on one day are one relapse.
    var dirtyDays: Set<Date> = []
    for session in sessions where session.hasPorn {
        let day = calendar.startOfDay(for: session.date)
        // A session dated in the future is outside the counted window; including it would
        // let a skewed clock break a streak that has not happened yet.
        guard day <= today else { continue }
        dirtyDays.insert(day)
    }

    let covered = (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1
    let relapses = dirtyDays.count
    let cleanDays = max(0, covered - relapses)
    let cleanRate = covered > 0 ? Double(cleanDays) / Double(covered) : 0

    // Longest run of clean days anywhere in the window.
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

    // Today dirty means the streak is already broken; otherwise it runs up to today.
    var days = 0
    if !dirtyDays.contains(today) {
        var cursor = today
        while !dirtyDays.contains(cursor) {
            days += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
            if cursor < start { break }
        }
    }

    return Abstinence(days: days, longest: longest, relapses: relapses,
                      cleanRate: cleanRate, lastRelapse: dirtyDays.max())
}
```

The day-by-day loop walks the window once; at ~30 iterations for a year of history this is
not worth the extra code of a sweep-line, and it keeps the rules readable.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AbstinenceTests`
Expected: PASS, 13 tests green.

- [ ] **Step 5: Run the whole suite to confirm nothing regressed**

Run: `swift test`
Expected: PASS, all targets green.

- [ ] **Step 6: Commit**

```bash
git add Sources/WellbeingCore/Abstinence.swift Tests/WellbeingCoreTests/AbstinenceTests.swift
git commit -m "feat: count porn-free days from the journal"
```

---

### Task 3: The toggle in the session editor

**Files:**
- Modify: `App/SessionEditor.swift:37-48` (the "Séance" `Section`)

**Interfaces:**
- Consumes: `Session.hasPorn` (Task 1).
- Produces: nothing new; the editor round-trips the field through its existing `onSave`.

- [ ] **Step 1: Add the toggle**

In `App/SessionEditor.swift`, inside the `Section("Séance")`, after the duration `HStack`
and its validation `if let`/`else` pair, add:

```swift
                    Toggle("Séance avec porno", isOn: $session.hasPorn)
```

- [ ] **Step 2: Verify the field reaches the store**

Run: `git diff App/SessionEditor.swift`
Expected: only the `Toggle` line is added, and it binds to `$session.hasPorn`.

The sheet already passes the whole `session` to `onSave(session)`, and `JournalStore.save`
writes it back through `Journal.encode`, so the value persists with no further change.

- [ ] **Step 3: Commit**

```bash
git add App/SessionEditor.swift
git commit -m "feat: mark a session as porn in the editor"
```

---

### Task 4: The abstinence card in Tendances

**Files:**
- Create: `App/AbstinenceCard.swift`
- Modify: `App/TrendsView.swift:27-33` (insert above the `Picker`)

**Interfaces:**
- Consumes: `abstinence(sessions:now:calendar:)` and `Abstinence` (Task 2), and the existing `metric(_:_:symbol:)` helper on `TrendsView`.
- Produces: `AbstinenceCard(sessions:)`, a view taking `[Session]` and rendering nothing else.

The card lives above the period `Picker`, so it is visible while the journal is still
empty, and it ignores the `Picker`: a streak is read in absolute terms, not through a
sliding window.

- [ ] **Step 1: Create the card**

Create `App/AbstinenceCard.swift`:

```swift
import SwiftUI
import WellbeingCore

/// Porn-free day counts. Deliberately independent of the period picker above it: a streak
/// is an absolute figure, and filtering it to "the last 7 days" would hide the one number
/// the card exists to show.
struct AbstinenceCard: View {
    let sessions: [Session]

    private var result: Abstinence { abstinence(sessions: sessions) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Jours sans porno").font(.headline)

            if sessions.isEmpty {
                Text("Les jours sans porno apparaîtront après votre première séance.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    metric("Série en cours", "\(result.days) j", .clock)
                    metric("Record", "\(result.longest) j", .trophy)
                }
                band
                Text("\(result.relapses) rechute(s) · \(Int((result.cleanRate * 100).rounded())) % de jours propres, selon les séances cochées.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityLabel("\(result.relapses) rechutes, \(Int((result.cleanRate * 100).rounded())) pour cent de jours propres selon les séances cochées.")
            }
        }
        .padding(16).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    /// One square per day over the last 30 days, so a gap in the journal is visible as a
    /// gap and not mistaken for a clean streak.
    private var band: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dirty = Set(sessions.filter(\.hasPorn).map { calendar.startOfDay(for: $0.date) })
        return HStack(spacing: 3) {
            ForEach(0..<30, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset - 29, to: today)!
                let clean = !dirty.contains(day)
                RoundedRectangle(cornerRadius: 2)
                    .fill(clean ? Color.teal.opacity(0.55) : Color.orange.opacity(0.75))
                    .frame(height: 18)
                    .accessibilityLabel(day.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue(clean ? "sans porno" : "avec porno")
            }
        }
    }

    /// Same shape as the existing metrics in `TrendsView`: caption, monospaced value,
    /// 16pt padding on the same tint.
    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }
}
```

- [ ] **Step 2: Mount the card in TrendsView**

`TrendsView.swift` already imports `WellbeingCore`, so no import changes.
Insert as the first element of the `VStack` in `body`, before the `Picker`:

```swift
                    if !store.loadFailed {
                        AbstinenceCard(sessions: store.sessions)
                    }
```

The `loadFailed` guard keeps the existing rule of the file: no figures are shown over an
unreadable journal.

- [ ] **Step 3: Verify the placement**

Run: `git diff App/TrendsView.swift`
Expected: exactly one insertion, three lines, above the `Picker("Période")`.

- [ ] **Step 4: Commit**

```bash
git add App/AbstinenceCard.swift App/TrendsView.swift
git commit -m "feat: show porn-free days in the trends"
```

---

### Task 5: The journal chip and the README

**Files:**
- Modify: `App/JournalView.swift:64` (chip row), `App/JournalView.swift:136-147` (`accessibilitySummary`)
- Modify: `README.md:5-15`

**Interfaces:**
- Consumes: `Session.hasPorn` (Task 1).

- [ ] **Step 1: Add the chip**

In `App/JournalView.swift`, inside the `HStack(spacing: 6)` that already holds the four
chips, add after the `ejaculation` chip:

```swift
                                if session.hasPorn {
                                    chip("Porno", RatingPalette.ejaculation)
                                }
```

Reusing `RatingPalette.ejaculation` keeps the palette to the colours already defined in
`RatingPalette.swift` instead of introducing a new hue.

- [ ] **Step 2: Extend the accessibility summary**

In `accessibilitySummary(_:)`, add after the `ejaculation` line:

```swift
            session.hasPorn ? "avec porno" : "sans porno",
```

VoiceOver then carries the fact on its own; the chip's colour never has to.

- [ ] **Step 3: Add the README bullet**

In `README.md`, add to the `## Fonctionnalités` list, after the export bullet:

```markdown
- Suivi des jours sans porno : série, record et taux de jours propres, calculés depuis les séances marquées « avec porno » dans l'éditeur.
```

- [ ] **Step 4: Commit**

```bash
git add App/JournalView.swift README.md
git commit -m "feat: flag porn sessions in the journal"
```

---

### Task 6: Full verification and push

**Files:** none modified. This task gates the branch.

- [ ] **Step 1: Run the whole test suite**

Run: `swift test`
Expected: PASS, every target green, `KDriveTests` absent (removed earlier).

- [ ] **Step 2: Confirm no stray references**

Run: `git grep -n "hasPorn" -- App Sources`
Expected: hits only in `Session.swift`, `SessionEditor.swift`, `AbstinenceCard.swift`,
`JournalView.swift`, `AbstinenceTests.swift`, `JournalTests.swift`. Nothing in
`WellbeingApp.swift` — no new tab was added, and that is the check for it.

- [ ] **Step 3: Push and read the CI result**

Run: `git push origin main`, then `gh run watch $(gh run list --workflow "Build iOS IPA" --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status`
Expected: exit code 0. The CI job runs `swift test`, then `xcodebuild` for
iphoneos, then packages and validates the IPA — this is the only real iOS compile
available, and a failure here means the SwiftUI wiring is wrong in a way the package
tests cannot see.

- [ ] **Step 4: Read the release notes for scope creep**

Run: `git log --oneline 4bbb07a..HEAD -- App Sources Tests`
Expected: only the six tasks above plus the earlier kDrive removal and this feature. No
unrelated edits.