@testable import MaestroCore
import XCTest

final class EnvironmentInstallerTests: XCTestCase {
    // MARK: - Pure logic helpers

    func testInstallerCommandBuildsExpectedFormat() {
        XCTAssertEqual(
            EnvironmentInstaller.installerCommand(pkgPath: "/tmp/node.pkg"),
            "/usr/sbin/installer -pkg '/tmp/node.pkg' -target /"
        )
    }

    func testInstallerCommandEscapesSingleQuoteInPath() {
        // 사용자 임시 폴더 이름에 single quote 있는 비정상 case — sh-safe escape.
        XCTAssertEqual(
            EnvironmentInstaller.installerCommand(pkgPath: "/tmp/it's/node.pkg"),
            "/usr/sbin/installer -pkg '/tmp/it'\\''s/node.pkg' -target /"
        )
    }

    // MARK: - AppleScript escape

    func testOsascriptEscapeDoubleQuote() {
        XCTAssertEqual(
            OsascriptSudoExecutor.escape(#"a "b" c"#),
            #"a \"b\" c"#
        )
    }

    func testOsascriptEscapeBackslash() {
        XCTAssertEqual(
            OsascriptSudoExecutor.escape(#"path\to\file"#),
            #"path\\to\\file"#
        )
    }

    func testOsascriptEscapeBackslashBeforeQuote() {
        // Order matters: backslash escape 가 먼저, quote 가 다음.
        XCTAssertEqual(
            OsascriptSudoExecutor.escape(#"\"#),
            #"\\"#
        )
    }

    func testAppleScriptBuilderProducesValidSyntax() {
        let script = OsascriptSudoExecutor.appleScript(
            command: "echo hello",
            prompt: "테스트 prompt"
        )
        XCTAssertEqual(
            script,
            #"do shell script "echo hello" with prompt "테스트 prompt" with administrator privileges"#
        )
    }

    // MARK: - InstallProgress equality

    func testInstallProgressEquality() {
        XCTAssertEqual(
            InstallProgress.downloading(bytes: 100, total: 1000),
            InstallProgress.downloading(bytes: 100, total: 1000)
        )
        XCTAssertNotEqual(
            InstallProgress.downloading(bytes: 100, total: 1000),
            InstallProgress.complete
        )
        XCTAssertEqual(
            InstallProgress.running(phase: "test"),
            InstallProgress.running(phase: "test")
        )
    }

    // MARK: - EnvironmentInstaller integration via stubs

    private final class StubDownloader: NodeDownloading, @unchecked Sendable {
        var downloadedPath: URL = URL(filePath: "/tmp/stub-node.pkg")
        var calledWith: URL?
        func download(
            from url: URL,
            progress: @Sendable (Int64, Int64?) -> Void
        ) async throws -> URL {
            calledWith = url
            progress(50_000_000, 50_000_000)  // simulate 50MB downloaded
            return downloadedPath
        }
    }

    private final class StubSudo: SudoExecuting, @unchecked Sendable {
        var calledWithCommand: String?
        var shouldThrow: Error?
        func runWithAdminPrivileges(command: String, prompt: String) async throws {
            calledWithCommand = command
            if let err = shouldThrow { throw err }
        }
    }

    /// Sendable closure capture 회피용 thread-safe append.
    private final class ProgressCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var _events: [InstallProgress] = []
        func append(_ e: InstallProgress) {
            lock.lock(); defer { lock.unlock() }
            _events.append(e)
        }
        var events: [InstallProgress] {
            lock.lock(); defer { lock.unlock() }
            return _events
        }
    }

    func testInstallNodeFlowDownloadsAndRunsInstaller() async throws {
        let downloader = StubDownloader()
        // 임시 파일 만들어서 cleanup 단계 통과 (defer { removeItem(...) }).
        let tempPkg = FileManager.default.temporaryDirectory
            .appending(path: "stub-node-\(UUID().uuidString).pkg", directoryHint: .notDirectory)
        try Data().write(to: tempPkg)
        downloader.downloadedPath = tempPkg
        let sudo = StubSudo()
        let installer = EnvironmentInstaller(
            nodeDownloader: downloader,
            sudoExecutor: sudo
        )

        // 동시성 안전 collector — closure 가 @Sendable 라 외부 var 캡처 못 함.
        let collector = ProgressCollector()
        try await installer.installNode { event in
            collector.append(event)
        }
        let progressEvents = collector.events

        XCTAssertEqual(downloader.calledWith, EnvironmentInstaller.defaultNodePackageURL)
        XCTAssertNotNil(sudo.calledWithCommand)
        XCTAssertTrue(sudo.calledWithCommand?.contains("/usr/sbin/installer") == true)
        XCTAssertTrue(sudo.calledWithCommand?.contains(tempPkg.path) == true)
        XCTAssertTrue(progressEvents.contains(.complete))
    }

    func testInstallClaudeFailurePropagatesAsInstallFailed() async {
        let installer = EnvironmentInstaller(
            adapterInstall: { _ in
                .failed(exitCode: 1, stderr: "npm: ENOENT package.json")
            }
        )
        do {
            try await installer.installClaude()
            XCTFail("expected installFailed")
        } catch let err as EnvironmentInstallerError {
            switch err {
            case .installFailed(let code, let stderr):
                XCTAssertEqual(code, 1)
                XCTAssertTrue(stderr.contains("ENOENT"))
            default:
                XCTFail("wrong error: \(err)")
            }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testInstallClaudeSuccessPropagates() async throws {
        let installer = EnvironmentInstaller(
            adapterInstall: { _ in .success(stdoutTail: "added 100 packages") }
        )
        try await installer.installClaude()  // throws X 면 통과
    }

    func testInstallAiderFailurePropagatesAsInstallFailed() async {
        let installer = EnvironmentInstaller(
            adapterInstall: { _ in
                .failed(exitCode: 1, stderr: "pip: requirement not found")
            }
        )
        do {
            try await installer.installAider()
            XCTFail("expected installFailed")
        } catch let err as EnvironmentInstallerError {
            if case .installFailed = err {} else {
                XCTFail("wrong error: \(err)")
            }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testInstallNodePropagatesSudoCancel() async {
        let downloader = StubDownloader()
        let tempPkg = FileManager.default.temporaryDirectory
            .appending(path: "stub-node-\(UUID().uuidString).pkg", directoryHint: .notDirectory)
        try? Data().write(to: tempPkg)
        downloader.downloadedPath = tempPkg
        let sudo = StubSudo()
        sudo.shouldThrow = EnvironmentInstallerError.sudoCancelled
        let installer = EnvironmentInstaller(
            nodeDownloader: downloader,
            sudoExecutor: sudo
        )

        do {
            try await installer.installNode()
            XCTFail("expected error")
        } catch let err as EnvironmentInstallerError {
            XCTAssertEqual(err, .sudoCancelled)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Sudo cancel detection (locale-tolerant)
    // OsascriptSudoExecutor 의 stderr 매칭 검증은 통합 — but DefaultProcessExecutor 모킹
    // 어려움. ProcessExecuting protocol 로 stub 가능.

    private final class StubProcExec: ProcessExecuting, @unchecked Sendable {
        var output: ProcessOutput
        init(output: ProcessOutput) { self.output = output }
        func run(
            executable: URL,
            arguments: [String],
            currentDirectoryURL: URL?,
            environment: [String: String]?
        ) async throws -> ProcessOutput { output }
    }

    func testOsascriptSudoCancelKoreanLocale() async {
        // 한국어 환경의 osascript stderr 변형 — "사용자가 취소했습니다."
        let stub = StubProcExec(output: ProcessOutput(
            stdout: "", stderr: "execution error: 사용자가 취소했습니다. (-128)", exitCode: 1
        ))
        let exec = OsascriptSudoExecutor(executor: stub)
        do {
            try await exec.runWithAdminPrivileges(command: "echo 1", prompt: "test")
            XCTFail("expected cancel")
        } catch let err as EnvironmentInstallerError {
            XCTAssertEqual(err, .sudoCancelled)
        } catch {
            XCTFail("wrong: \(error)")
        }
    }

    func testOsascriptSudoFailureNonCancel() async {
        let stub = StubProcExec(output: ProcessOutput(
            stdout: "", stderr: "execution error: random failure (-1700)", exitCode: 1
        ))
        let exec = OsascriptSudoExecutor(executor: stub)
        do {
            try await exec.runWithAdminPrivileges(command: "echo 1", prompt: "test")
            XCTFail("expected failure")
        } catch let err as EnvironmentInstallerError {
            if case .sudoFailed = err {} else { XCTFail("wrong: \(err)") }
        } catch {
            XCTFail("wrong: \(error)")
        }
    }
}
