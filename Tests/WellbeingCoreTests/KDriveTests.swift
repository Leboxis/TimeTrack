import XCTest
@testable import WellbeingCore

final class KDriveTests: XCTestCase {
    private let config = KDriveConfig(token: "tk", driveID: "42")

    private func unwrap(_ url: URL?) -> String {
        (try? XCTUnwrap(url))?.absoluteString ?? "<nil>"
    }

    // MARK: - Drive id validation

    func testAcceptsANumericDriveID() {
        XCTAssertTrue(KDriveConfig(token: "tk", driveID: "42").isComplete)
        XCTAssertTrue(KDriveConfig(token: "tk", driveID: "123456").isComplete)
    }

    func testTrimsWhitespaceAroundBothCredentials() {
        let padded = KDriveConfig(token: "  tk \n", driveID: " 42 ")
        XCTAssertEqual(padded.token, "tk")
        XCTAssertEqual(padded.driveID, "42")
        XCTAssertTrue(padded.isComplete)
    }

    func testRejectsAnIncompleteConfig() {
        XCTAssertFalse(KDriveConfig(token: "", driveID: "42").isComplete)
        XCTAssertFalse(KDriveConfig(token: "tk", driveID: "").isComplete)
    }

    /// A pasted id with a space or a slash used to reach `URL(string:)!` and trap.
    /// It is now refused as a credential, which is a message the user can act on.
    func testRejectsAMalformedDriveID() {
        XCTAssertFalse(KDriveConfig(token: "tk", driveID: "a b").isComplete)
        XCTAssertFalse(KDriveConfig(token: "tk", driveID: "42/../7").isComplete)
        XCTAssertFalse(KDriveConfig(token: "tk", driveID: "42?x=1").isComplete)
        XCTAssertFalse(KDriveConfig(token: "tk", driveID: "42#frag").isComplete)
        XCTAssertFalse(KDriveConfig(token: "tk", driveID: "%").isComplete)
    }

    func testRejectsAnAbsurdlyLongDriveID() {
        XCTAssertFalse(KDriveConfig(token: "tk", driveID: String(repeating: "9", count: 21)).isComplete)
    }

    /// Whatever the id looks like, the builders must hand back a usable URL rather
    /// than trapping. The encoded id simply will not resolve server-side.
    func testBuildersNeverTrapOnAMalformedDriveID() {
        let broken = KDriveConfig(token: "tk", driveID: "a b/c?d")
        XCTAssertNotNil(KDriveClient.driveURL(config: broken))
        XCTAssertNotNil(KDriveClient.listURL(config: broken, directoryID: "1", cursor: nil))
        XCTAssertNotNil(KDriveClient.downloadURL(config: broken, fileID: 1))
        XCTAssertNotNil(KDriveClient.thumbnailURL(config: broken, fileID: 1))
        XCTAssertNotNil(KDriveClient.temporaryURL(config: broken, fileID: 1, duration: 600))
    }

    func testBuilderEncodesTheDriveIDIntoThePath() {
        let broken = KDriveConfig(token: "tk", driveID: "a b")
        XCTAssertEqual(unwrap(KDriveClient.driveURL(config: broken)),
            "https://api.infomaniak.com/2/drive/a%20b")
    }

    // MARK: - URL shapes

    func testListingURLEscapesTheCursor() throws {
        let url = try XCTUnwrap(KDriveClient.listURL(config: config, directoryID: "1", cursor: nil))
        XCTAssertEqual(url.absoluteString,
            "https://api.infomaniak.com/3/drive/42/files/1/files?limit=200")
        let paged = try XCTUnwrap(KDriveClient.listURL(config: config, directoryID: "1", cursor: "a b+c"))
        XCTAssertEqual(paged.query, "limit=200&cursor=a%20b%2Bc")
    }

    func testDownloadURLShape() throws {
        // v2, not v3, and the id sits between `files` and `download`. The OpenAPI spec
        // has no /3/ download path at all.
        let url = try XCTUnwrap(KDriveClient.downloadURL(config: config, fileID: 77))
        XCTAssertEqual(url.absoluteString,
            "https://api.infomaniak.com/2/drive/42/files/77/download")
    }

    func testThumbnailAndTemporaryURLs() throws {
        let thumbnail = try XCTUnwrap(KDriveClient.thumbnailURL(config: config, fileID: 77))
        XCTAssertEqual(thumbnail.absoluteString,
            "https://api.infomaniak.com/2/drive/42/files/77/thumbnail")
        let temporary = try XCTUnwrap(KDriveClient.temporaryURL(config: config, fileID: 77, duration: 600))
        XCTAssertEqual(temporary.absoluteString,
            "https://api.infomaniak.com/2/drive/42/files/77/temporary_url?duration=600")
    }

    func testTemporaryURLClampsTheDuration() throws {
        let tooShort = try XCTUnwrap(KDriveClient.temporaryURL(config: config, fileID: 1, duration: 1))
        XCTAssertEqual(tooShort.query, "duration=60")
        let tooLong = try XCTUnwrap(KDriveClient.temporaryURL(config: config, fileID: 1, duration: 999_999))
        XCTAssertEqual(tooLong.query, "duration=86400")
    }

    func testDriveURLForConnectionTest() throws {
        let url = try XCTUnwrap(KDriveClient.driveURL(config: config))
        XCTAssertEqual(url.absoluteString, "https://api.infomaniak.com/2/drive/42")
    }

    // MARK: - Decoding

    func testDecodesAnItemAndTreatsNilTypeAsFile() throws {
        let json = """
        {"id":77,"name":"clip.mp4","type":"file","size":1234,"mime_type":"video/mp4","last_modified_at":1700000000}
        """
        let item = try JSONDecoder().decode(KDriveItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.id, 77)
        XCTAssertEqual(item.size, 1234)
        XCTAssertEqual(item.mimeType, "video/mp4")
        XCTAssertFalse(item.isDirectory)
    }

    func testDirectoryDetection() throws {
        func item(type: String?) -> KDriveItem {
            try! JSONDecoder().decode(KDriveItem.self,
                from: Data("{\"id\":1,\"name\":\"x\",\"type\":\(type.map { "\"\($0)\"" } ?? "null")}".utf8))
        }
        XCTAssertTrue(item(type: "dir").isDirectory)
        XCTAssertTrue(item(type: "directory").isDirectory)
        XCTAssertFalse(item(type: "file").isDirectory)
        XCTAssertFalse(item(type: nil).isDirectory)
    }

    func testDecodesTheResponseEnvelope() throws {
        let json = """
        {"result":"success","data":[{"id":1,"name":"a"},{"id":2,"name":"b"}],"has_more":false,"cursor":"n"}
        """
        let page = try KDriveClient.decodePage(Data(json.utf8))
        XCTAssertEqual(page.items.map(\.name), ["a", "b"])
        XCTAssertFalse(page.hasMore)
        XCTAssertEqual(page.cursor, "n")
    }

    func testMissingResultFailsTheDecode() {
        let json = """
        {"data":[],"has_more":false}
        """
        XCTAssertThrowsError(try KDriveClient.decodePage(Data(json.utf8)))
    }

    /// A bad token used to surface as "Erreur serveur (0)", which points the user at
    /// their Drive id instead of at the credential.
    func testEnvelopeAuthenticationFailureBecomesAuthenticationFailed() {
        for code in ["unauthorized", "unauthenticated", "forbidden", "invalid_token", "401"] {
            let json = """
            {"result":"error","error":{"code":"\(code)","description":"nope"}}
            """
            XCTAssertThrowsError(try KDriveClient.decodePage(Data(json.utf8))) { error in
                XCTAssertEqual(error as? KDriveError, .authenticationFailed, "code \(code)")
            }
        }
    }

    func testOtherEnvelopeErrorsKeepTheirDetail() {
        let json = """
        {"result":"error","error":{"code":"not_found","description":"Drive introuvable"}}
        """
        XCTAssertThrowsError(try KDriveClient.decodePage(Data(json.utf8))) { error in
            XCTAssertEqual(error as? KDriveError, .serverError(0, "not_found — Drive introuvable"))
        }
    }

    // MARK: - Signed URL extraction

    func testReadsTheSignedURLOutOfTheTemporaryURLEnvelope() throws {
        let json = """
        {"data":{"temporary_url":"https://drive.infomaniak.com/2/drive/42/files/77/download?token=abc"}}
        """
        let url = try XCTUnwrap(KDriveClient.signedURL(in: Data(json.utf8)))
        XCTAssertEqual(url.absoluteString,
            "https://drive.infomaniak.com/2/drive/42/files/77/download?token=abc")
    }

    /// The whole point of the streaming fix: a media body must never be mistaken for
    /// a signed URL, it must simply be refused.
    func testSignedURLExtractionRefusesAnythingThatIsNotOne() {
        XCTAssertNil(KDriveClient.signedURL(in: Data()))
        XCTAssertNil(KDriveClient.signedURL(in: Data("\u{0}\u{1}\u{2}not json".utf8)))
        XCTAssertNil(KDriveClient.signedURL(in: Data(#"{"data":{"temporary_url":"ftp://x/y"}}"#.utf8)))
        XCTAssertNil(KDriveClient.signedURL(in: Data(#"{"data":{}}"#.utf8)))
        // The first bytes of an MP4 header.
        XCTAssertNil(KDriveClient.signedURL(in: Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])))
    }

    // MARK: - Pagination

    func testListAllWalksEveryPageAndDropsDuplicates() async throws {
        var calls = 0
        let items = try await KDriveClient.listAll(config: config, directoryID: "1") { cursor in
            calls += 1
            switch calls {
            case 1:
                return KDrivePage(items: [KDriveItem(id: 1, name: "a"), KDriveItem(id: 2, name: "b")],
                                  hasMore: true, cursor: "c1")
            case 2:
                // A cursor can hand back an item the previous page already carried.
                return KDrivePage(items: [KDriveItem(id: 2, name: "b"), KDriveItem(id: 3, name: "c")],
                                  hasMore: true, cursor: "c2")
            default:
                return KDrivePage(items: [KDriveItem(id: 4, name: "d")], hasMore: false, cursor: nil)
            }
        }
        XCTAssertEqual(items.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(calls, 3)
    }

    func testListAllStopsWhenHasMoreComesWithoutACursor() async throws {
        var calls = 0
        let items = try await KDriveClient.listAll(config: config, directoryID: "1") { _ in
            calls += 1
            return KDrivePage(items: [KDriveItem(id: calls, name: "\(calls)")], hasMore: true, cursor: nil)
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(calls, 1)
    }

    func testListAllStopsOnARepeatedCursor() async throws {
        var calls = 0
        let items = try await KDriveClient.listAll(config: config, directoryID: "1") { _ in
            calls += 1
            return KDrivePage(items: [KDriveItem(id: calls, name: "\(calls)")], hasMore: true, cursor: "same")
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(calls, 2)
    }

    func testListAllPropagatesAPageFailure() async {
        struct Boom: Error {}
        do {
            _ = try await KDriveClient.listAll(config: config, directoryID: "1") { _ in
                throw Boom()
            }
            XCTFail("expected the page error to surface")
        } catch is Boom {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testMediaKindFromName() {
        XCTAssertEqual(KDriveClient.mediaKind(of: "a.mp4"), .video)
        XCTAssertEqual(KDriveClient.mediaKind(of: "a.M4A"), .audio)
        XCTAssertEqual(KDriveClient.mediaKind(of: "a.mkv"), .video)
        XCTAssertEqual(KDriveClient.mediaKind(of: "a.webm"), .video)
        XCTAssertEqual(KDriveClient.mediaKind(of: "a.jpg"), .image)
        XCTAssertEqual(KDriveClient.mediaKind(of: "a.PNG"), .image)
        XCTAssertEqual(KDriveClient.mediaKind(of: "notes.txt"), nil)
    }
}
