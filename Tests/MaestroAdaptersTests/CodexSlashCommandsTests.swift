import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

final class CodexSlashCommandsTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestSupport.makeTempDirectory(named: "codex-slash")
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempDir)
        super.tearDown()
    }

    func testBuiltInsContainsHelp() {
        let names = CodexSlashCommands.builtIns.map(\.name)
        XCTAssertTrue(names.contains("/help"))
        XCTAssertTrue(names.contains("/clear"))
        XCTAssertTrue(names.contains("/model"))
    }

    func testScanEmptyDirectoryReturnsEmpty() {
        let result = CodexSlashCommands.scan(directory: tempDir, category: "user")
        XCTAssertEqual(result, [])
    }

    func testScanReturnsSkillDirectories() throws {
        // skill 디렉토리 두 개 생성
        let skillA = tempDir.appending(path: "skill-a", directoryHint: .isDirectory)
        let skillB = tempDir.appending(path: "skill-b", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skillA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skillB, withIntermediateDirectories: true)

        let result = CodexSlashCommands.scan(directory: tempDir, category: "user")
        let names = result.map(\.name)
        XCTAssertTrue(names.contains("/skill-a"))
        XCTAssertTrue(names.contains("/skill-b"))
        XCTAssertTrue(result.allSatisfy { $0.category == "user" })
    }

    func testScanIgnoresFiles() throws {
        // 디렉토리만 — 파일 (e.g., README) 은 무시.
        let skillC = tempDir.appending(path: "skill-c", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skillC, withIntermediateDirectories: true)
        let readme = tempDir.appending(path: "README.md", directoryHint: .notDirectory)
        try Data("hi".utf8).write(to: readme)

        let names = CodexSlashCommands.scan(directory: tempDir, category: "user").map(\.name)
        XCTAssertEqual(names, ["/skill-c"])
    }

    func testScanExtractsDescriptionFromSkillMd() throws {
        let skill = tempDir.appending(path: "imagegen", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        let skillMd = skill.appending(path: "SKILL.md", directoryHint: .notDirectory)
        try Data("""
            ---
            name: imagegen
            description: Image generation skill for Codex
            ---
            # Imagegen
            """.utf8).write(to: skillMd)

        let result = CodexSlashCommands.scan(directory: tempDir, category: "system")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].description, "Image generation skill for Codex")
    }

    func testScanFallbackDescriptionWhenNoSkillMd() throws {
        let skill = tempDir.appending(path: "no-meta", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)

        let result = CodexSlashCommands.scan(directory: tempDir, category: "user")
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].description.isEmpty, "fallback description 적용")
    }

    func testScanResultsAreSortedAlphabetically() throws {
        for name in ["zebra", "alpha", "mango"] {
            let dir = tempDir.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let names = CodexSlashCommands.scan(directory: tempDir, category: "user").map(\.name)
        XCTAssertEqual(names, ["/alpha", "/mango", "/zebra"])
    }
}
