import XCTest
@testable import WellbeingCore

final class RedditAccountTests: XCTestCase {
    func testReadsUsernameAndModhashFromMeJSON() throws {
        let json = """
        {"kind":"t2","data":{"name":"clairbear99","modhash":"f0f0f0f0f0f0f0f0f0"}}
        """
        let account = try RedditAccount.decode(Data(json.utf8))
        XCTAssertEqual(account.username, "clairbear99")
        XCTAssertEqual(account.modhash, "f0f0f0f0f0f0f0f0f0")
    }

    func testRejectsAnAnonymousMeJSON() {
        // Anonymous `me.json` returns an error envelope, never a modhash.
        let json = """
        {"kind":"t2","data":null,"error":403}
        """
        XCTAssertThrowsError(try RedditAccount.decode(Data(json.utf8)))
    }

    func testSaveAndUnsaveBodies() throws {
        let body = try RedditAccount.saveBody(fullname: "t3_abc123", modhash: "mh")
        let values = try XCTUnwrap(URLComponents(string: "https://x.invalid/?" + body)!.percentEncodedQuery)
        XCTAssertTrue(values.contains("id=t3_abc123"))
        XCTAssertTrue(values.contains("uh=mh"))
        XCTAssertTrue(try RedditAccount.saveBody(fullname: "t3_abc", modhash: "mh")
            .hasPrefix("id=t3_abc&uh="))
    }

    func testSaveActionURLs() {
        let account = RedditAccount(username: "u", modhash: "mh")
        XCTAssertEqual(RedditAccount.actionURL(.save).absoluteString, "https://www.reddit.com/api/save")
        XCTAssertEqual(RedditAccount.actionURL(.unsave).absoluteString, "https://www.reddit.com/api/unsave")
        XCTAssertEqual(account.actionURL(.save).absoluteString, "https://www.reddit.com/api/save")
    }

    func testPersistedSavedSetRoundTrips() throws {
        let set = RedditAccount.savedSet(from: "[\"t3_a\",\"t3_b\"]")
        XCTAssertEqual(set, ["t3_a", "t3_b"])
        XCTAssertEqual(RedditAccount.savedSet(from: "[\"t3_a\",\"t3_b\"]"), set)
        XCTAssertTrue(RedditAccount.savedSet(from: "").isEmpty)
        XCTAssertTrue(RedditAccount.savedSet(from: "pas du json").isEmpty)
    }
}
