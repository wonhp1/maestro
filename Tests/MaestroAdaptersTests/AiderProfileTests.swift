import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

final class AiderProfileTests: XCTestCase {
    func testStaticConstants() {
        XCTAssertEqual(AiderProfile.adapterID, "aider")
        XCTAssertEqual(AiderProfile.displayName, "Aider")
        XCTAssertEqual(AiderProfile.executableName, "aider")
    }

    func testProfileBuildsWithDefaults() throws {
        let profile = try AiderProfile.makeProfile()
        XCTAssertEqual(profile.adapterId.rawValue, "aider")
        XCTAssertEqual(profile.executable, "aider")
        XCTAssertEqual(profile.detectArgs, ["--version"])
    }

    func testVersionRegexExtractsRealAiderVersionString() {
        let extracted = CLIDetector.extractVersion(
            from: "aider 0.74.2\n",
            pattern: AiderProfile.versionRegex
        )
        XCTAssertEqual(extracted, "0.74.2")
    }

    func testVersionRegexHandlesMultiLineOutput() {
        // 일부 환경에서 aider 가 multi-line 헤더 출력.
        let raw = "Update available: 0.75.0\naider 0.74.2\n"
        XCTAssertEqual(
            CLIDetector.extractVersion(from: raw, pattern: AiderProfile.versionRegex),
            "0.74.2"
        )
    }

    func testCustomExecutableSupported() throws {
        let profile = try AiderProfile.makeProfile(executable: "aider-dev")
        XCTAssertEqual(profile.executable, "aider-dev")
    }
}
