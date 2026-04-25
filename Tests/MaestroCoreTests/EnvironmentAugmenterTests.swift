@testable import MaestroCore
import XCTest

final class EnvironmentAugmenterTests: XCTestCase {
    private var savedPATH: String?

    override func setUp() {
        super.setUp()
        savedPATH = ProcessInfo.processInfo.environment["PATH"]
        EnvironmentAugmenter.resetForTesting()
    }

    override func tearDown() {
        if let saved = savedPATH {
            saved.withCString { _ = setenv("PATH", $0, 1) }
        } else {
            unsetenv("PATH")
        }
        EnvironmentAugmenter.resetForTesting()
        super.tearDown()
    }

    // MARK: - merge

    func testMergeKeepsCurrentFirstThenAppendsNew() {
        let merged = EnvironmentAugmenter.merge(
            current: ["/usr/bin", "/bin"],
            additions: ["/opt/homebrew/bin", "/usr/bin", "/usr/local/bin"]
        )
        XCTAssertEqual(merged, [
            "/usr/bin", "/bin", "/opt/homebrew/bin", "/usr/local/bin",
        ])
    }

    func testMergeWithEmptyAdditionsIsIdentity() {
        let merged = EnvironmentAugmenter.merge(
            current: ["/usr/bin", "/bin"],
            additions: []
        )
        XCTAssertEqual(merged, ["/usr/bin", "/bin"])
    }

    func testMergeWithEmptyCurrentReturnsAdditions() {
        let merged = EnvironmentAugmenter.merge(
            current: [],
            additions: ["/opt/homebrew/bin"]
        )
        XCTAssertEqual(merged, ["/opt/homebrew/bin"])
    }

    func testMergeDeduplicatesAcrossInputs() {
        let merged = EnvironmentAugmenter.merge(
            current: ["/a", "/b", "/a"],
            additions: ["/b", "/c", "/b"]
        )
        XCTAssertEqual(merged, ["/a", "/b", "/c"])
    }

    func testFormatJoinsWithColon() {
        XCTAssertEqual(EnvironmentAugmenter.format(["/a", "/b"]), "/a:/b")
        XCTAssertEqual(EnvironmentAugmenter.format([]), "")
    }

    // MARK: - sanitize (PATH-poisoning 방어)

    func testSanitizeKeepsRealSystemDirs() {
        let result = EnvironmentAugmenter.sanitize(["/usr/bin", "/bin"])
        XCTAssertEqual(result, ["/usr/bin", "/bin"])
    }

    func testSanitizeDropsRelativePaths() {
        let result = EnvironmentAugmenter.sanitize(["./local", "../bin", "usr/bin"])
        XCTAssertEqual(result, [])
    }

    func testSanitizeDropsTmpAndOutsideAllowList() {
        let result = EnvironmentAugmenter.sanitize(["/tmp/attacker", "/var/spool"])
        XCTAssertEqual(result, [])
    }

    func testSanitizeDropsNonExistentPaths() {
        let result = EnvironmentAugmenter.sanitize(["/usr/this-dir-does-not-exist-xyz"])
        XCTAssertEqual(result, [])
    }

    func testSanitizeKeepsHomeDirSubpaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // 홈 디렉토리 자체는 늘 존재하므로 안전한 fixture
        let result = EnvironmentAugmenter.sanitize([home])
        XCTAssertEqual(result, [home])
    }

    // MARK: - augmentPATHFromLoginShell end-to-end

    func testAugmentPATHFromLoginShellWithStubReturnsAugmented() async {
        let stub = StubExtractor(result: .success(["/usr/bin", "/bin"]))
        let result = await EnvironmentAugmenter.augmentPATHFromLoginShell(
            extractor: stub.asExtractor()
        )
        if case .augmented = result {
            // ok — 정확한 addedCount 는 시스템 PATH 에 따라 다름
        } else {
            XCTFail("expected .augmented, got \(result)")
        }
    }

    func testAugmentPATHFromLoginShellSecondCallReturnsAlreadyAugmented() async {
        let stub = StubExtractor(result: .success(["/usr/bin"]))
        _ = await EnvironmentAugmenter.augmentPATHFromLoginShell(
            extractor: stub.asExtractor()
        )
        let result2 = await EnvironmentAugmenter.augmentPATHFromLoginShell(
            extractor: stub.asExtractor()
        )
        guard case .alreadyAugmented = result2 else {
            XCTFail("second call should be alreadyAugmented, got \(result2)")
            return
        }
    }

    func testAugmentPATHFromLoginShellExtractFailureDoesNotMutate() async {
        let original = ProcessInfo.processInfo.environment["PATH"]
        let stub = StubExtractor(
            result: .failure(LoginShellPathExtractorError.timedOut)
        )
        let result = await EnvironmentAugmenter.augmentPATHFromLoginShell(
            extractor: stub.asExtractor()
        )
        guard case .extractFailed = result else {
            XCTFail("expected .extractFailed, got \(result)")
            return
        }
        // PATH 변경 X — flag 도 false 유지 → 다음 시도 가능
        XCTAssertEqual(ProcessInfo.processInfo.environment["PATH"], original)
        let retry = await EnvironmentAugmenter.augmentPATHFromLoginShell(
            extractor: StubExtractor(result: .success(["/usr/bin"])).asExtractor()
        )
        if case .augmented = retry {
            // ok
        } else {
            XCTFail("retry after fail should be augmented")
        }
    }
}

/// 테스트용 — `LoginShellPathExtractor` 의 spawn 우회. ProcessExecuting 을 stub 으로
/// 주입한 LoginShellPathExtractor 를 만들어 반환.
private struct StubExtractor {
    let result: Result<[String], Error>

    func asExtractor() -> LoginShellPathExtractor {
        let stub = StubProcessExecutor(outputs: [resultToOutput()])
        return LoginShellPathExtractor(
            shellURL: URL(fileURLWithPath: "/bin/zsh"),
            executor: stub
        )
    }

    private func resultToOutput() -> StubProcessExecutor.Outcome {
        switch result {
        case .success(let paths):
            return .success(ProcessOutput(
                stdout: paths.joined(separator: ":"),
                stderr: "",
                exitCode: 0
            ))
        case .failure(let err):
            // LoginShellPathExtractorError 를 ProcessExecutionError 로 변환
            switch err {
            case LoginShellPathExtractorError.timedOut:
                return .failure(ProcessExecutionError.timedOut)
            default:
                return .failure(ProcessExecutionError.launchFailed(
                    reason: String(describing: err)
                ))
            }
        }
    }
}

private actor StubProcessExecutor: ProcessExecuting {
    enum Outcome {
        case success(ProcessOutput)
        case failure(Error)
    }

    private var outputs: [Outcome]

    init(outputs: [Outcome]) { self.outputs = outputs }

    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        guard !outputs.isEmpty else {
            throw ProcessExecutionError.launchFailed(reason: "stub exhausted")
        }
        switch outputs.removeFirst() {
        case .success(let out): return out
        case .failure(let err): throw err
        }
    }
}
