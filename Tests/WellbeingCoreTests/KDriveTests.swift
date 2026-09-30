import XCTest
@testable import WellbeingCore

final class KDriveTests: XCTestCase {
    func testListingURLEscapesTheCursor() throws {
        let config = KDriveConfig(token: "tk", driveID: "42")
        let url = KDriveClient.listURL(config: config, directoryID: "1", cursor: nil)
        XCTAssertEqual(url.absoluteString,
            "https://api.infomaniak.com/3/drive/42/files/1/files?limit=200")
        let paged = KDriveClient.listURL(config: config, directoryID: "1", cursor: "a b+c")
        XCTAssertEqual(paged.query, "limit=200&cursor=a%20b%2Bc")
    }

    func testDownloadURLShape() {
        let config = KDriveConfig(token: "tk", driveID: "42")
        let url = KDriveClient.downloadURL(config: config, fileID: 77)
        XCTAssertEqual(url.absoluteString,
            "https://api.infomaniak.com/3/drive/42/files/download/77")
    }

    func testDriveURLForConnectionTest() {
        let config = KDriveConfig(token: "tk", driveID: "42")
        XCTAssertEqual(KDriveClient.driveURL(config: config).absoluteString,
            "https://api.infomaniak.com/2/drive/42")
    }

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
