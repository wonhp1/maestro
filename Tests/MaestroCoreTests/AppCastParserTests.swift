@testable import MaestroCore
import XCTest

final class AppCastParserTests: XCTestCase {
    func testParsesSingleItem() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>Maestro</title>
            <item>
              <title>1.2.0</title>
              <sparkle:version>1.2.0</sparkle:version>
              <sparkle:releaseNotesLink>https://example.com/notes</sparkle:releaseNotesLink>
              <enclosure
                url="https://example.com/Maestro-1.2.0.dmg"
                sparkle:edSignature="SIG=="
                length="1234567" />
            </item>
          </channel>
        </rss>
        """
        let items = AppCastParser.parse(data: Data(xml.utf8))
        XCTAssertEqual(items.count, 1)
        let item = items[0]
        XCTAssertEqual(item.version, AppVersion(major: 1, minor: 2, patch: 0))
        XCTAssertEqual(item.downloadURL.absoluteString, "https://example.com/Maestro-1.2.0.dmg")
        XCTAssertEqual(item.releaseNotesURL?.absoluteString, "https://example.com/notes")
        XCTAssertEqual(item.edSignature, "SIG==")
        XCTAssertEqual(item.length, 1234567)
    }

    func testParsesMultipleItems() {
        let xml = """
        <rss xmlns:sparkle="x"><channel>
          <item><sparkle:version>1.0.0</sparkle:version>
            <enclosure url="https://example.com/a.dmg" sparkle:edSignature="A=="/>
          </item>
          <item><sparkle:version>0.9.0</sparkle:version>
            <enclosure url="https://example.com/b.dmg" sparkle:edSignature="B=="/>
          </item>
        </channel></rss>
        """
        let items = AppCastParser.parse(data: Data(xml.utf8))
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].version, AppVersion(major: 1, minor: 0, patch: 0))
        XCTAssertEqual(items[1].version, AppVersion(major: 0, minor: 9, patch: 0))
    }

    func testRejectsNonHTTPSEnclosure() {
        let xml = """
        <rss xmlns:sparkle="x"><channel>
          <item><sparkle:version>1.0.0</sparkle:version>
            <enclosure url="http://example.com/a.dmg" sparkle:edSignature="A=="/>
          </item>
        </channel></rss>
        """
        let items = AppCastParser.parse(data: Data(xml.utf8))
        XCTAssertTrue(items.isEmpty, "http enclosure 는 무시")
    }

    func testItemWithoutVersionIsSkipped() {
        let xml = """
        <rss xmlns:sparkle="x"><channel>
          <item><title>x</title>
            <enclosure url="https://example.com/x.dmg"/>
          </item>
        </channel></rss>
        """
        let items = AppCastParser.parse(data: Data(xml.utf8))
        XCTAssertTrue(items.isEmpty)
    }

    func testItemWithoutEnclosureIsSkipped() {
        let xml = """
        <rss xmlns:sparkle="x"><channel>
          <item><sparkle:version>1.0.0</sparkle:version></item>
        </channel></rss>
        """
        let items = AppCastParser.parse(data: Data(xml.utf8))
        XCTAssertTrue(items.isEmpty)
    }

    func testInvalidVersionStringSkipped() {
        let xml = """
        <rss xmlns:sparkle="x"><channel>
          <item><sparkle:version>garbage</sparkle:version>
            <enclosure url="https://example.com/x.dmg"/>
          </item>
        </channel></rss>
        """
        let items = AppCastParser.parse(data: Data(xml.utf8))
        XCTAssertTrue(items.isEmpty)
    }
}
