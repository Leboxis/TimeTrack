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

    func testExtractFallsBackToPreviewForQuarantinedFeeds() {
        // Exactly the shape a quarantined NSFW feed serves after entity decoding:
        // a preview.redd.it <img> inside an escaped content blob, no original link.
        let html = "<a href=\"https://www.reddit.com/r/feet/comments/abc/x/\"> " +
                   "<img src=\"https://preview.redd.it/photo.jpeg?width=640&amp;auto=webp&amp;s=zz\">"
        let media = MediaExtractor.extract(html)
        XCTAssertEqual(media, [.direct(URL(string: "https://i.redd.it/photo.jpeg")!)])
    }

    func testExtractDoesNotTrustForeignPreviewHosts() {
        let html = "<img src=\"https://preview.redd.it.evil.example/photo.jpeg\"> " +
                   "<img src=\"http://preview.redd.it/photo.jpeg\">"
        XCTAssertTrue(MediaExtractor.extract(html).isEmpty)
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

    func testHTTPErrorCarriesStatusCode() {
        XCTAssertTrue(FeedError.http(401).errorDescription?.contains("401") == true)
    }

    func testGalleryKeepsItemsWithoutStatus() throws {
        let json = """
        [{"kind":"Listing","data":{"children":[{"kind":"t3","data":{
          "gallery_data":{"items":[{"media_id":"abc"}]},
          "media_metadata":{"abc":{"m":"image/jpg","s":{"u":"https://preview.redd.it/abc.jpg?auto=webp"}}}
        }}]}}]
        """
        let media = try GalleryFeed.parse(Data(json.utf8))
        XCTAssertEqual(media, [.direct(URL(string: "https://i.redd.it/abc.jpg")!)])
    }

    func testGalleryKeepsGifWithOnlyU() throws {
        let json = """
        [{"kind":"Listing","data":{"children":[{"kind":"t3","data":{
          "gallery_data":{"items":[{"media_id":"abc"}]},
          "media_metadata":{"abc":{"m":"image/gif","s":{"u":"https://preview.redd.it/abc.gif?auto=webp"}}}
        }}]}}]
        """
        let media = try GalleryFeed.parse(Data(json.utf8))
        XCTAssertEqual(media, [.direct(URL(string: "https://i.redd.it/abc.gif")!)])
    }
}
