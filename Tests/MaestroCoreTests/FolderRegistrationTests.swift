import Foundation
@testable import MaestroCore
import XCTest

final class FolderRegistrationTests: XCTestCase {
    // MARK: - validateDisplayName

    func testValidatesNonEmptyTrimmedName() throws {
        XCTAssertNoThrow(try FolderRegistration.validateDisplayName("My Project"))
        XCTAssertNoThrow(try FolderRegistration.validateDisplayName("  trimmed  "))
    }

    func testRejectsEmptyName() {
        XCTAssertThrowsError(try FolderRegistration.validateDisplayName("")) { error in
            XCTAssertEqual(error as? FolderRegistrationError, .emptyDisplayName)
        }
        XCTAssertThrowsError(try FolderRegistration.validateDisplayName("   ")) { error in
            XCTAssertEqual(error as? FolderRegistrationError, .emptyDisplayName)
        }
    }

    func testRejectsTooLongName() {
        let huge = String(repeating: "A", count: 200)
        XCTAssertThrowsError(try FolderRegistration.validateDisplayName(huge)) { error in
            XCTAssertEqual(error as? FolderRegistrationError, .displayNameTooLong(length: 200))
        }
    }

    func testRejectsControlCharacters() {
        XCTAssertThrowsError(
            try FolderRegistration.validateDisplayName("evil\u{0007}name")
        ) { error in
            XCTAssertEqual(
                error as? FolderRegistrationError,
                .displayNameContainsControlCharacter
            )
        }
    }

    // MARK: - validatePath

    func testValidatesExistingDirectory() throws {
        let tmp = try TestSupport.makeTempDirectory()
        defer { TestSupport.removeTempDirectory(tmp) }
        XCTAssertNoThrow(try FolderRegistration.validatePath(tmp))
    }

    func testRejectsNonFileURL() {
        let url = URL(string: "https://example.com")!
        XCTAssertThrowsError(try FolderRegistration.validatePath(url)) { error in
            XCTAssertEqual(error as? FolderRegistrationError, .pathMustBeFileURL)
        }
    }

    func testRejectsNonexistentPath() throws {
        let tmp = try TestSupport.makeTempDirectory()
        defer { TestSupport.removeTempDirectory(tmp) }
        let missing = tmp.appending(path: "does-not-exist")
        XCTAssertThrowsError(try FolderRegistration.validatePath(missing)) { error in
            guard case .pathIsNotADirectory = error as? FolderRegistrationError else {
                XCTFail("expected pathIsNotADirectory, got \(error)")
                return
            }
        }
    }

    func testRejectsFilePath() throws {
        let tmp = try TestSupport.makeTempDirectory()
        defer { TestSupport.removeTempDirectory(tmp) }
        let file = tmp.appending(path: "f.txt")
        try Data().write(to: file)
        XCTAssertThrowsError(try FolderRegistration.validatePath(file)) { error in
            guard case .pathIsNotADirectory = error as? FolderRegistrationError else {
                XCTFail("expected pathIsNotADirectory, got \(error)")
                return
            }
        }
    }

    // MARK: - Symlink resolution (Phase 10 security must-fix)

    func testValidatePathReturnsResolvedPathForRegularDirectory() throws {
        let tmp = try TestSupport.makeTempDirectory()
        defer { TestSupport.removeTempDirectory(tmp) }
        let resolved = try FolderRegistration.validatePath(tmp)
        XCTAssertEqual(resolved.path, tmp.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    func testValidatePathFollowsSymlinkToDirectory() throws {
        let tmp = try TestSupport.makeTempDirectory()
        defer { TestSupport.removeTempDirectory(tmp) }
        let real = tmp.appending(path: "real-dir")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = tmp.appending(path: "link-dir")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let resolved = try FolderRegistration.validatePath(link)
        // Symlink 가 실제 디렉토리로 해소되어야 함 (Aider --yes-always 와 결합한 RCE 방어)
        XCTAssertNotEqual(resolved.path, link.standardizedFileURL.path)
        XCTAssertEqual(
            resolved.path,
            real.standardizedFileURL.resolvingSymlinksInPath().path
        )
    }

    func testValidatePathRejectsSymlinkToFile() throws {
        let tmp = try TestSupport.makeTempDirectory()
        defer { TestSupport.removeTempDirectory(tmp) }
        let file = tmp.appending(path: "file.txt")
        try Data("hi".utf8).write(to: file)
        let link = tmp.appending(path: "link-file")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        XCTAssertThrowsError(try FolderRegistration.validatePath(link)) { error in
            guard case .pathIsNotADirectory = error as? FolderRegistrationError else {
                XCTFail("expected pathIsNotADirectory, got \(error)")
                return
            }
        }
    }

    func testValidatePathRejectsBrokenSymlink() throws {
        let tmp = try TestSupport.makeTempDirectory()
        defer { TestSupport.removeTempDirectory(tmp) }
        let missing = tmp.appending(path: "nope")
        let link = tmp.appending(path: "broken-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: missing)

        XCTAssertThrowsError(try FolderRegistration.validatePath(link)) { error in
            guard case .pathIsNotADirectory = error as? FolderRegistrationError else {
                XCTFail("expected pathIsNotADirectory, got \(error)")
                return
            }
        }
    }

    // MARK: - Bidi / zero-width spoofing (Phase 10 security must-fix)

    func testRejectsBidiOverrideInDisplayName() {
        // "user\u{202E}fdp.exe" — RTL override → 시각적으로 "exe.pdf" 처럼 보임
        let spoofed = "innocent\u{202E}exe.fdp"
        XCTAssertThrowsError(try FolderRegistration.validateDisplayName(spoofed)) { error in
            XCTAssertEqual(
                error as? FolderRegistrationError,
                .displayNameContainsControlCharacter
            )
        }
    }

    func testRejectsZeroWidthSpaceInDisplayName() {
        let spoofed = "claude\u{200B}fake"
        XCTAssertThrowsError(try FolderRegistration.validateDisplayName(spoofed)) { error in
            XCTAssertEqual(
                error as? FolderRegistrationError,
                .displayNameContainsControlCharacter
            )
        }
    }

    func testRejectsAllBidiAndZeroWidthVariants() {
        let dangerousChars = [
            "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
            "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
            "\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}",
        ]
        for char in dangerousChars {
            XCTAssertThrowsError(
                try FolderRegistration.validateDisplayName("a\(char)b"),
                "should reject \(char.unicodeScalars.first?.value ?? 0)"
            )
        }
    }

    func testAcceptsKoreanAndEmojiInDisplayName() throws {
        // 한글 / 이모지는 spoofing 아님 — 정상 허용.
        XCTAssertNoThrow(try FolderRegistration.validateDisplayName("내 프로젝트 🚀"))
    }

    // MARK: - Codable round-trip

    func testCodableRoundTripPreservesAllFields() throws {
        let now = Date()
        let original = FolderRegistration(
            id: FolderID(rawValue: "abc-123"),
            displayName: "test",
            path: URL(filePath: "/tmp/x"),
            adapterId: AdapterID(rawValue: "claude"),
            createdAt: now,
            lastUsedAt: now
        )
        let data = try JSONEncoder.maestro.encode(original)
        let decoded = try JSONDecoder.maestro.decode(FolderRegistration.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.displayName, original.displayName)
        XCTAssertEqual(decoded.path.path, original.path.path)
        XCTAssertEqual(decoded.adapterId, original.adapterId)
    }
}
