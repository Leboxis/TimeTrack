import XCTest
@testable import WellbeingCore

final class RedditSavedTests: XCTestCase {
    func testSavedFeedURL() throws {
        let url = try XCTUnwrap(RedditSaved.feedURL(username: "clairbear99", limit: 100))
        XCTAssertEqual(url.absoluteString,
            "https://www.reddit.com/user/clairbear99/saved.rss?limit=100")
    }

    func testSavedFeedURLCarriesTheAfterCursor() throws {
        let url = try XCTUnwrap(RedditSaved.feedURL(username: "user", limit: 100, after: "t3_abc"))
        XCTAssertEqual(url.query, "limit=100&after=t3_abc")
    }

    func testExtractsTheSavedIDsFromAnAtomFeed() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry><id>t3_aaa111</id><title>un</title></entry>
          <entry><id>t3_bbb222</id><title>deux</title></entry>
        </feed>
        """
        let posts = try FeedParser.parse(Data(xml.utf8))
        XCTAssertEqual(RedditSaved.ids(from: posts), ["t3_aaa111", "t3_bbb222"])
    }

    func testRejectsAUsernameWithUrlUnsafeCharacters() {
        XCTAssertNil(RedditSaved.feedURL(username: "a/b"))
        XCTAssertNil(RedditSaved.feedURL(username: ""))
        XCTAssertNil(RedditSaved.feedURL(username: "ab"))          // under 3 characters
        XCTAssertNil(RedditSaved.feedURL(username: "a/b c"))        // slash and space
    }

    func testMergeKeepsLocalSavesAndAddsRemotes() {
        let local: Set<String> = ["t3_local", "t3_stale"]
        let remote: Set<String> = ["t3_stale", "t3_remote"]
        let merged = RedditSaved.merge(local: local, remote: remote)
        XCTAssertTrue(merged.contains("t3_local"))   // saved here, absent remotely
        XCTAssertTrue(merged.contains("t3_remote"))  // saved elsewhere
        XCTAssertTrue(merged.contains("t3_stale"))
    }

    func testIsStaleHonoursTheTTL() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(RedditSaved.isStale(nil, now: now))
        XCTAssertTrue(RedditSaved.isStale(now.addingTimeInterval(-7_200), now: now))
        XCTAssertFalse(RedditSaved.isStale(now.addingTimeInterval(-60), now: now))
    }
}
