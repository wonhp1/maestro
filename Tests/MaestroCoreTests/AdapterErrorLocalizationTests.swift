@testable import MaestroCore
import XCTest

final class AdapterErrorLocalizationTests: XCTestCase {
    func testNotInstalledClaudeIncludesNpmInstallCommand() {
        let error = AdapterError.notInstalled(adapterId: "claude")
        let message = error.errorDescription ?? ""
        XCTAssertTrue(message.contains("Claude Code"))
        XCTAssertTrue(message.contains("npm install"))
        XCTAssertTrue(message.contains("@anthropic-ai/claude-code"))
    }

    func testNotInstalledAiderIncludesPipInstallCommand() {
        let error = AdapterError.notInstalled(adapterId: "aider")
        let message = error.errorDescription ?? ""
        XCTAssertTrue(message.contains("Aider"))
        XCTAssertTrue(message.contains("pip install"))
        XCTAssertTrue(message.contains("aider-chat"))
    }

    func testNotInstalledUnknownAdapterFallsBackGracefully() {
        let error = AdapterError.notInstalled(adapterId: "future-vendor")
        let message = error.errorDescription ?? ""
        XCTAssertTrue(message.contains("future-vendor"))
        XCTAssertFalse(message.isEmpty)
    }

    func testProcessFailedIncludesExitCodeAndStderr() {
        let error = AdapterError.processFailed(exitCode: 42, stderr: "oops\n")
        let message = error.errorDescription ?? ""
        XCTAssertTrue(message.contains("42"))
        XCTAssertTrue(message.contains("oops"))
    }

    func testNoneOfTheMessagesFallsBackToErrorEnum() {
        // 모든 case 가 명시적 메시지 — `AdapterError error 0` 같은 raw 표현 절대 안 나옴.
        let cases: [AdapterError] = [
            .notInstalled(adapterId: "x"),
            .sessionCreationFailed(reason: "y"),
            .unknownSession(id: SessionID.new()),
            .processFailed(exitCode: 1, stderr: ""),
            .unsupported(operation: "op"),
        ]
        for error in cases {
            let message = error.errorDescription ?? ""
            XCTAssertFalse(message.isEmpty, "\(error) 의 메시지가 비었음")
            XCTAssertFalse(
                message.contains("AdapterError error"),
                "raw enum 표현 새어나옴: \(message)"
            )
        }
    }
}
