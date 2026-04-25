import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

final class ClaudeSlashCommandsTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestSupport.makeTempDirectory(named: "claude-cmds")
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempDir)
        super.tearDown()
    }

    func testBuiltInsIncludeCoreCommands() {
        let names = Set(ClaudeSlashCommands.builtIns.map(\.name))
        XCTAssertTrue(names.contains("clear"))
        XCTAssertTrue(names.contains("compact"))
        XCTAssertTrue(names.contains("review"))
        XCTAssertGreaterThanOrEqual(ClaudeSlashCommands.builtIns.count, 5)
        // 모든 built-in 은 category="built-in"
        for cmd in ClaudeSlashCommands.builtIns {
            XCTAssertEqual(cmd.category, "built-in")
        }
    }

    func testScanReturnsEmptyForMissingDirectory() {
        let missing = tempDir.appending(path: "no-such-dir")
        XCTAssertEqual(ClaudeSlashCommands.scan(directory: missing, category: "user"), [])
    }

    func testScanFiltersToMarkdownOnly() throws {
        try "x".write(to: tempDir.appending(path: "alpha.md"), atomically: true, encoding: .utf8)
        try "x".write(to: tempDir.appending(path: "beta.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: tempDir.appending(path: "gamma.json"), atomically: true, encoding: .utf8)
        let cmds = ClaudeSlashCommands.scan(directory: tempDir, category: "user")
        XCTAssertEqual(cmds.map(\.name), ["alpha"])
    }

    func testScanReadsFirstMeaningfulLineAsDescription() throws {
        try "Run a code review".write(
            to: tempDir.appending(path: "review.md"),
            atomically: true, encoding: .utf8
        )
        let cmds = ClaudeSlashCommands.scan(directory: tempDir, category: "user")
        XCTAssertEqual(cmds.first?.name, "review")
        XCTAssertEqual(cmds.first?.description, "Run a code review")
        XCTAssertEqual(cmds.first?.category, "user")
    }

    func testScanSkipsFrontmatterAndUsesFollowingLine() throws {
        let content = """
        ---
        argument: prompt
        ---

        # Code Review

        details below
        """
        try content.write(
            to: tempDir.appending(path: "review.md"),
            atomically: true, encoding: .utf8
        )
        let cmds = ClaudeSlashCommands.scan(directory: tempDir, category: "user")
        XCTAssertEqual(cmds.first?.description, "Code Review")
    }

    func testScanResultsAreSorted() throws {
        for name in ["zebra.md", "alpha.md", "mango.md"] {
            try "x".write(to: tempDir.appending(path: name), atomically: true, encoding: .utf8)
        }
        let cmds = ClaudeSlashCommands.scan(directory: tempDir, category: "user")
        XCTAssertEqual(cmds.map(\.name), ["alpha", "mango", "zebra"])
    }

    func testEmptyFileGivesFallbackDescription() throws {
        try "".write(to: tempDir.appending(path: "empty.md"), atomically: true, encoding: .utf8)
        let cmds = ClaudeSlashCommands.scan(directory: tempDir, category: "user")
        XCTAssertEqual(cmds.first?.description, "User command")
    }

    /// Phase 7 sec must-fix: 심볼릭 링크는 거부 — 임의 파일 노출 차단.
    func testSymbolicLinksAreSkipped() throws {
        // 실제 파일.
        let real = tempDir.appending(path: "real.md")
        try "real command".write(to: real, atomically: true, encoding: .utf8)
        // symlink 생성 → /etc/hosts (어디든) — symlink 자체가 .md 확장자라도 거부.
        let link = tempDir.appending(path: "link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        let cmds = ClaudeSlashCommands.scan(directory: tempDir, category: "user")
        XCTAssertEqual(cmds.map(\.name), ["real"], "symlink 이 포함됨: \(cmds.map(\.name))")
    }

    /// Phase 7 perf must-fix: 큰 파일도 16 KiB 만 읽음 — OOM/지연 방어.
    func testLargeFileFirstLineCappedReadDoesNotHang() throws {
        // 100 KiB 채워진 파일.
        let bigContent = "first line of big file\n" + String(repeating: "x", count: 100 * 1024)
        try bigContent.write(to: tempDir.appending(path: "big.md"), atomically: true, encoding: .utf8)
        let cmds = ClaudeSlashCommands.scan(directory: tempDir, category: "user")
        XCTAssertEqual(cmds.first?.description, "first line of big file")
    }
}
