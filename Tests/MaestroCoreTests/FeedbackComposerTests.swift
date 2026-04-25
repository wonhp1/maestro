@testable import MaestroCore
import XCTest

final class FeedbackComposerTests: XCTestCase {
    func testComposeIncludesSystemInfo() {
        let payload = FeedbackComposer.compose(
            userNote: "hello",
            detectedCLIs: ["claude", "aider"]
        )
        XCTAssertEqual(payload.userNote, "hello")
        XCTAssertEqual(payload.detectedCLIs, ["claude", "aider"])
        XCTAssertEqual(payload.appName, MaestroConfig.appName)
        XCTAssertEqual(payload.bundleIdentifier, MaestroConfig.bundleIdentifier)
        XCTAssertFalse(payload.macOSVersionString.isEmpty)
    }

    func testRenderMarkdownIncludesAllSections() {
        let payload = FeedbackPayload(
            appName: "Maestro",
            appVersion: "0.1.0",
            bundleIdentifier: "com.example.maestro",
            macOSVersionString: "14.0.0",
            detectedCLIs: ["claude"],
            userNote: "I love it",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let md = payload.renderMarkdown()
        XCTAssertTrue(md.contains("Maestro 0.1.0"))
        XCTAssertTrue(md.contains("com.example.maestro"))
        XCTAssertTrue(md.contains("14.0.0"))
        XCTAssertTrue(md.contains("claude"))
        XCTAssertTrue(md.contains("I love it"))
    }

    func testEmptyUserNoteRendersPlaceholder() {
        let payload = FeedbackPayload(
            appName: "M", appVersion: "1.0",
            bundleIdentifier: "x", macOSVersionString: "14.0",
            detectedCLIs: [], userNote: ""
        )
        XCTAssertTrue(payload.renderMarkdown().contains("_(empty)_"))
    }

    func testEmptyDetectedCLIsRendersNonePlaceholder() {
        let payload = FeedbackPayload(
            appName: "M", appVersion: "1.0",
            bundleIdentifier: "x", macOSVersionString: "14.0",
            detectedCLIs: [], userNote: "x"
        )
        XCTAssertTrue(payload.renderMarkdown().contains("(none)"))
    }

    func testUserNoteIsSanitized() {
        // bidi 컨트롤 문자 (U+202E) 가 markdown 에 그대로 들어가면 안 됨
        let payload = FeedbackPayload(
            appName: "M", appVersion: "1.0",
            bundleIdentifier: "x", macOSVersionString: "14.0",
            detectedCLIs: [], userNote: "before\u{202E}after"
        )
        XCTAssertFalse(payload.renderMarkdown().contains("\u{202E}"))
    }
}
