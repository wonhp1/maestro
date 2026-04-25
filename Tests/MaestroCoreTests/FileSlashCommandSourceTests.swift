@testable import MaestroCore
import XCTest

final class FileSlashCommandSourceTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "FileSlashCommandSourceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func write(_ name: String, _ content: String) throws {
        let url = tempRoot.appending(path: name, directoryHint: .notDirectory)
        try content.data(using: .utf8)!.write(to: url)
    }

    func testEmptyDirectoryYieldsEmpty() async {
        let source = FileSlashCommandSource(directory: tempRoot)
        let discovered = await source.discover()
        XCTAssertTrue(discovered.isEmpty)
    }

    func testNonexistentDirectoryYieldsEmpty() async {
        let missing = tempRoot.appending(path: "missing", directoryHint: .isDirectory)
        let source = FileSlashCommandSource(directory: missing)
        let discovered = await source.discover()
        XCTAssertTrue(discovered.isEmpty)
    }

    func testParsesFrontmatterDescriptionAndArgumentHint() async throws {
        try write("compact.md", """
        ---
        description: Compact context
        argument-hint: [topic]
        ---
        body
        """)
        let source = FileSlashCommandSource(directory: tempRoot)
        let discovered = await source.discover()
        XCTAssertEqual(discovered.count, 1)
        let cmd = discovered[0]
        XCTAssertEqual(cmd.command.name, "compact")
        XCTAssertEqual(cmd.command.description, "Compact context")
        XCTAssertEqual(cmd.command.arguments, ["[topic]"])
        XCTAssertEqual(cmd.source, .userFile)
    }

    func testFallsBackToFirstNonEmptyBodyLineWhenNoFrontmatter() async throws {
        try write("greet.md", """

        First content line
        Second
        """)
        let source = FileSlashCommandSource(directory: tempRoot)
        let discovered = await source.discover()
        XCTAssertEqual(discovered.first?.command.description, "First content line")
    }

    func testRejectsInvalidNamesAndHiddenFiles() async throws {
        try write("ok-name.md", "ok")
        try write("..bad.md", "bad")           // path traversal
        try write("with space.md", "bad")     // not allowed char
        try write(".hidden.md", "bad")        // skipsHiddenFiles
        let source = FileSlashCommandSource(directory: tempRoot)
        let discovered = await source.discover()
        XCTAssertEqual(discovered.map(\.command.name), ["ok-name"])
    }

    func testIgnoresNonMarkdownExtensions() async throws {
        try write("a.md", "ok")
        try write("b.txt", "ignored")
        let source = FileSlashCommandSource(directory: tempRoot)
        let discovered = await source.discover()
        XCTAssertEqual(discovered.map(\.command.name), ["a"])
    }

    func testRespectsMaxFileBytesCap() async throws {
        try write("small.md", "ok")
        let huge = String(repeating: "x", count: 2 * 1024 * 1024)
        try write("huge.md", huge)
        let source = FileSlashCommandSource(directory: tempRoot, maxFileBytes: 1024)
        let discovered = await source.discover()
        XCTAssertEqual(discovered.map(\.command.name), ["small"])
    }

    func testIDEncodesSourceAndName() async throws {
        try write("alpha.md", "x")
        let source = FileSlashCommandSource(directory: tempRoot, kind: .userFile)
        let discovered = await source.discover()
        XCTAssertEqual(discovered.first?.id, "userFile:alpha")
    }
}
