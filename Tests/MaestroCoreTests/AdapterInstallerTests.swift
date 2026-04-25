@testable import MaestroCore
import XCTest

final class AdapterInstallerTests: XCTestCase {
    func testInstallSpecsForKnownAdapters() {
        XCTAssertNotNil(AdapterInstaller.spec(for: "claude"))
        XCTAssertNotNil(AdapterInstaller.spec(for: "aider"))
        XCTAssertNil(AdapterInstaller.spec(for: "future-vendor"))
    }

    func testClaudeSpecUsesNpm() {
        let spec = AdapterInstaller.spec(for: "claude")!
        XCTAssertEqual(spec.packageManager, "npm")
        XCTAssertTrue(spec.installArguments.contains("@anthropic-ai/claude-code"))
        XCTAssertTrue(spec.installArguments.contains("install"))
        XCTAssertTrue(spec.installArguments.contains("-g"))
    }

    func testAiderSpecUsesPip() {
        let spec = AdapterInstaller.spec(for: "aider")!
        XCTAssertTrue(spec.packageManager == "pip" || spec.packageManager == "pip3")
        XCTAssertTrue(spec.installArguments.contains("aider-chat"))
    }

    func testInstallSucceedsWithStubExecutor() async throws {
        let stub = StubExecutor(outputs: [.success(
            ProcessOutput(stdout: "added 1 package", stderr: "", exitCode: 0)
        )])
        let installer = AdapterInstaller(
            packageManagerLocator: { _ in URL(fileURLWithPath: "/tmp/fake-npm") },
            executor: stub
        )
        let result = try await installer.install(adapterId: "claude")
        guard case .success = result else {
            XCTFail("expected success, got \(result)")
            return
        }
    }

    func testInstallFailsWhenPackageManagerMissing() async {
        let stub = StubExecutor(outputs: [])
        let installer = AdapterInstaller(
            packageManagerLocator: { _ in nil },
            executor: stub
        )
        do {
            _ = try await installer.install(adapterId: "claude")
            XCTFail("expected throw")
        } catch let AdapterInstallerError.packageManagerMissing(name) {
            XCTAssertEqual(name, "npm")
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testInstallFailsForUnknownAdapter() async {
        let stub = StubExecutor(outputs: [])
        let installer = AdapterInstaller(
            packageManagerLocator: { _ in URL(fileURLWithPath: "/tmp/x") },
            executor: stub
        )
        do {
            _ = try await installer.install(adapterId: "future-vendor")
            XCTFail("expected throw")
        } catch AdapterInstallerError.unsupportedAdapter {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testInstallReturnsFailedWhenExitNonZero() async throws {
        let stub = StubExecutor(outputs: [.success(
            ProcessOutput(stdout: "", stderr: "EACCES: permission denied", exitCode: 13)
        )])
        let installer = AdapterInstaller(
            packageManagerLocator: { _ in URL(fileURLWithPath: "/tmp/fake-npm") },
            executor: stub
        )
        let result = try await installer.install(adapterId: "claude")
        guard case .failed(let exitCode, let stderr) = result else {
            XCTFail("expected failed, got \(result)")
            return
        }
        XCTAssertEqual(exitCode, 13)
        XCTAssertTrue(stderr.contains("EACCES"))
    }
}

private actor StubExecutor: ProcessExecuting {
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
