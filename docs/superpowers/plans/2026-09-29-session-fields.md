# Session orgasm, mental and ejaculation fields Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three per-session measures — `orgasm` (1-5), `mental` (1-5) and `ejaculation` (three states) — without ever making an existing `journal.json` unreadable.

**Architecture:** The change is additive at the schema level. `Session` gains a hand-written `init(from:)` that uses `decodeIfPresent` for the three new fields, so files written by older builds keep decoding with neutral defaults. `encode(to:)` stays synthesized and writes all six fields. No migration, no file rewrite, no schema version. UI work is three small consumers: the editor, the journal row, the trends charts.

**Tech Stack:** Swift 5, SwiftUI, Swift Charts, Foundation, XcodeGen (`project.yml`), XCTest. iOS 17 deployment target, no third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-29-session-fields-design.md`

## Global Constraints

- **Backward compatibility is a blocking requirement.** Any code that makes an old `journal.json` fail to decode is a defect, not an edge case.
- Enum raw values are French and are persisted verbatim: `aucune`, `baveuse`, `jet`. They are the CSV cell content.
- `Ejaculation` displays as `Aucune`, `Baveuse`, `Jet`.
- Scale labels: `Ressenti` uses the existing `1 · Difficile` … `5 · Très bien`. `Orgasme` uses `1 · Difficile` … `5 · Excellent`. `Mental` uses `1 · Anxieux` … `5 · Serein`.
- CSV header is exactly `date_utc,duree_secondes,ressenti_sur_5,orgasme_sur_5,ressenti_mental_sur_5,type_ejaculation,notes`.
- Only `notes` goes through the formula-injection guard. The other new columns are integers or a closed enumeration.
- `README.md` is not modified. User-facing copy about the new defaults goes in the app.
- UI copy is French throughout.
- `MARKETING_VERSION` goes 1.3.0 → 1.4.0, in `project.yml` only.
- Verification is `swift test` plus the GitHub Actions iOS build. There is no local Swift toolchain on the author's Windows machine, so commit early and let CI compile.

## Review Focus

These are the input classes and failure modes the spec implies but no listed test exercises. Each one gets a test added to the task that owns the code.

1. **A `journal.json` written by a 1.3.0 build** — six keys present, three absent. It must load with defaults, not fail. → Task 1.
2. **A `journal.json` that is a hand-edited array where one record is corrupt** — the other records must survive `decodeRecovering` with the new fields defaulted, and only the corrupt one counted as rejected. → Task 1.
3. **A session saved between 1.3.0 and 1.4.0, then opened in 1.4.0 and edited** — the three new fields now hold `3 / 3 / aucune`, and re-saving must write them explicitly so the next build is stable. → Task 1.
4. **`orgasm` or `mental` decoded as `0` or `6` from a hand-edited file** — must be rejected by `isValid`, so the record is quarantined rather than plotted on a 1-5 axis. → Task 1.
5. **An old spreadsheet pointed at the new export** — column positions shift by three. Nothing in the app can catch this, so `README` stays untouched and the header is asserted verbatim in the test. → Task 3.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/WellbeingCore/Session.swift` | `Ejaculation` enum, the three new `Session` fields, the hand-written `init(from:)`, the explicit memberwise `init`, `isValid`, the new `Journal.csv` columns |
| `Tests/WellbeingCoreTests/JournalTests.swift` | every test for the above |
| `App/RatingRow.swift` (new) | one reusable 1-5 button row, bound to a `Binding<Int>`, with its five labels |
| `App/SessionEditor.swift` | consumes `RatingRow` three times, adds the `Ejaculation` picker |
| `App/JournalView.swift` | session row shows the three new measures compactly |
| `App/TrendsView.swift` | `ChartMetric` gains `.orgasm` and `.mental`; new categorical bar chart |
| `App/SettingsView.swift` | one static footnote about defaulted legacy values |
| `project.yml` | `MARKETING_VERSION` 1.4.0 |

---

### Task 1: Data model, backward-compatible decoding, validation, CSV

**Files:**
- Modify: `Sources/WellbeingCore/Session.swift`
- Test: `Tests/WellbeingCoreTests/JournalTests.swift`

**Interfaces:**
- Consumes: nothing. This task owns the model.
- Produces: `public enum Ejaculation: String, Codable, CaseIterable` with cases `aucune`, `baveuse`, `jet` and a `label: String` property; `Session` properties `orgasm: Int`, `mental: Int`, `ejaculation: Ejaculation`; `Session.init(id:date:duration:feeling:orgasm:mental:ejaculation:notes:)` with the three new parameters inserted **between `feeling` and `notes`**, each defaulting so all existing call sites keep compiling; `Journal.csv(_:)` gains three columns.

- [ ] **Step 1: Write the failing backward-compatibility test**

Append to `Tests/WellbeingCoreTests/JournalTests.swift`. This is the test that protects every existing user's data.

```swift
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter testDecodesJournalWrittenBeforeTheNewFields`
Expected: FAIL — `cannot find 'orgasm' in scope`.

- [ ] **Step 3: Add the enum and the three fields with a hand-written `init(from:)`**

In `Sources/WellbeingCore/Session.swift`, declare above `Session`:

```swift
public enum Ejaculation: String, Codable, CaseIterable {
    case aucune, baveuse, jet

    public var label: String {
        switch self {
        case .aucune: "Aucune"
        case .baveuse: "Baveuse"
        case .jet: "Jet"
        }
    }
}
```

Add `orgasm`, `mental` and `ejaculation` to `Session` with a default value on each, and extend the existing memberwise `init` so the three new parameters sit **between `feeling` and `notes`** and default to `3`, `3` and `.aucune`. The order is load-bearing: later tasks and tests call `Session(duration:feeling:orgasm:mental:ejaculation:notes:)`. Then add this decoder below `isValid`. `encode(to:)` is left synthesized — it writes all six fields.

```swift
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        feeling = try container.decode(Int.self, forKey: .feeling)
        // Absent in every journal written before 1.4.0: default, never fail.
        orgasm = try container.decodeIfPresent(Int.self, forKey: .orgasm) ?? 3
        mental = try container.decodeIfPresent(Int.self, forKey: .mental) ?? 3
        ejaculation = try container.decodeIfPresent(Ejaculation.self, forKey: .ejaculation) ?? .aucune
        notes = try container.decode(String.self, forKey: .notes)
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter testDecodesJournalWrittenBeforeTheNewFields`
Expected: PASS.

- [ ] **Step 5: Write the failing validation tests**

Append to the same test class:

```swift
    func testRejectsOutOfRangeNewScales() {
        XCTAssertThrowsError(try Journal.encode([Session(duration: 10, orgasm: 0)]))
        XCTAssertThrowsError(try Journal.encode([Session(duration: 10, orgasm: 6)]))
        XCTAssertThrowsError(try Journal.encode([Session(duration: 10, mental: 0)]))
        XCTAssertThrowsError(try Journal.encode([Session(duration: 10, mental: 6)]))
        XCTAssertNoThrow(try Journal.encode([Session(duration: 10, orgasm: 1, mental: 5)]))
    }

    func testRoundTripsTheNewFields() throws {
        let session = Session(duration: 42, feeling: 4, orgasm: 5, mental: 2, ejaculation: .jet, notes: "Net")
        let decoded = try Journal.decode(Journal.encode([session]))
        XCTAssertEqual(decoded, [session])
    }
```

- [ ] **Step 6: Run them to verify they fail**

Run: `swift test --filter "testRejectsOutOfRangeNewScales|testRoundTripsTheNewFields"`
Expected: FAIL — `isValid` does not range-check the new fields yet.

- [ ] **Step 7: Extend `isValid`**

In `Session.isValid`, add `(1...5).contains(orgasm) && (1...5).contains(mental)` alongside the existing feeling check. `Ejaculation` needs no check.

- [ ] **Step 8: Run them to verify they pass**

Run: `swift test --filter "testRejectsOutOfRangeNewScales|testRoundTripsTheNewFields"`
Expected: PASS.

- [ ] **Step 9: Write the failing recovery test**

Append to the same test class:

```swift
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
```

- [ ] **Step 10: Run the whole suite so far**

Run: `swift test`
Expected: PASS, all five new tests green. If `testRecoveryKeepsLegacyRecordsAlongsideACorruptOne` FAILS, the `decodeIfPresent` defaults are not reaching `decodeRecovering`, which is the exact defect this task exists to prevent. Fix Step 3 before moving on.

- [ ] **Step 11: Write the failing CSV test**

Append to the same test class:

```swift
    func testCSVExposesEveryMeasure() {
        let csv = Journal.csv([Session(duration: 12, feeling: 4, orgasm: 5, mental: 2, ejaculation: .baveuse, notes: "Note")])
        XCTAssertTrue(csv.hasPrefix("date_utc,duree_secondes,ressenti_sur_5,orgasme_sur_5,ressenti_mental_sur_5,type_ejaculation,notes\r\n"))
        let row = csv.components(separatedBy: "\r\n")[1]
        XCTAssertTrue(row.hasSuffix(",4,5,2,baveuse,\"Note\""))
    }
```

- [ ] **Step 12: Run it to verify it fails**

Run: `swift test --filter testCSVExposesEveryMeasure`
Expected: FAIL — the header still has four columns.

- [ ] **Step 13: Add the three CSV columns**

In `Journal.csv`, insert the three values between `String(session.feeling)` and `safeCSVField(session.notes)`, in this order: `String(session.orgasm)`, `String(session.mental)`, `session.ejaculation.rawValue`. Leave `safeCSVField` applied to `notes` only.

- [ ] **Step 14: Run the whole suite**

Run: `swift test`
Expected: PASS, including the pre-existing `testCSVQuotesNewlinesAndNeutralizesFormulas`, which asserts the `date_utc,duree_secondes,ressenti_sur_5,notes` prefix. **That pre-existing test will now fail on the header** — update only its `hasPrefix` assertion to the new header; leave every other assertion in it untouched.

- [ ] **Step 15: Commit**

```bash
git add Sources/WellbeingCore/Session.swift Tests/WellbeingCoreTests/JournalTests.swift
git commit -m "feat: add orgasm, mental and ejaculation fields to the session model"
```

---

### Task 2: Editor and journal

**Files:**
- Create: `App/RatingRow.swift`
- Modify: `App/SessionEditor.swift`
- Modify: `App/JournalView.swift`

**Interfaces:**
- Consumes: `Session.orgasm: Int`, `Session.mental: Int`, `Session.ejaculation: Ejaculation` binding through `@State`, `Ejaculation.allCases: [Ejaculation]`, `Ejaculation.label: String` from Task 1.
- Produces: `struct RatingRow: View` with `init(title: String, labels: [String], value: Binding<Int>)`, used by `SessionEditor` and by nothing else.

- [ ] **Step 1: Create `App/RatingRow.swift`**

A `View` with exactly this interface:

```swift
struct RatingRow: View {
    let title: String
    let labels: [String]
    @Binding var value: Int
}
```

It renders `title`, then an `HStack` of five buttons. Button `i` shows `labels[i]`, is filled when `i + 1 <= value`, uses `.buttonStyle(.borderedProminent)` with teal when filled and plain when not, and carries `.accessibilityLabel("\(title) : \(labels[i])")`. Every button gets `.frame(minWidth: 44, minHeight: 44)`. Tapping button `i` sets `value = i + 1`.

- [ ] **Step 2: Wire the three scales into `SessionEditor`**

Replace the existing `Picker("Ressenti", …)` section with three `RatingRow` uses, bound to `$session.feeling`, `$session.orgasm` and `$session.mental`, labelled with the three label sets from Global Constraints. Add one `Picker("Type d’éjaculation", selection: $session.ejaculation)` with `ForEach(Ejaculation.allCases, id: \.self) { Text($0.label).tag($0) }` and `.pickerStyle(.segmented)`.

`SessionEditor`'s existing `valid` computed property already re-checks `session.isValid` on the whole struct, so the new fields are validated by construction once they are bound.

- [ ] **Step 3: Build to verify it compiles**

Run: `git push origin main`, then `gh run watch --exit-status` on the new run.
Expected: `Test and build IPA` succeeds. The iOS build is the only compiler available; do not move on until it is green.

- [ ] **Step 4: Show the three measures in the journal row**

In `App/JournalView`, in the session row's caption `HStack`, replace the single `Label("Ressenti \(session.feeling)/5", systemImage: "heart")` with a row of compact `Text` badges reading `Ressenti \(session.feeling)/5`, `Orgasme \(session.orgasm)/5`, `Mental \(session.mental)/5`, followed by `session.ejaculation.label`. Keep the whole row `.font(.caption).foregroundStyle(.secondary)` so the added width stays inside the line budget on iPhone; if it truncates, move the badges to their own line rather than shrinking the font.

- [ ] **Step 5: Commit**

```bash
git add App/RatingRow.swift App/SessionEditor.swift App/JournalView.swift
git commit -m "feat: rate orgasm, mental state and ejaculation in the editor"
```

---

### Task 3: Trends

**Files:**
- Modify: `App/TrendsView.swift`

**Interfaces:**
- Consumes: `Session.orgasm`, `Session.mental`, `Ejaculation` and `Ejaculation.allCases` from Task 1.
- Produces: nothing consumed later.

- [ ] **Step 1: Extend `ChartMetric`**

`ChartMetric` currently has `case duration, feeling` with `title`, `axisLabel`, `color` and `value(_:)`. Add `case orgasm` and `case mental`. Their `title` is `Ressenti de l'orgasme` and `Ressenti mental`, `axisLabel` is `Ressenti sur 5` for both, `color` is `.purple` and `.indigo` respectively (distinct from the existing teal and purple), and `value(_:)` returns `Double(session.orgasm)` and `Double(session.mental)`.

- [ ] **Step 2: Confirm the Y domain needs no change**

`SessionChart.domain` is `1...5` for every metric that is not `.duration`. Read it and confirm `.orgasm` and `.mental` both fall in that branch. No edit is expected; this step exists so a future metric that is not a 1-5 scale cannot slip through unnoticed.

- [ ] **Step 3: Render the two curves**

In the charts `VStack`, add `SessionChart(sessions: sessions, selectedID: $selectedID, metric: .orgasm)` and the same with `.mental`, after the existing feeling chart.

- [ ] **Step 4: Add the categorical bar chart**

In the same `VStack`, add a `VStack(alignment: .leading, spacing: 12)` containing a `Text("Type d’éjaculation").font(.title3.bold())` and a `Chart` with, for each of `Ejaculation.allCases`, a `BarMark(x: .value("Type", type.label), y: .value("Séances", count))` where `count` is how many of `sessions` have that type. Use `.foregroundStyle(.teal)` and `.frame(height: 180)`. Give the `Chart` an `.accessibilityLabel("Répartition des types d’éjaculation")`. This chart has no selection and does not touch `selectedID`.

- [ ] **Step 5: Build to verify it compiles**

Run: `git push origin main`, then `gh run watch --exit-status`.
Expected: `Test and build IPA` succeeds.

- [ ] **Step 6: Commit**

```bash
git add App/TrendsView.swift
git commit -m "feat: chart orgasm, mental and ejaculation type"
```

---

### Task 4: Defaults notice and version

**Files:**
- Modify: `App/SettingsView.swift`
- Modify: `project.yml`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: nothing.

- [ ] **Step 1: Add the footnote in Réglages**

In `App/SettingsView`, inside the `Section("Vos données")`, after the existing export caption, add a second `Text` with `.font(.footnote).foregroundStyle(.secondary)` reading: `Les séances enregistrées avant la version 1.4.0 affichent 3/5 pour le ressenti de l’orgasme et le ressenti mental, et « Aucune » pour le type d’éjaculation. Ouvrez-les pour les corriger.`

`README.md` stays untouched, per Global Constraints.

- [ ] **Step 2: Bump the version**

In `project.yml`, change `MARKETING_VERSION: "1.3.0"` to `MARKETING_VERSION: "1.4.0"`.

- [ ] **Step 3: Verify the whole suite and the build**

Run: `git push origin main`, then `gh run watch --exit-status`.
Expected: both jobs green. The bot then commits a refreshed `repo.json` whose `version` is `1.4.0`; confirm with `git pull --rebase` then read `https://raw.githubusercontent.com/Leboxis/TimeTrack/main/repo.json` and check `versions[0].version == "1.4.0"` and that `buildVersion` advanced.

- [ ] **Step 4: Commit**

```bash
git add App/SettingsView.swift project.yml
git commit -m "docs: explain defaulted legacy values and bump to 1.4.0"
```
