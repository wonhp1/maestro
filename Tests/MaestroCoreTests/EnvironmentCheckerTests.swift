// swiftlint:disable file_length
@testable import MaestroCore
import XCTest

// swiftlint:disable:next type_body_length
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

    // MARK: - Codex check (v0.9.0)

    func testCheckCodexMissingReturnsNotInstalled() async {
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),
            executor: StubExecutor()
        )
        let r = await checker.checkCodex()
        XCTAssertEqual(r, .notInstalled)
    }

    func testCheckCodexInstalledExtractsVersion() async {
        let executor = StubExecutor()
        executor.responses["codex"] = ProcessOutput(
            stdout: "codex-cli 0.125.0\n", stderr: "", exitCode: 0
        )
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: ["codex": URL(filePath: "/usr/local/bin/codex")]),
            executor: executor
        )
        let r = await checker.checkCodex()
        XCTAssertEqual(r, .installed(version: "0.125.0"))
    }

    /// Codex auth tests 는 빈 homeDirectory 가 필요 — 실제 ~/.codex/auth.json
    /// 우선순위가 stub 결과를 가림.
    private func emptyHomeDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "maestro-codex-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    func testCheckCodexAuthLoggedInReturnsInstalled() async throws {
        let home = try emptyHomeDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let executor = StubExecutor()
        executor.responses["codex"] = ProcessOutput(
            stdout: "Logged in as user@example.com\n", stderr: "", exitCode: 0
        )
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: ["codex": URL(filePath: "/usr/local/bin/codex")]),
            executor: executor,
            homeDirectory: home
        )
        let r = await checker.checkCodexAuth()
        XCTAssertEqual(r, .installed(version: nil))
    }

    func testCheckCodexAuthNotLoggedInReturnsNotInstalled() async throws {
        let home = try emptyHomeDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let executor = StubExecutor()
        executor.responses["codex"] = ProcessOutput(
            stdout: "Not logged in\n", stderr: "", exitCode: 0
        )
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: ["codex": URL(filePath: "/usr/local/bin/codex")]),
            executor: executor,
            homeDirectory: home
        )
        let r = await checker.checkCodexAuth()
        XCTAssertEqual(r, .notInstalled)
    }

    func testCheckCodexAuthAPIKeyEnvFallback() async throws {
        // CLI 미설치 + 빈 home 상태에서도 OPENAI_API_KEY 만으로 인증 OK.
        let home = try emptyHomeDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),
            executor: StubExecutor(),
            homeDirectory: home,
            environment: ["OPENAI_API_KEY": "sk-fake"]
        )
        let r = await checker.checkCodexAuth()
        XCTAssertEqual(r, .installed(version: nil))
    }

    func testCheckCodexAuthEmptyEnvVarNotTreatedAsAuth() async throws {
        let home = try emptyHomeDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),
            executor: StubExecutor(),
            homeDirectory: home,
            environment: ["OPENAI_API_KEY": ""]
        )
        let r = await checker.checkCodexAuth()
        XCTAssertEqual(r, .notInstalled)
    }

    func testCheckCodexAuthExitNonZeroReturnsNotInstalled() async throws {
        let home = try emptyHomeDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let executor = StubExecutor()
        executor.responses["codex"] = ProcessOutput(
            stdout: "", stderr: "internal error", exitCode: 1
        )
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: ["codex": URL(filePath: "/usr/local/bin/codex")]),
            executor: executor,
            homeDirectory: home
        )
        let r = await checker.checkCodexAuth()
        XCTAssertEqual(r, .notInstalled)
    }

    func testCheckCodexAuthExecutorThrowReturnsNotInstalled() async throws {
        let home = try emptyHomeDir()
        defer { try? FileManager.default.removeItem(at: home) }
        final class ThrowingExec: ProcessExecuting, @unchecked Sendable {
            func run(
                executable: URL,
                arguments: [String],
                currentDirectoryURL: URL?,
                environment: [String: String]?
            ) async throws -> ProcessOutput {
                throw ProcessExecutionError.timedOut
            }
        }
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: ["codex": URL(filePath: "/usr/local/bin/codex")]),
            executor: ThrowingExec(),
            homeDirectory: home
        )
        let r = await checker.checkCodexAuth()
        XCTAssertEqual(r, .notInstalled)
    }

    func testCheckCodexAuthFromAuthJsonFile() async throws {
        // ~/.codex/auth.json 존재 + valid JSON → installed (subprocess 안 거침).
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "maestro-codex-auth-\(UUID().uuidString)", directoryHint: .isDirectory)
        let codexDir = tempDir.appending(path: ".codex", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let authFile = codexDir.appending(path: "auth.json", directoryHint: .notDirectory)
        try Data("{\"token\":\"oauth-token\"}".utf8).write(to: authFile)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),  // CLI 없어도 됨
            executor: StubExecutor(),
            homeDirectory: tempDir
        )
        let r = await checker.checkCodexAuth()
        XCTAssertEqual(r, .installed(version: nil))
    }

    func testCheckCodexAuthCorruptAuthJsonFallsThroughToCLI() async throws {
        // corrupt auth.json → file fast path 실패 → CLI status 로 fall through.
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "maestro-codex-corrupt-\(UUID().uuidString)", directoryHint: .isDirectory)
        let codexDir = tempDir.appending(path: ".codex", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let authFile = codexDir.appending(path: "auth.json", directoryHint: .notDirectory)
        try Data("not json {{{".utf8).write(to: authFile)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let executor = StubExecutor()
        executor.responses["codex"] = ProcessOutput(
            stdout: "Logged in using ChatGPT\n", stderr: "", exitCode: 0
        )
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: ["codex": URL(filePath: "/usr/local/bin/codex")]),
            executor: executor,
            homeDirectory: tempDir
        )
        let r = await checker.checkCodexAuth()
        XCTAssertEqual(r, .installed(version: nil))
    }

    func testCheckCodexAuthAmbiguousOutputConservative() async throws {
        let home = try emptyHomeDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let executor = StubExecutor()
        executor.responses["codex"] = ProcessOutput(
            stdout: "Some unknown status response\n", stderr: "", exitCode: 0
        )
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: ["codex": URL(filePath: "/usr/local/bin/codex")]),
            executor: executor,
            homeDirectory: home
        )
        let r = await checker.checkCodexAuth()
        XCTAssertEqual(r, .notInstalled)
    }

    func testClassifyCodexLoginStatusPositiveVariants() {
        // 다양한 "logged in" 표현이 모두 installed 로 분류.
        let cases = [
            "Logged in as foo@bar.com",
            "User authenticated successfully",
            "✓ logged in",
        ]
        for stdout in cases {
            let out = ProcessOutput(stdout: stdout, stderr: "", exitCode: 0)
            XCTAssertEqual(
                EnvironmentChecker.classifyCodexLoginStatus(output: out),
                .installed(version: nil),
                "expected installed for: \(stdout)"
            )
        }
    }

    func testClassifyCodexLoginStatusNegativeVariants() {
        let cases = [
            "Not logged in",
            "no active session for this user",
            "no credentials found",
            "you are logged out",
        ]
        for stdout in cases {
            let out = ProcessOutput(stdout: stdout, stderr: "", exitCode: 0)
            XCTAssertEqual(
                EnvironmentChecker.classifyCodexLoginStatus(output: out),
                .notInstalled,
                "expected notInstalled for: \(stdout)"
            )
        }
    }

    // MARK: - Gemini check (v0.9.0)

    func testCheckGeminiMissingReturnsNotInstalled() async {
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),
            executor: StubExecutor()
        )
        let r = await checker.checkGemini()
        XCTAssertEqual(r, .notInstalled)
    }

    func testCheckGeminiInstalledExtractsVersion() async {
        let executor = StubExecutor()
        executor.responses["gemini"] = ProcessOutput(
            stdout: "0.40.0\n", stderr: "", exitCode: 0
        )
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: ["gemini": URL(filePath: "/usr/local/bin/gemini")]),
            executor: executor
        )
        let r = await checker.checkGemini()
        XCTAssertEqual(r, .installed(version: "0.40.0"))
    }

    func testCheckGeminiAuthOAuthFileExists() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "maestro-vm-gemini-\(UUID().uuidString)", directoryHint: .isDirectory)
        let gemDir = tempDir.appending(path: ".gemini", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: gemDir, withIntermediateDirectories: true)
        let cred = gemDir.appending(path: "oauth_creds.json", directoryHint: .notDirectory)
        try Data("{\"refresh_token\":\"x\"}".utf8).write(to: cred)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),
            executor: StubExecutor(),
            homeDirectory: tempDir
        )
        let r = await checker.checkGeminiAuth()
        XCTAssertEqual(r, .installed(version: nil))
    }

    func testCheckGeminiAuthMissingFileReturnsNotInstalled() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "maestro-vm-gem2-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),
            executor: StubExecutor(),
            homeDirectory: tempDir
        )
        let r = await checker.checkGeminiAuth()
        XCTAssertEqual(r, .notInstalled)
    }

    func testCheckGeminiAuthAPIKeyEnvFallback() async {
        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),
            executor: StubExecutor(),
            environment: ["GEMINI_API_KEY": "AIzaFake"]
        )
        let r = await checker.checkGeminiAuth()
        XCTAssertEqual(r, .installed(version: nil))
    }

    func testCheckGeminiAuthCorruptJSONTreatedAsMissing() async throws {
        // claudeAuth 와 대칭 — corrupt JSON 도 차단.
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "maestro-vm-gem3-\(UUID().uuidString)", directoryHint: .isDirectory)
        let gemDir = tempDir.appending(path: ".gemini", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: gemDir, withIntermediateDirectories: true)
        let cred = gemDir.appending(path: "oauth_creds.json", directoryHint: .notDirectory)
        try Data("not json {{{".utf8).write(to: cred)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let checker = EnvironmentChecker(
            locator: StubLocator(mapping: [:]),
            executor: StubExecutor(),
            homeDirectory: tempDir
        )
        let r = await checker.checkGeminiAuth()
        XCTAssertEqual(r, .notInstalled)
    }

    // MARK: - codexReady / geminiReady

    func testCodexReadyRequiresAllThree() {
        let allReady = EnvironmentStatus(
            node: .installed(version: "v22"),
            claude: .notInstalled,
            git: .notInstalled,
            python3: .notInstalled,
            aider: .notInstalled,
            claudeAuth: .notInstalled,
            codex: .installed(version: "0.125.0"),
            codexAuth: .installed(version: nil)
        )
        XCTAssertTrue(allReady.codexReady)

        let missingAuth = EnvironmentStatus(
            node: .installed(version: "v22"),
            claude: .notInstalled,
            git: .notInstalled,
            python3: .notInstalled,
            aider: .notInstalled,
            claudeAuth: .notInstalled,
            codex: .installed(version: "0.125.0"),
            codexAuth: .notInstalled
        )
        XCTAssertFalse(missingAuth.codexReady)
    }

    func testGeminiReadyRequiresAllThree() {
        let allReady = EnvironmentStatus(
            node: .installed(version: "v22"),
            claude: .notInstalled,
            git: .notInstalled,
            python3: .notInstalled,
            aider: .notInstalled,
            claudeAuth: .notInstalled,
            gemini: .installed(version: "0.40.0"),
            geminiAuth: .installed(version: nil)
        )
        XCTAssertTrue(allReady.geminiReady)

        let missingNode = EnvironmentStatus(
            node: .notInstalled,
            claude: .notInstalled,
            git: .notInstalled,
            python3: .notInstalled,
            aider: .notInstalled,
            claudeAuth: .notInstalled,
            gemini: .installed(version: "0.40.0"),
            geminiAuth: .installed(version: nil)
        )
        XCTAssertFalse(missingNode.geminiReady)
    }

    func testAdapterRequirementToolsForKnownAdapters() {
        XCTAssertEqual(AdapterRequirement.tools(for: "claude"), [.node, .claude, .claudeAuth])
        XCTAssertEqual(AdapterRequirement.tools(for: "aider"), [.git, .python3, .aider])
        XCTAssertEqual(AdapterRequirement.tools(for: "codex"), [.node, .codex, .codexAuth])
        XCTAssertEqual(AdapterRequirement.tools(for: "gemini"), [.node, .gemini, .geminiAuth])
        XCTAssertNil(AdapterRequirement.tools(for: "unknown"))
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
