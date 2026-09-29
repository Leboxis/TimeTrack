# RSS media feed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A full-screen vertical media feed for a level-grouped subreddit menu, with images, Reddit video, Redgifs and carousels playing inline, plus empty-but-functional gallery and media sections.

**Architecture:** Port the reference project's feed layer (`Redditmediapocket`, read-only at `C:\Users\KEDI-ADMIN\Documents\Project\Redditmediapocket`) in two halves. Pure logic (RSS parsing, media-URL extraction, Redgifs API shapes) goes into `WellbeingCore` verbatim where possible and gets unit tests. Stateful UI (feed model, pager, player, level menu) goes into `App/` and is verified by the iOS compile plus on-device checks. Downloads, DASH merging, prefetching, auth, saving and collections are dropped; Reddit video streams HLS directly and images stream without temp files.

**Tech Stack:** Swift 5, SwiftUI, Swift Charts (untouched), Foundation (`XMLParser`, `URLSession`, `AVPlayer` via `AVPlayerViewController`), `UserDefaults`. iOS 17, no third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-29-media-feed-design.md`

## Global Constraints

- Reference code is copied verbatim wherever the spec's table says "verbatim". Where it says "verbatim", the implementer does not restyle, rename or "improve" — byte-equivalent logic, Swift formatting only.
- French UI copy throughout. No `L(_:_:)` helper; French strings are literals.
- `User-Agent` is exactly `Wellbeing/1.6 (iOS; RSS reader)`.
- Feed URL is exactly `https://www.reddit.com/r/<name>/new.rss?limit=25`. No `after`, no other sort.
- Subreddit validation is exactly `^[A-Za-z0-9_]{2,21}$`.
- Level 0 is BBWFeet, MommyMilfs, PublicFeetPics, feet, feetgooned, vagina. Level 1 is burstingout, OnOff. Level 2 is milfspanties, classyboners. Level 3 is ClothedForPrejac. Level 4 is CensoredFeet.
- `README.md` changes are limited to the one sentence the spec names. Nothing else in the README moves.
- `MARKETING_VERSION` goes 1.5.0 → 1.6.0, in `project.yml` only.
- There is no local Swift toolchain, so every `Run: swift test` step executes on GitHub Actions (push, watch, read the log). A test-only push that turns the build red is the RED half of the cycle, not an incident.
- `App/` has no unit-test target. Tasks 2-4 are verified by the iOS compile, never by invented tests.

## Review Focus

1. **A subreddit that does not exist** (404) or a private one (403) — the feed must show the error screen with a retry button, never an infinite spinner and never a crash. No unit test covers this (network); it is a device check in Task 2.
2. **A post whose HTML carries no playable media** — it must be skipped before rendering, so the pager never shows a blank card. Covered by the extraction test (unknown host → no `Media`) plus the entry-building rule in Task 2.
3. **A Redgifs token that expires mid-session** (401 on the gif call) — invalidate once and retry once, then surface the error. Device check in Task 2; the single-retry rule is in the spec table.
4. **Airplane mode / no connectivity** — a `URLError` must become the friendly error screen, not a crash and not a silent empty feed. Device check in Task 2.
5. **An HLS URL for a removed video** — `AVPlayer` fails on that card only; the card shows its error state and swiping keeps working. This is the spec's open HLS assumption; if it fails on device, the fallback is porting the reference DASH pipeline, which is a new task, not a fix inside this plan.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/WellbeingCore/Feed.swift` (new) | `Post`, `Media`, `FeedError`, `FeedParser`, feed-URL construction, subreddit validation, `MediaExtractor`, `GalleryFeed`, `QualityPolicy`, `RedgifsAPI` |
| `Tests/WellbeingCoreTests/FeedTests.swift` (new) | the six tests below |
| `App/FeedLevel.swift` (new) | the five levels and their subreddit lists |
| `App/FeedModel.swift` (new) | subreddit persistence, `load()`, Redgifs token cache, resolved-URL memory cache |
| `App/FeedView.swift` (new) | the vertical pager, level menu, loading / error / empty / refresh states |
| `App/FeedCard.swift` (new) | one post: thumbnail → resolved media → image or video, title/date overlay |
| `App/AutoPlayVideo.swift` (new) | `AVPlayerViewController` wrapper, loop, active-driven play/pause, teardown |
| `App/GalleryCatalog.swift`, `App/GalleryPickerView.swift`, `App/GalleryViewer.swift` (new) | empty catalog, picker, swipeable viewer |
| `App/MediaCatalog.swift`, `App/MediaLibraryView.swift` (new) | empty catalog, "coming soon" screen |
| `App/MethodListView.swift` | the three buttons above the method list |
| `App/SettingsView.swift` | the rewritten Confidentialité copy |
| `README.md` | the one sentence |
| `project.yml` | 1.6.0 |

---

## Setup (before Task 1)

- [ ] Create the plan workspace and ledger:

```bash
New-Item -ItemType Directory -Force -Path ".superpowers/sdd/2026-09-29-media-feed"
```

Write `.superpowers/sdd/2026-09-29-media-feed/progress.md` with the first line `# SDD ledger — plan: docs/superpowers/plans/2026-09-29-media-feed.md`, then the setup rulings: work on `main` (standing consent + `publish` only runs there), `swift test` runs on Actions, Tasks 2-4 have no unit tests (verification is the iOS compile), and a pre-flight row confirming Task 2 consumes exactly what Task 1 produces.

---

### Task 1: Core parsing and its tests

**Files:**
- Create: `Sources/WellbeingCore/Feed.swift`
- Test: `Tests/WellbeingCoreTests/FeedTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `Post`, `Media`, `FeedError`, `FeedParser.parse(_:)`, `feedURL(subreddit: String) -> URL`, `subredditName(_:) throws -> String`, `MediaExtractor.extract(_:) -> [Media]`, `MediaExtractor.previewImage(_:) -> URL?`, `GalleryFeed.linkedID(_:) -> String?`, `GalleryFeed.commentsJSONURL(feedID:) -> URL?`, `QualityPolicy.originalImageURL(_:) -> URL`, `RedgifsAPI.gifURL(id:) -> URL`. Task 2 consumes every one of these by exactly these names.

- [ ] **Step 1: Write the six failing tests**

Create `Tests/WellbeingCoreTests/FeedTests.swift`. All six fail to compile — that is the RED.

```swift
import XCTest
@testable import WellbeingCore

final class FeedTests: XCTestCase {
    func testFeedURLFallsBackToNew() {
        XCTAssertEqual(feedURL(subreddit: "feet").absoluteString,
            "https://www.reddit.com/r/feet/new.rss?limit=25")
    }

    func testSubredditValidation() throws {
        XCTAssertEqual(try subredditName("  vagina "), "vagina")
        XCTAssertThrowsError(try subredditName("a"))
        XCTAssertThrowsError(try subredditName(String(repeating: "a", count: 22)))
        XCTAssertThrowsError(try subredditName("feet!"))
    }

    func testParsesFrozenAtomFeed() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>t3_abc123</id>
            <title>Premier post</title>
            <content type="html"><![CDATA[<a href="https://i.redd.it/x.jpg">x</a>]]></content>
            <published>2024-01-01T00:00:00+00:00</published>
            <link href="https://www.reddit.com/r/feet/comments/abc123/premier/" />
          </entry>
          <entry>
            <id>t3_def456</id>
            <title>Second post</title>
            <content type="html"><![CDATA[rien ici]]></content>
            <published>2024-01-02T00:00:00+00:00</published>
            <link href="https://www.reddit.com/r/feet/comments/def456/second/" />
          </entry>
        </feed>
        """
        let posts = try FeedParser.parse(Data(xml.utf8))
        XCTAssertEqual(posts.count, 2)
        XCTAssertEqual(posts[0].id, "t3_abc123")
        XCTAssertEqual(posts[0].title, "Premier post")
        XCTAssertEqual(posts[0].link, "https://www.reddit.com/r/feet/comments/abc123/premier/")
        XCTAssertNotNil(posts[0].publishedAt)
    }

    func testRejectsDocumentWithoutFeedRoot() {
        XCTAssertThrowsError(try FeedParser.parse(Data("<html></html>".utf8)))
    }

    func testExtractsKnownMediaAndDropsTheRest() {
        let html = """
        <a href="https://v.redd.it/abc123/">v</a>
        <a href="https://www.redgifs.com/watch/jauntylegalcobalt">g</a>
        <a href="https://i.redd.it/photo.jpg">i</a>
        <a href="https://example.com/evil.mp4">x</a>
        <a href="https://i.redd.it/photo.jpg">i</a>
        """
        let media = MediaExtractor.extract(html)
        XCTAssertEqual(media.count, 3)
    }

    func testStripsImgurSuffixAndBuildsGalleryURL() {
        XCTAssertEqual(
            QualityPolicy.originalImageURL(URL(string: "https://i.imgur.com/Ab12Cd3l.jpg")!).absoluteString,
            "https://i.imgur.com/Ab12Cd3.jpg")
        XCTAssertEqual(
            GalleryFeed.commentsJSONURL(feedID: "t3_1wlhnh1")?.absoluteString,
            "https://www.reddit.com/comments/1wlhnh1.json?raw_json=1&limit=1")
        XCTAssertNil(GalleryFeed.commentsJSONURL(feedID: "t3_!!!"))
    }
}
```

- [ ] **Step 2: Push and watch it fail**

```bash
git add Tests/WellbeingCoreTests/FeedTests.swift
git commit -m "test: specify the feed parsing layer (RED)"
git pull --rebase origin main
git push origin main
```

Then `gh run watch --exit-status` on the new run.
Expected: FAIL with `cannot find 'feedURL' in scope` (and siblings). Read the log and confirm the failure is the missing API, not a typo in the test.

- [ ] **Step 3: Port `Sources/WellbeingCore/Feed.swift`**

Copy from the reference, per the spec table: `Post`, `Media`, `FeedError` (French literals, no `L` helper), `FeedParser` + `parseDate`, `feedURL` (subreddit branch only, `limit=25`, sort fixed to `new`), `subredditName`, `MediaExtractor` (`extract` + `previewImage`, allowlists verbatim), `GalleryFeed` (`linked`/`linkedID`/`commentsJSONURL`/`parse`), `QualityPolicy` (`originalImageURL` + `redgifsCandidates`), `RedgifsAPI` (`gifURL` + `headers`). Skip `MediaExtractor.username`, the Redgifs user-search response, and everything download-shaped.

Naming contract with the tests: the free functions are `feedURL(subreddit:)`, `subredditName(_:)`, the types expose exactly the members the tests touch.

- [ ] **Step 4: Push and watch it pass**

```bash
git add Sources/WellbeingCore/Feed.swift
git commit -m "feat: port the feed parsing layer"
git pull --rebase origin main
git push origin main
```

Then `gh run watch --exit-status` and `gh run view --log`.
Expected: `swift test` green, all six new tests passing, pre-existing suite untouched.

- [ ] **Step 5: Ledger the task**

Append `Task 1: complete (commits <base7>..<head7>, tests: GitHub Actions swift test → 22/22 pass)` to `.superpowers/sdd/2026-09-29-session-fields/progress.md` — wait, wrong workspace. This plan owns `.superpowers/sdd/2026-09-29-media-feed/progress.md`, created below in Setup. The ledger line goes there.

---

### Task 2: Feed model, pager, cards, player, level menu

**Files:**
- Create: `App/FeedLevel.swift`, `App/FeedModel.swift`, `App/FeedView.swift`, `App/FeedCard.swift`, `App/AutoPlayVideo.swift`

**Interfaces:**
- Consumes: every Task 1 name listed above.
- Produces: `FeedView` (no parameters), used by Task 4's buttons. Nothing else consumes these files.

- [ ] **Step 1: `App/FeedLevel.swift`**

The enum from the spec with the five levels and their lists, verbatim.

- [ ] **Step 3: `App/FeedModel.swift`**

`@MainActor @Observable final class FeedModel`: `subreddit` (persisted under `wellbeing.feed.subreddit`, default `feet`), `posts: [Post]`, `loading: Bool`, `errorMessage: String?`, a 30-minute Redgifs token cache, a `[String: URL]` resolved-media memory cache, and `load()` which validates via `subredditName`, fetches with the exact `User-Agent`, checks 200-299, parses with `FeedParser`, and maps any `URLError` to a French offline message. `resolve(_ post:) async throws -> URL?` implements the per-type resolution from the spec (direct stream, HLS URL, Redgifs token + hd/sd, gallery JSON) and fills the memory cache.

- [ ] **Step 4: `App/AutoPlayVideo.swift`, `App/FeedCard.swift`, `App/FeedView.swift`**

`AutoPlayVideo`: the reference coordinator verbatim. `FeedCard`: black background, thumbnail from `previewImage` while resolving, image via streaming `URLSession` data task, video via `AutoPlayVideo`, gallery via a horizontal `TabView(.page)` of its images, title/date overlay, error state with retry. `FeedView`: the reference pager verbatim minus `scrollTransition` decoration only if it misbehaves on device (keep it initially), level `Menu` in the toolbar, loading / error-with-retry / pull-to-refresh states, entries built exactly like the reference `savedFeedEntries` (one entry per media, gallery posts as gallery entries, media-less posts skipped).

- [ ] **Step 5: Push and watch the compile**

```bash
git add App/FeedLevel.swift App/FeedModel.swift App/AutoPlayVideo.swift App/FeedCard.swift App/FeedView.swift
git commit -m "feat: fullscreen paged media feed"
git pull --rebase origin main
git push origin main
```

Then `gh run watch --exit-status`.
Expected: `Test and build IPA` succeeds. That is the whole verification available for this task.

---

### Task 3: Gallery and media sections

**Files:**
- Create: `App/GalleryCatalog.swift`, `App/GalleryPickerView.swift`, `App/GalleryViewer.swift`, `App/MediaCatalog.swift`, `App/MediaLibraryView.swift`

**Interfaces:**
- Consumes: nothing from Tasks 1-2.
- Produces: `GalleryPickerView`, `MediaLibraryView` (no parameters), used by Task 4's buttons.

- [ ] **Step 1: Catalogs and views**

`GalleryCatalog.all: [Gallery]` empty, `Gallery` with `id`, `title`, `imageNames: [String]`. `GalleryPickerView` lists them or shows `ContentUnavailableView("Aucune galerie", …)`. `GalleryViewer(gallery:)` is a `TabView` with `.tabViewStyle(.page(indexDisplayMode: .automatic))` over `Image(name)` pages — functional now, content later. `MediaCatalog.all` empty, `MediaLibraryView` shows `ContentUnavailableView("Contenu à venir", …)`.

- [ ] **Step 2: Push and watch the compile**

```bash
git add App/GalleryCatalog.swift App/GalleryPickerView.swift App/GalleryViewer.swift App/MediaCatalog.swift App/MediaLibraryView.swift
git commit -m "feat: gallery and media sections"
git pull --rebase origin main
git push origin main
```

Then `gh run watch --exit-status`.
Expected: `Test and build IPA` succeeds.

---

### Task 4: Tab buttons, privacy copy, version

**Files:**
- Modify: `App/MethodListView.swift`, `App/SettingsView.swift`, `README.md`, `project.yml`

**Interfaces:**
- Consumes: `FeedView`, `GalleryPickerView`, `MediaLibraryView` from Tasks 2-3.
- Produces: nothing.

- [ ] **Step 1: The three buttons**

In `App/MethodListView`, above the method list, an `HStack` of three `NavigationLink`s to `FeedView()`, `MediaLibraryView()` and `GalleryPickerView()`, labelled Flux, Médias, Galeries, each with an SF Symbol and `.buttonStyle(.bordered)`.

- [ ] **Step 2: Privacy copy and version**

`App/SettingsView`: the Confidentialité `Label` becomes `Journal local, sans compte ni suivi`, the body becomes `Le journal reste dans son espace local et peut être inclus dans les sauvegardes de votre appareil. Exportez-le avant de désinstaller l'app ou son conteneur. Seul le flux RSS contacte Reddit pour afficher son contenu public.` `README.md`: replace `Aucun compte, serveur, service de suivi ou dépendance applicative tierce.` with `Aucun compte ni service de suivi. Le flux RSS charge du contenu public depuis Reddit.` `project.yml`: `MARKETING_VERSION` 1.5.0 → 1.6.0.

- [ ] **Step 3: Push, watch, confirm the source**

```bash
git add App/MethodListView.swift App/SettingsView.swift README.md project.yml
git commit -m "feat: expose the feed and update privacy copy (1.6.0)"
git pull --rebase origin main
git push origin main
```

Then `gh run watch --exit-status`, then `git pull --rebase`, then read `https://raw.githubusercontent.com/Leboxis/TimeTrack/main/repo.json` and confirm `versions[0].version == "1.6.0"`.
Expected: both jobs green, source shows 1.6.0.
