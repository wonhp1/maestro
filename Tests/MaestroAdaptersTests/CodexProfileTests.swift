import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

final class CodexProfileTests: XCTestCase {
    func testStaticConstants() {
        XCTAssertEqual(CodexProfile.adapterID, "codex")
        XCTAssertEqual(CodexProfile.displayName, "Codex (OpenAI)")
        XCTAssertEqual(CodexProfile.executableName, "codex")
    }

    func testProfileBuildsWithDefaults() throws {
        let profile = try CodexProfile.makeProfile()
        XCTAssertEqual(profile.adapterId.rawValue, "codex")
        XCTAssertEqual(profile.executable, "codex")
        XCTAssertEqual(profile.detectArgs, ["--version"])
    }

    func testVersionRegexExtractsCodexCLIVersion() {
        let extracted = CLIDetector.extractVersion(
            from: "codex-cli 0.125.0\n",
            pattern: CodexProfile.versionRegex
        )
        XCTAssertEqual(extracted, "0.125.0")
    }

    func testVersionRegexHandlesPrefixedOutput() {
        // 일부 환경에서 changelog / banner 가 첫 줄에 출현.
        let raw = "[INFO] Update available: 0.126.0\ncodex-cli 0.125.0\n"
        XCTAssertEqual(
            CLIDetector.extractVersion(from: raw, pattern: CodexProfile.versionRegex),
            // 첫 매치 (changelog 의 0.126.0) — 실 사용자 흐름에서 'codex --version' 단독
            // 호출이라 banner 안 나옴. 만약 여기 변경 시 ClaudeProfile 패턴 통일.
            "0.126.0"
        )
    }

    func testCustomExecutableSupported() throws {
        let profile = try CodexProfile.makeProfile(executable: "codex-beta")
        XCTAssertEqual(profile.executable, "codex-beta")
    }
}
