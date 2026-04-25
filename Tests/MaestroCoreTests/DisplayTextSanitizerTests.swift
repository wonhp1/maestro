@testable import MaestroCore
import XCTest

final class DisplayTextSanitizerTests: XCTestCase {
    func testStripsBidiOverrides() {
        let input = "innocent\u{202E}exe.fdp"
        let output = DisplayTextSanitizer.sanitize(input)
        XCTAssertFalse(output.unicodeScalars.contains(Unicode.Scalar(0x202E)!))
        XCTAssertEqual(output, "innocentexe.fdp")
    }

    func testStripsZeroWidthCharacters() {
        let input = "claude\u{200B}fake"
        XCTAssertEqual(DisplayTextSanitizer.sanitize(input), "claudefake")
    }

    func testReplacesControlCharsWithReplacementMarker() {
        let input = "alert\u{0007}sound"
        let output = DisplayTextSanitizer.sanitize(input)
        XCTAssertTrue(output.contains("\u{FFFD}"))
        XCTAssertFalse(output.contains("\u{0007}"))
    }

    func testKeepsNewlineAndTab() {
        let input = "line1\nline2\tindent"
        XCTAssertEqual(DisplayTextSanitizer.sanitize(input), input)
    }

    func testKeepsKoreanAndEmoji() {
        let input = "안녕하세요 🚀"
        XCTAssertEqual(DisplayTextSanitizer.sanitize(input), input)
    }

    func testNilPassesThrough() {
        XCTAssertNil(DisplayTextSanitizer.sanitize(nil))
    }
}
