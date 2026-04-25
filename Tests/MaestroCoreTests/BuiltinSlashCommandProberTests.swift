@testable import MaestroCore
import XCTest

final class BuiltinSlashCommandProberTests: XCTestCase {
    private var tempRoot: URL!
    private var cacheFile: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "BuiltinProberTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        cacheFile = tempRoot.appending(path: "cache.json", directoryHint: .notDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // MARK: parseHelpOutput

    func testParsesDashSeparatedFormat() {
        let output = """
        Available commands:
        /help - Show help
        /clear - Clear conversation
        """
        let cmds = BuiltinSlashCommandProber.parseHelpOutput(output)
        XCTAssertEqual(cmds.count, 2)
        XCTAssertEqual(cmds[0].name, "help")
        XCTAssertEqual(cmds[0].description, "Show help")
        XCTAssertEqual(cmds[1].name, "clear")
    }

    func testParsesWhitespaceSeparatedFormat() {
        let output = """
        /compact   compress the conversation
        """
        let cmds = BuiltinSlashCommandProber.parseHelpOutput(output)
        XCTAssertEqual(cmds.first?.name, "compact")
        XCTAssertEqual(cmds.first?.description, "compress the conversation")
    }

    func testParsesStandaloneCommandLine() {
        let cmds = BuiltinSlashCommandProber.parseHelpOutput("/foo")
        XCTAssertEqual(cmds.first?.name, "foo")
        XCTAssertEqual(cmds.first?.description, "")
    }

    func testIgnoresNonSlashLines() {
        let output = """
        Header
        Some text
        /valid - desc
        not a command
        """
        let cmds = BuiltinSlashCommandProber.parseHelpOutput(output)
        XCTAssertEqual(cmds.map(\.name), ["valid"])
    }

    func testRejectsInvalidCommandNames() {
        let output = """
        /good - ok
        /bad name - has space
        /../traversal - bad
        /also/bad - bad
        """
        let cmds = BuiltinSlashCommandProber.parseHelpOutput(output)
        XCTAssertEqual(cmds.map(\.name), ["good"])
    }

    func testDuplicatesDeduped() {
        let output = """
        /help - one
        /help - two
        """
        let cmds = BuiltinSlashCommandProber.parseHelpOutput(output)
        XCTAssertEqual(cmds.count, 1)
    }

    // MARK: cache + ttl

    func testFreshProbeWritesCacheAndReturnsCommands() async throws {
        let exe = try makeFakeExecutable()
        let executor = StubExecutor(stdout: "/help - text\n", exitCode: 0)
        let prober = BuiltinSlashCommandProber(
            claudeExecutable: exe,
            cacheFile: cacheFile,
            ttl: 100,
            executor: executor
        )
        let discovered = await prober.discover()
        XCTAssertEqual(discovered.map(\.command.name), ["help"])
        let calls = await executor.callCount
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))
    }

    func testWithinTTLDoesNotReprobe() async throws {
        let exe = try makeFakeExecutable()
        let executor = StubExecutor(stdout: "/help - first\n", exitCode: 0)
        let prober = BuiltinSlashCommandProber(
            claudeExecutable: exe,
            cacheFile: cacheFile,
            ttl: 1000,
            executor: executor
        )
        _ = await prober.discover()
        _ = await prober.discover()
        _ = await prober.discover()
        let calls = await executor.callCount
        XCTAssertEqual(calls, 1)
    }

    func testExpiredCacheReprobes() async throws {
        let exe = try makeFakeExecutable()
        let executor = StubExecutor(stdout: "/help - x\n", exitCode: 0)
        let prober = BuiltinSlashCommandProber(
            claudeExecutable: exe,
            cacheFile: cacheFile,
            ttl: 0,
            executor: executor
        )
        _ = await prober.discover()
        _ = await prober.discover()
        let calls = await executor.callCount
        XCTAssertGreaterThan(calls, 1)
    }

    func testBinaryPathChangeInvalidatesCache() async throws {
        let exe1 = try makeFakeExecutable(name: "claude-a")
        let exe2 = try makeFakeExecutable(name: "claude-b")
        let executor1 = StubExecutor(stdout: "/help - a\n", exitCode: 0)
        let prober1 = BuiltinSlashCommandProber(
            claudeExecutable: exe1, cacheFile: cacheFile, ttl: 1000, executor: executor1
        )
        _ = await prober1.discover()

        let executor2 = StubExecutor(stdout: "/help - b\n", exitCode: 0)
        let prober2 = BuiltinSlashCommandProber(
            claudeExecutable: exe2, cacheFile: cacheFile, ttl: 1000, executor: executor2
        )
        let discovered2 = await prober2.discover()
        let calls2 = await executor2.callCount
        XCTAssertEqual(calls2, 1, "different binary path → reprobe")
        XCTAssertEqual(discovered2.map(\.command.description), ["b"])
    }

    func testNoExecutableYieldsEmpty() async {
        let prober = BuiltinSlashCommandProber(
            claudeExecutable: nil, cacheFile: cacheFile, executor: StubExecutor()
        )
        let discovered = await prober.discover()
        XCTAssertTrue(discovered.isEmpty)
    }

    func testNonZeroExitYieldsEmpty() async throws {
        let exe = try makeFakeExecutable()
        let executor = StubExecutor(stdout: "", exitCode: 1)
        let prober = BuiltinSlashCommandProber(
            claudeExecutable: exe, cacheFile: cacheFile, executor: executor
        )
        let discovered = await prober.discover()
        XCTAssertTrue(discovered.isEmpty)
    }

    func testInvalidateClearsCache() async throws {
        let exe = try makeFakeExecutable()
        let executor = StubExecutor(stdout: "/help - hi\n", exitCode: 0)
        let prober = BuiltinSlashCommandProber(
            claudeExecutable: exe, cacheFile: cacheFile, ttl: 1000, executor: executor
        )
        _ = await prober.discover()
        await prober.invalidate()
        _ = await prober.discover()
        let calls = await executor.callCount
        XCTAssertEqual(calls, 2)
    }

    // MARK: helpers

    private func makeFakeExecutable(name: String = "claude") throws -> URL {
        let url = tempRoot.appending(path: name, directoryHint: .notDirectory)
        try Data().write(to: url)
        return url
    }
}

private actor StubExecutor: ProcessExecuting {
    var callCount: Int = 0
    let stdout: String
    let stderr: String
    let exitCode: Int32

    init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }

    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        callCount += 1
        return ProcessOutput(stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
}
