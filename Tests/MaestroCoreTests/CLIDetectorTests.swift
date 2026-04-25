import Foundation
@testable import MaestroCore
import XCTest

final class CLIDetectorTests: XCTestCase {
    func testNotInstalledWhenLocatorReturnsNil() async throws {
        let detector = CLIDetector(
            locator: StubLocator(map: [:]),
            executor: StubExecutor(stdout: "", stderr: "", exitCode: 0)
        )
        let profile = try makeProfile(executable: "missing-cli")
        let detection = await detector.detect(profile: profile)
        XCTAssertFalse(detection.isInstalled)
        XCTAssertNil(detection.version)
        XCTAssertNil(detection.executablePath)
    }

    func testInstalledWithVersionExtractedFromStdout() async throws {
        let path = URL(fileURLWithPath: "/usr/local/bin/fakecli")
        let detector = CLIDetector(
            locator: StubLocator(map: ["fakecli": path]),
            executor: StubExecutor(stdout: "fakecli 1.2.3 (rev abc)\n", stderr: "", exitCode: 0)
        )
        let profile = try makeProfile(
            executable: "fakecli",
            versionRegex: #"\b([0-9]+\.[0-9]+\.[0-9]+)\b"#
        )
        let detection = await detector.detect(profile: profile)
        XCTAssertTrue(detection.isInstalled)
        XCTAssertEqual(detection.version, "1.2.3")
        XCTAssertEqual(detection.executablePath, path)
    }

    func testInstalledFallsBackToStderrForVersion() async throws {
        // 일부 CLI 가 --version 출력을 stderr 로 흘림 (claude-cli, brew 일부).
        let path = URL(fileURLWithPath: "/usr/local/bin/fakecli")
        let detector = CLIDetector(
            locator: StubLocator(map: ["fakecli": path]),
            executor: StubExecutor(stdout: "", stderr: "v9.8.7\n", exitCode: 0)
        )
        let profile = try makeProfile(
            executable: "fakecli",
            versionRegex: #"v([0-9]+\.[0-9]+\.[0-9]+)"#
        )
        let detection = await detector.detect(profile: profile)
        XCTAssertEqual(detection.version, "9.8.7")
    }

    func testExecutorThrowsKeepsInstalledTrueButVersionNil() async throws {
        let path = URL(fileURLWithPath: "/usr/local/bin/fakecli")
        let detector = CLIDetector(
            locator: StubLocator(map: ["fakecli": path]),
            executor: StubExecutor(error: ProcessExecutionError.timedOut)
        )
        let profile = try makeProfile(executable: "fakecli")
        let detection = await detector.detect(profile: profile)
        XCTAssertTrue(detection.isInstalled)
        XCTAssertNil(detection.version)
        XCTAssertEqual(detection.executablePath, path)
    }

    func testRegexNoMatchYieldsNilVersion() async throws {
        let path = URL(fileURLWithPath: "/usr/local/bin/fakecli")
        let detector = CLIDetector(
            locator: StubLocator(map: ["fakecli": path]),
            executor: StubExecutor(stdout: "no version here", stderr: "", exitCode: 0)
        )
        let profile = try makeProfile(
            executable: "fakecli",
            versionRegex: #"\b([0-9]+\.[0-9]+\.[0-9]+)\b"#
        )
        let detection = await detector.detect(profile: profile)
        XCTAssertTrue(detection.isInstalled)
        XCTAssertNil(detection.version)
    }

    func testExtractVersionUsesFirstCaptureGroupWhenPresent() {
        let v = CLIDetector.extractVersion(
            from: "tool 1.2.3 build 99",
            pattern: #"\b([0-9]+\.[0-9]+\.[0-9]+)\b"#
        )
        XCTAssertEqual(v, "1.2.3")
    }

    func testExtractVersionFallsBackToFullMatchWhenNoCapture() {
        let v = CLIDetector.extractVersion(
            from: "v3.4.5",
            pattern: #"v[0-9]+\.[0-9]+\.[0-9]+"#
        )
        XCTAssertEqual(v, "v3.4.5")
    }

    func testExtractVersionEmptyPatternReturnsNil() {
        XCTAssertNil(CLIDetector.extractVersion(from: "1.0.0", pattern: ""))
    }

    func testExtractVersionInvalidPatternReturnsNil() {
        XCTAssertNil(CLIDetector.extractVersion(from: "1.0.0", pattern: "([invalid"))
    }

    // MARK: - PATH locator integration smoke (uses real /bin/sh which exists everywhere).

    func testPATHLocatorFindsCommonExecutable() {
        let locator = PATHExecutableLocator()
        // 모든 macOS/Linux 에 존재하는 실행 파일.
        let url = locator.locate("sh") ?? locator.locate("ls")
        XCTAssertNotNil(url, "PATH 에서 sh/ls 를 찾지 못함 — locator 결함")
    }

    func testPATHLocatorReturnsNilForNonexistentName() {
        let locator = PATHExecutableLocator()
        XCTAssertNil(locator.locate("definitely-not-a-real-binary-xyz-123"))
    }

    func testPATHLocatorRejectsEmptyName() {
        let locator = PATHExecutableLocator()
        XCTAssertNil(locator.locate(""))
    }

    func testPATHLocatorAcceptsAbsolutePathDirectly() {
        let locator = PATHExecutableLocator()
        // /bin/sh 는 모든 Unix 에 존재하고 실행 가능.
        XCTAssertNotNil(locator.locate("/bin/sh"))
        XCTAssertNil(locator.locate("/no/such/path/at/all/please"))
    }

    func testPATHLocatorWithOverrideRespectsCustomPath() {
        let locator = PATHExecutableLocator(pathOverride: "/bin")
        XCTAssertNotNil(locator.locate("sh"))
    }

    func testPATHLocatorIgnoresEmptyAndDoubleColons() {
        let locator = PATHExecutableLocator(pathOverride: ":/bin::/usr/bin:")
        XCTAssertNotNil(locator.locate("sh"))
    }

    func testPATHLocatorEmptyOverrideReturnsNil() {
        let locator = PATHExecutableLocator(pathOverride: "")
        XCTAssertNil(locator.locate("sh"))
    }

    func testPATHLocatorSkipsDirectoriesShadowingExecutable() throws {
        let tempDir = try TestSupport.makeTempDirectory(named: "path-locator")
        defer { TestSupport.removeTempDirectory(tempDir) }
        // tempDir 안에 'shadow' 라는 디렉토리 생성 — 일반 파일이 아니므로 매칭 거부.
        let shadowDir = tempDir.appending(path: "shadow")
        try FileManager.default.createDirectory(at: shadowDir, withIntermediateDirectories: true)
        let locator = PATHExecutableLocator(pathOverride: tempDir.path)
        XCTAssertNil(locator.locate("shadow"))
    }

    // MARK: - ReDoS defense

    func testCombinedRegexInputCappedAt16KiB() async throws {
        // stderr 로 거대한 garbage + 끝부분에 진짜 버전 → cap 때문에 매칭 안 됨 검증.
        let huge = String(repeating: "X", count: 32 * 1024)
        let stderr = huge + "v9.9.9"
        let path = URL(fileURLWithPath: "/usr/local/bin/fakecli")
        let detector = CLIDetector(
            locator: StubLocator(map: ["fakecli": path]),
            executor: StubExecutor(stdout: "", stderr: stderr, exitCode: 0)
        )
        let profile = try makeProfile(
            executable: "fakecli",
            versionRegex: #"v([0-9]+\.[0-9]+\.[0-9]+)"#
        )
        let detection = await detector.detect(profile: profile)
        // 진짜 버전은 cap (16 KiB) 이후에 있으므로 추출 실패.
        XCTAssertNil(detection.version)
    }

    // MARK: - End-to-end: real executor + real PATH locator + real binary

    func testE2EWithRealEchoBinary() async throws {
        // /bin/echo 는 항상 존재. profile.detectArgs 로 직접 버전 출력 시뮬레이션.
        let detector = CLIDetector(
            locator: PATHExecutableLocator(pathOverride: "/bin"),
            executor: DefaultProcessExecutor(timeout: 5)
        )
        let profile = AgentProfile(
            adapterId: try AdapterID.validated(rawValue: "echo-test"),
            displayName: "Echo",
            executable: "echo",
            detectArgs: ["echo 1.0.0"],
            versionRegex: #"([0-9]+\.[0-9]+\.[0-9]+)"#,
            invokeArgs: []
        )
        let detection = await detector.detect(profile: profile)
        XCTAssertTrue(detection.isInstalled)
        XCTAssertEqual(detection.version, "1.0.0")
        XCTAssertEqual(detection.executablePath?.lastPathComponent, "echo")
    }

    // MARK: helpers

    private func makeProfile(
        executable: String,
        versionRegex: String = #"([0-9]+\.[0-9]+\.[0-9]+)"#
    ) throws -> AgentProfile {
        AgentProfile(
            adapterId: try AdapterID.validated(rawValue: "test"),
            displayName: "Test",
            executable: executable,
            detectArgs: ["--version"],
            versionRegex: versionRegex,
            invokeArgs: []
        )
    }
}

// MARK: - Stubs

private struct StubLocator: ExecutableLocating {
    let map: [String: URL]
    func locate(_ executableName: String) -> URL? { map[executableName] }
}

private struct StubExecutor: ProcessExecuting {
    let output: ProcessOutput?
    let error: Error?

    init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
        self.output = ProcessOutput(stdout: stdout, stderr: stderr, exitCode: exitCode)
        self.error = nil
    }

    init(error: Error) {
        self.output = nil
        self.error = error
    }

    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        if let error = error { throw error }
        return output!
    }
}
