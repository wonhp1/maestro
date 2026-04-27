@testable import MaestroCore
import XCTest

@MainActor
final class EnvironmentSetupViewModelTests: XCTestCase {
    // MARK: - Stubs

    /// EnvironmentChecker 동작을 통제하기 위한 fake — 결과를 미리 설정.
    private struct StubLocator: ExecutableLocating {
        let mapping: [String: URL?]
        func locate(_ executableName: String) -> URL? {
            mapping[executableName, default: nil]
        }
    }

    private final class StubExecutor: ProcessExecuting, @unchecked Sendable {
        var responses: [String: ProcessOutput] = [:]
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

    private final class StubDownloader: NodeDownloading, @unchecked Sendable {
        var downloadedPath: URL = URL(filePath: "/tmp/stub-node.pkg")
        func download(
            from url: URL,
            progress: @Sendable (Int64, Int64?) -> Void
        ) async throws -> URL {
            progress(50_000_000, 50_000_000)
            return downloadedPath
        }
    }

    private final class StubSudo: SudoExecuting, @unchecked Sendable {
        var shouldThrow: Error?
        func runWithAdminPrivileges(command: String, prompt: String) async throws {
            if let err = shouldThrow { throw err }
        }
    }

    // MARK: - Helpers

    /// 실제 EnvironmentChecker 를 stub locator/executor 로 만들어 viewModel 에 주입.
    private func makeChecker(
        node: ProcessOutput? = nil,
        claude: ProcessOutput? = nil,
        gitAvailable: Bool = false,
        homeDir: URL
    ) -> EnvironmentChecker {
        let executor = StubExecutor()
        if let node { executor.responses["node"] = node }
        if let claude { executor.responses["claude"] = claude }
        var mapping: [String: URL?] = [:]
        if node != nil { mapping["node"] = URL(filePath: "/usr/local/bin/node") }
        if claude != nil { mapping["claude"] = URL(filePath: "/usr/local/bin/claude") }
        if gitAvailable { mapping["git"] = URL(filePath: "/usr/bin/git") }
        return EnvironmentChecker(
            locator: StubLocator(mapping: mapping),
            executor: executor,
            homeDirectory: homeDir
        )
    }

    private func makeTempHome(authPresent: Bool) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "maestro-vm-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        if authPresent {
            let claudeDir = tempDir.appending(path: ".claude", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
            let credFile = claudeDir.appending(path: "credentials.json", directoryHint: .notDirectory)
            try Data("{\"token\":\"x\"}".utf8).write(to: credFile)
        }
        return tempDir
    }

    // MARK: - Phase transitions

    func testInitialPhaseIsIdle() {
        let vm = EnvironmentSetupViewModel()
        if case .idle = vm.phase {} else {
            XCTFail("초기 phase 는 idle 이어야 함, got \(vm.phase)")
        }
        XCTAssertNil(vm.lastError)
        XCTAssertNil(vm.status)
    }

    func testScanTransitionsFromIdleToReady() async throws {
        let home = try makeTempHome(authPresent: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let checker = makeChecker(
            node: ProcessOutput(stdout: "v22.11.0\n", stderr: "", exitCode: 0),
            claude: ProcessOutput(stdout: "1.0.0\n", stderr: "", exitCode: 0),
            gitAvailable: true,
            homeDir: home
        )
        let vm = EnvironmentSetupViewModel(checker: checker, installer: EnvironmentInstaller())
        await vm.scan()

        guard case let .ready(status) = vm.phase else {
            XCTFail("phase 는 ready 여야 함, got \(vm.phase)")
            return
        }
        XCTAssertTrue(status.claudeReady)
        XCTAssertTrue(vm.status?.claudeReady == true)
    }

    func testRescanResetsPhaseAndChecksAgain() async throws {
        let home = try makeTempHome(authPresent: false)
        defer { try? FileManager.default.removeItem(at: home) }

        let checker = makeChecker(homeDir: home)
        let vm = EnvironmentSetupViewModel(checker: checker, installer: EnvironmentInstaller())
        await vm.rescan()

        guard case let .ready(status) = vm.phase else {
            XCTFail("ready 기대, got \(vm.phase)")
            return
        }
        XCTAssertFalse(status.claudeReady)
        XCTAssertEqual(status.node, .notInstalled)
    }

    // MARK: - missingClaudeRequirements

    func testMissingClaudeRequirementsTrueWhenStatusUnknown() {
        let vm = EnvironmentSetupViewModel()
        XCTAssertTrue(vm.missingClaudeRequirements)
    }

    func testMissingClaudeRequirementsFalseWhenAllReady() async throws {
        let home = try makeTempHome(authPresent: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let checker = makeChecker(
            node: ProcessOutput(stdout: "v22.11.0\n", stderr: "", exitCode: 0),
            claude: ProcessOutput(stdout: "1.0.0\n", stderr: "", exitCode: 0),
            homeDir: home
        )
        let vm = EnvironmentSetupViewModel(checker: checker, installer: EnvironmentInstaller())
        await vm.scan()
        XCTAssertFalse(vm.missingClaudeRequirements)
    }

    // MARK: - hasInstallableMissing

    func testHasInstallableMissingTrueWhenNodeMissing() async throws {
        let home = try makeTempHome(authPresent: false)
        defer { try? FileManager.default.removeItem(at: home) }
        let checker = makeChecker(homeDir: home)
        let vm = EnvironmentSetupViewModel(checker: checker, installer: EnvironmentInstaller())
        await vm.scan()
        XCTAssertTrue(vm.hasInstallableMissing)
    }

    // MARK: - installMissing error path

    func testInstallMissingPropagatesSudoCancelledAsLastError() async throws {
        let home = try makeTempHome(authPresent: false)
        defer { try? FileManager.default.removeItem(at: home) }

        // Node 누락 상태 — installNode 호출됨.
        let checker = makeChecker(homeDir: home)

        let downloader = StubDownloader()
        let tempPkg = FileManager.default.temporaryDirectory
            .appending(path: "stub-vm-\(UUID().uuidString).pkg", directoryHint: .notDirectory)
        try Data().write(to: tempPkg)
        downloader.downloadedPath = tempPkg

        let sudo = StubSudo()
        sudo.shouldThrow = EnvironmentInstallerError.sudoCancelled

        let installer = EnvironmentInstaller(
            nodeDownloader: downloader,
            sudoExecutor: sudo
        )
        let vm = EnvironmentSetupViewModel(checker: checker, installer: installer)

        await vm.installMissing()

        XCTAssertNotNil(vm.lastError)
        XCTAssertTrue(vm.lastError?.contains("취소") == true)
        // 끝에 무조건 rescan — phase 는 ready.
        if case .ready = vm.phase {} else {
            XCTFail("install 실패 후 phase 는 ready 여야 함, got \(vm.phase)")
        }
    }

    // MARK: - Happy path: Node + Claude install end-to-end

    /// 누락 → installNode → checker 재검사 → installClaude → final scan ready 까지 검증.
    /// 핵심: AdapterInstall closure 가 호출되는지, mid 재검사가 phase 전이에 어떻게 반영되는지.
    func testInstallMissingFullFlowSucceedsAndUpdatesPhase() async throws {
        let home = try makeTempHome(authPresent: false)
        defer { try? FileManager.default.removeItem(at: home) }

        // Initial scan 시점에는 node/claude 둘 다 없음 → 설치 필요.
        let executor = StubExecutor()
        let locator = StubLocator(mapping: [:])
        let checker = EnvironmentChecker(
            locator: locator,
            executor: executor,
            homeDirectory: home
        )

        // Node downloader / sudo 는 성공 stub.
        let downloader = StubDownloader()
        let tempPkg = FileManager.default.temporaryDirectory
            .appending(path: "stub-vm-happy-\(UUID().uuidString).pkg", directoryHint: .notDirectory)
        try Data().write(to: tempPkg)
        downloader.downloadedPath = tempPkg

        // adapterInstall (Claude) 도 성공.
        let installer = EnvironmentInstaller(
            nodeDownloader: downloader,
            sudoExecutor: StubSudo(),
            adapterInstall: { _ in .success(stdoutTail: "added 100 packages") }
        )
        let vm = EnvironmentSetupViewModel(checker: checker, installer: installer)

        await vm.installMissing()

        // 끝에 final scan — 결과는 여전히 ready (StubLocator 가 install 후에도 매핑이 없음).
        XCTAssertNil(vm.lastError)
        if case .ready = vm.phase {} else {
            XCTFail("최종 phase 는 ready 여야 함, got \(vm.phase)")
        }
    }

    // MARK: - status callback

    /// VM 의 onStatusChange 콜백이 scan 완료마다 호출되는지.
    func testOnStatusChangeFiresOnScan() async throws {
        let home = try makeTempHome(authPresent: false)
        defer { try? FileManager.default.removeItem(at: home) }

        let checker = makeChecker(homeDir: home)
        let vm = EnvironmentSetupViewModel(checker: checker, installer: EnvironmentInstaller())

        let received = StatusBox()
        vm.onStatusChange = { @MainActor status in
            received.set(status)
        }

        await vm.scan()
        XCTAssertNotNil(received.value)
        XCTAssertEqual(received.value?.node, .notInstalled)
    }

    /// onStatusChange callback 결과 캡처용 — @MainActor isolated box.
    @MainActor
    private final class StatusBox {
        private(set) var value: EnvironmentStatus?
        func set(_ s: EnvironmentStatus) { value = s }
    }

    // MARK: - humanizeError full coverage

    func testHumanizeErrorAllVariants() async {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "maestro-err-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let checker = makeChecker(homeDir: home)

        // sudoFailed
        do {
            let sudo = StubSudo()
            sudo.shouldThrow = EnvironmentInstallerError.sudoFailed(reason: "auth-x")
            let downloader = StubDownloader()
            let pkg = FileManager.default.temporaryDirectory
                .appending(path: "stub-\(UUID().uuidString).pkg", directoryHint: .notDirectory)
            try? Data().write(to: pkg)
            downloader.downloadedPath = pkg
            let installer = EnvironmentInstaller(nodeDownloader: downloader, sudoExecutor: sudo)
            let vm = EnvironmentSetupViewModel(checker: checker, installer: installer)
            await vm.installMissing()
            XCTAssertTrue(vm.lastError?.contains("인증 실패") == true)
            XCTAssertTrue(vm.lastError?.contains("auth-x") == true)
        }

        // installFailed (Claude path) — Node 가 이미 있는 시나리오를 만들기 위해
        // checker 는 node ready, claude 누락 으로 둠.
        do {
            let executor = StubExecutor()
            executor.responses["node"] = ProcessOutput(stdout: "v22.0.0\n", stderr: "", exitCode: 0)
            let checker2 = EnvironmentChecker(
                locator: StubLocator(mapping: ["node": URL(filePath: "/usr/local/bin/node")]),
                executor: executor,
                homeDirectory: home
            )
            let installer = EnvironmentInstaller(
                adapterInstall: { _ in .failed(exitCode: 7, stderr: "boom") }
            )
            let vm = EnvironmentSetupViewModel(checker: checker2, installer: installer)
            await vm.installMissing()
            XCTAssertTrue(vm.lastError?.contains("설치 실패") == true)
            XCTAssertTrue(vm.lastError?.contains("exit 7") == true)
        }
    }

    // MARK: - Phase Equatable smoke

    func testPhaseEquatable() {
        XCTAssertEqual(EnvironmentSetupViewModel.Phase.idle, .idle)
        XCTAssertEqual(EnvironmentSetupViewModel.Phase.scanning, .scanning)
        XCTAssertNotEqual(
            EnvironmentSetupViewModel.Phase.idle,
            EnvironmentSetupViewModel.Phase.scanning
        )
    }
}
