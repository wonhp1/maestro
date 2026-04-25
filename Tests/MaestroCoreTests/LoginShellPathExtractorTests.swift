@testable import MaestroCore
import XCTest

final class LoginShellPathExtractorTests: XCTestCase {
    func testParsesNormalPath() {
        let raw = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        let parsed = LoginShellPathExtractor.parse(raw)
        XCTAssertEqual(parsed, [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        ])
    }

    func testTrimsWhitespaceAndDropsEmpty() {
        let raw = "  /opt/homebrew/bin :: /usr/bin  \n"
        let parsed = LoginShellPathExtractor.parse(raw)
        XCTAssertEqual(parsed, ["/opt/homebrew/bin", "/usr/bin"])
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(LoginShellPathExtractor.parse(""), [])
        XCTAssertEqual(LoginShellPathExtractor.parse("   \n  "), [])
    }

    func testDeduplicatesPreservingFirstOccurrence() {
        let raw = "/a:/b:/a:/c:/b"
        XCTAssertEqual(LoginShellPathExtractor.parse(raw), ["/a", "/b", "/c"])
    }

    func testParseHandlesUTF8Paths() {
        let raw = "/Users/김/bin:/usr/bin"
        XCTAssertEqual(LoginShellPathExtractor.parse(raw), ["/Users/김/bin", "/usr/bin"])
    }

    // MARK: - extract() 통합

    func testExtractWithStubExecutorReturnsParsed() async throws {
        let stub = StubExecutor(
            outputs: [.success(ProcessOutput(
                stdout: "/opt/homebrew/bin:/usr/bin\n",
                stderr: "",
                exitCode: 0
            ))]
        )
        let extractor = LoginShellPathExtractor(
            shellURL: URL(fileURLWithPath: "/bin/zsh"),
            executor: stub
        )
        let result = try await extractor.extract()
        XCTAssertEqual(result, ["/opt/homebrew/bin", "/usr/bin"])
    }

    func testExtractWithEmptyStdoutReturnsEmpty() async throws {
        let stub = StubExecutor(outputs: [.success(
            ProcessOutput(stdout: "", stderr: "", exitCode: 0)
        )])
        let extractor = LoginShellPathExtractor(
            shellURL: URL(fileURLWithPath: "/bin/zsh"),
            executor: stub
        )
        let result = try await extractor.extract()
        XCTAssertEqual(result, [])
    }

    func testExtractWithNonZeroExitThrows() async {
        let stub = StubExecutor(outputs: [.success(
            ProcessOutput(stdout: "", stderr: "boom", exitCode: 1)
        )])
        let extractor = LoginShellPathExtractor(
            shellURL: URL(fileURLWithPath: "/bin/zsh"),
            executor: stub
        )
        do {
            _ = try await extractor.extract()
            XCTFail("expected throw")
        } catch let LoginShellPathExtractorError.shellFailed(exitCode, stderr) {
            XCTAssertEqual(exitCode, 1)
            XCTAssertEqual(stderr, "boom")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testExtractTimeoutPropagates() async {
        let stub = StubExecutor(outputs: [.failure(ProcessExecutionError.timedOut)])
        let extractor = LoginShellPathExtractor(
            shellURL: URL(fileURLWithPath: "/bin/zsh"),
            executor: stub
        )
        do {
            _ = try await extractor.extract()
            XCTFail("expected throw")
        } catch LoginShellPathExtractorError.timedOut {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testExtractLaunchFailureWrapsAsSpawnFailed() async {
        let stub = StubExecutor(outputs: [.failure(
            ProcessExecutionError.launchFailed(reason: "no such file")
        )])
        let extractor = LoginShellPathExtractor(
            shellURL: URL(fileURLWithPath: "/bin/zsh"),
            executor: stub
        )
        do {
            _ = try await extractor.extract()
            XCTFail("expected throw")
        } catch let LoginShellPathExtractorError.spawnFailed(underlying) {
            XCTAssertEqual(underlying, .launchFailed(reason: "no such file"))
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testExtractInvokesShellWithLoginInteractiveArgs() async throws {
        let stub = StubExecutor(outputs: [.success(
            ProcessOutput(stdout: "/usr/bin", stderr: "", exitCode: 0)
        )])
        let extractor = LoginShellPathExtractor(
            shellURL: URL(fileURLWithPath: "/bin/zsh"),
            executor: stub
        )
        _ = try await extractor.extract()
        let calls = await stub.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.arguments, ["-ilc", "echo $PATH"])
    }

    // MARK: - SHELL allow-list

    func testDefaultShellURLAcceptsBinZsh() {
        let url = LoginShellPathExtractor.defaultShellURL(env: ["SHELL": "/bin/zsh"])
        XCTAssertEqual(url.path, "/bin/zsh")
    }

    func testDefaultShellURLRejectsTmpAndFallsBack() {
        let url = LoginShellPathExtractor.defaultShellURL(env: ["SHELL": "/tmp/evil"])
        XCTAssertEqual(url.path, "/bin/zsh")
    }

    func testDefaultShellURLRejectsRelativeAndFallsBack() {
        let url = LoginShellPathExtractor.defaultShellURL(env: ["SHELL": "zsh"])
        XCTAssertEqual(url.path, "/bin/zsh")
    }

    func testDefaultShellURLEmptyEnvFallsBack() {
        let url = LoginShellPathExtractor.defaultShellURL(env: [:])
        XCTAssertEqual(url.path, "/bin/zsh")
    }
}

private actor StubExecutor: ProcessExecuting {
    enum Outcome {
        case success(ProcessOutput)
        case failure(Error)
    }
    struct Call: Equatable {
        let executable: URL
        let arguments: [String]
    }

    private var outputs: [Outcome]
    private(set) var calls: [Call] = []

    init(outputs: [Outcome]) { self.outputs = outputs }

    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        calls.append(Call(executable: executable, arguments: arguments))
        guard !outputs.isEmpty else {
            throw ProcessExecutionError.launchFailed(reason: "stub exhausted")
        }
        switch outputs.removeFirst() {
        case .success(let out): return out
        case .failure(let err): throw err
        }
    }
}
