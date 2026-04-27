@testable import MaestroCore
import XCTest

final class EnvironmentCheckerTests: XCTestCase {
    // MARK: - StubLocator + StubExecutor

    private struct StubLocator: ExecutableLocating {
        let mapping: [String: URL?]
        func locate(_ executableName: String) -> URL? {
            mapping[executableName, default: nil]
        }
    }

    private final class StubExecutor: ProcessExecuting, @unchecked Sendable {
        var responses: [String: ProcessOutput] = [:]  // key: executable lastPath
        func run(
            executable: URL,
            arguments: [String],
            currentDirectoryURL: URL?,
            environment: [String: String]?
        ) async throws -> ProcessOutput {
            if let r = responses[executable.lastPathComponent] { return r }
            return ProcessOutput(stdout: "", stderr: "", exitCode: 1)
        }
    }

    // MARK: - Node check

    func testCheckNodeMissingReturnsNotInstalled() async {
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),
            executor: StubExecutor()
        )
        let result = await checker.checkNode()
        XCTAssertEqual(result, ToolStatus.notInstalled)
    }

    func testCheckNodeInstalledExtractsVersion() async {
        let executor = StubExecutor()
        executor.responses["node"] = ProcessOutput(
            stdout: "v22.11.0\n", stderr: "", exitCode: 0
        )
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: ["node": URL(filePath: "/usr/local/bin/node")]),
            executor: executor
        )
        let result = await checker.checkNode()
        XCTAssertEqual(result, .installed(version: "v22.11.0"))
    }

    func testCheckNodeOutdatedReturnsOutdated() async {
        let executor = StubExecutor()
        executor.responses["node"] = ProcessOutput(
            stdout: "v14.21.3\n", stderr: "", exitCode: 0
        )
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: ["node": URL(filePath: "/usr/local/bin/node")]),
            executor: executor
        )
        let result = await checker.checkNode()
        XCTAssertEqual(result, .outdated(current: "v14.21.3", required: "v18"))
    }

    // MARK: - Claude check

    func testCheckClaudeMissing() async {
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),
            executor: StubExecutor()
        )
        let r = await checker.checkClaude()
        XCTAssertEqual(r, .notInstalled)
    }

    func testCheckClaudeInstalled() async {
        let executor = StubExecutor()
        executor.responses["claude"] = ProcessOutput(
            stdout: "1.2.3 (Claude Code)\n", stderr: "", exitCode: 0
        )
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: ["claude": URL(filePath: "/usr/local/bin/claude")]),
            executor: executor
        )
        let r = await checker.checkClaude()
        XCTAssertEqual(r, .installed(version: "1.2.3"))
    }

    // MARK: - Git check (있음/없음만)

    func testCheckGitInstalled() async {
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: ["git": URL(filePath: "/usr/bin/git")]),
            executor: StubExecutor()
        )
        let r = await checker.checkGit()
        XCTAssertEqual(r, .installed(version: nil))
    }

    func testCheckGitMissing() async {
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),
            executor: StubExecutor()
        )
        let r = await checker.checkGit()
        XCTAssertEqual(r, .notInstalled)
    }

    // MARK: - Python check

    func testCheckPython3Outdated() async {
        let executor = StubExecutor()
        executor.responses["python3"] = ProcessOutput(
            stdout: "Python 3.8.10\n", stderr: "", exitCode: 0
        )
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [
                "python3": URL(filePath: "/usr/bin/python3"),
            ]),
            executor: executor
        )
        let r = await checker.checkPython3()
        XCTAssertEqual(r, .outdated(current: "3.8.10", required: "3.10"))
    }

    // MARK: - claudeAuth check

    func testCheckClaudeAuthMissingFile() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "maestro-env-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),
            executor: StubExecutor(),
            homeDirectory: tempDir
        )
        let r = await checker.checkClaudeAuth()
        XCTAssertEqual(r, .notInstalled)
    }

    func testCheckClaudeAuthExistingFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "maestro-env-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let claudeDir = tempDir.appending(path: ".claude", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let credFile = claudeDir.appending(path: "credentials.json", directoryHint: .notDirectory)
        try Data("{\"token\":\"abc\"}".utf8).write(to: credFile)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),
            executor: StubExecutor(),
            homeDirectory: tempDir
        )
        let r = await checker.checkClaudeAuth()
        XCTAssertEqual(r, .installed(version: nil))
    }

    func testCheckClaudeAuthEmptyFileTreatedAsMissing() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "maestro-env-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let claudeDir = tempDir.appending(path: ".claude", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let credFile = claudeDir.appending(path: "credentials.json", directoryHint: .notDirectory)
        try Data().write(to: credFile)  // empty
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),
            executor: StubExecutor(),
            homeDirectory: tempDir
        )
        let r = await checker.checkClaudeAuth()
        XCTAssertEqual(r, .notInstalled)
    }

    // MARK: - checkAll integration

    func testCheckAllAggregatesAllTools() async {
        let executor = StubExecutor()
        executor.responses["node"] = ProcessOutput(
            stdout: "v22.0.0\n", stderr: "", exitCode: 0
        )
        executor.responses["claude"] = ProcessOutput(
            stdout: "1.0.0\n", stderr: "", exitCode: 0
        )
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [
                "node": URL(filePath: "/usr/local/bin/node"),
                "claude": URL(filePath: "/usr/local/bin/claude"),
                "git": URL(filePath: "/usr/bin/git"),
            ]),
            executor: executor
        )
        let result = await checker.checkAll()
        XCTAssertEqual(result.node, .installed(version: "v22.0.0"))
        XCTAssertEqual(result.claude, .installed(version: "1.0.0"))
        XCTAssertEqual(result.git, .installed(version: nil))
        XCTAssertEqual(result.python3, .notInstalled)  // no executor mapping
    }

    // MARK: - EnvironmentStatus convenience

    func testClaudeReadyRequiresAllThree() {
        let allReady = EnvironmentStatus(
            node: .installed(version: "v22"),
            claude: .installed(version: "1"),
            git: .notInstalled,
            python3: .notInstalled,
            aider: .notInstalled,
            claudeAuth: .installed(version: nil)
        )
        XCTAssertTrue(allReady.claudeReady)
        XCTAssertFalse(allReady.aiderReady)

        let missingAuth = EnvironmentStatus(
            node: .installed(version: "v22"),
            claude: .installed(version: "1"),
            git: .notInstalled,
            python3: .notInstalled,
            aider: .notInstalled,
            claudeAuth: .notInstalled
        )
        XCTAssertFalse(missingAuth.claudeReady)
    }

    func testToolStatusFlags() {
        XCTAssertTrue(ToolStatus.installed(version: nil).isReady)
        XCTAssertFalse(ToolStatus.notInstalled.isReady)
        XCTAssertFalse(ToolStatus.outdated(current: "v14", required: "v18").isReady)
    }

    // MARK: - claudeAuth corrupt JSON

    func testCheckClaudeAuthCorruptJSONTreatedAsMissing() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "maestro-env-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let claudeDir = tempDir.appending(path: ".claude", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let credFile = claudeDir.appending(path: "credentials.json", directoryHint: .notDirectory)
        try Data("not json {{{".utf8).write(to: credFile)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),
            executor: StubExecutor(),
            homeDirectory: tempDir
        )
        let r = await checker.checkClaudeAuth()
        XCTAssertEqual(r, .notInstalled)
    }
}
