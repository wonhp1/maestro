import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

final class GeminiProfileTests: XCTestCase {
    func testStaticConstants() {
        XCTAssertEqual(GeminiProfile.adapterID, "gemini")
        XCTAssertEqual(GeminiProfile.displayName, "Gemini (Google)")
        XCTAssertEqual(GeminiProfile.executableName, "gemini")
    }

    func testProfileBuildsWithDefaults() throws {
        let profile = try GeminiProfile.makeProfile()
        XCTAssertEqual(profile.adapterId.rawValue, "gemini")
        XCTAssertEqual(profile.executable, "gemini")
        XCTAssertEqual(profile.detectArgs, ["--version"])
    }

    func testVersionRegexExtractsRealVersion() {
        let extracted = CLIDetector.extractVersion(
            from: "0.40.0\n",
            pattern: GeminiProfile.versionRegex
        )
        XCTAssertEqual(extracted, "0.40.0")
    }

    func testCustomExecutable() throws {
        let profile = try GeminiProfile.makeProfile(executable: "gemini-beta")
        XCTAssertEqual(profile.executable, "gemini-beta")
    }
}
