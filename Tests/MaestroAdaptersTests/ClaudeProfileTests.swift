import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

final class ClaudeProfileTests: XCTestCase {
    func testStaticConstants() {
        XCTAssertEqual(ClaudeProfile.adapterID, "claude")
        XCTAssertEqual(ClaudeProfile.displayName, "Claude Code")
        XCTAssertEqual(ClaudeProfile.executableName, "claude")
    }

    func testProfileBuildsWithDefaults() throws {
        let profile = try ClaudeProfile.makeProfile()
        XCTAssertEqual(profile.adapterId.rawValue, "claude")
        XCTAssertEqual(profile.executable, "claude")
        XCTAssertEqual(profile.detectArgs, ["--version"])
        XCTAssertFalse(profile.versionRegex.isEmpty)
    }

    func testVersionRegexExtractsRealClaudeVersionString() {
        // 실제 Claude --version 출력 형식: `2.1.118 (Claude Code)`.
        let extracted = CLIDetector.extractVersion(
            from: "2.1.118 (Claude Code)",
            pattern: ClaudeProfile.versionRegex
        )
        XCTAssertEqual(extracted, "2.1.118")
    }

    func testCustomExecutableSupported() throws {
        // 사용자가 비표준 위치의 claude 사용 가능 (e.g., dev fork).
        let profile = try ClaudeProfile.makeProfile(executable: "claude-dev")
        XCTAssertEqual(profile.executable, "claude-dev")
        XCTAssertEqual(profile.adapterId.rawValue, "claude")
    }
}
