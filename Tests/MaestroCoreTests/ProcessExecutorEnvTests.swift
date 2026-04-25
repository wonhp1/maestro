import Foundation
@testable import MaestroCore
import XCTest

/// Phase 6: ProcessExecuting.run 의 environment 매개변수 (collected exec) 검증.
final class ProcessExecutorEnvTests: XCTestCase {
    func testCustomEnvironmentInheritedByChild() async throws {
        let executor = DefaultProcessExecutor(timeout: 5)
        let output = try await executor.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo $MAESTRO_EXEC_TEST"],
            currentDirectoryURL: nil,
            environment: ["MAESTRO_EXEC_TEST": "ok", "PATH": "/bin:/usr/bin"]
        )
        XCTAssertEqual(output.stdout, "ok\n")
        XCTAssertEqual(output.exitCode, 0)
    }

    func testNilEnvironmentInheritsParent() async throws {
        // 부모 env 에 sentinel 추가 → 자식이 그대로 받음.
        setenv("MAESTRO_PARENT_INHERIT", "yes", 1)
        defer { unsetenv("MAESTRO_PARENT_INHERIT") }
        let executor = DefaultProcessExecutor(timeout: 5)
        let output = try await executor.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo $MAESTRO_PARENT_INHERIT"]
        )
        XCTAssertEqual(output.stdout, "yes\n")
    }

    /// Phase 6 must-fix: sanitization 과 cwd 가 동시에 정상 적용.
    func testSanitizedEnvironmentWithCustomCwd() async throws {
        setenv("ANTHROPIC_API_KEY", "secret-x", 1)
        defer { unsetenv("ANTHROPIC_API_KEY") }
        let executor = DefaultProcessExecutor(timeout: 5)
        let cleaned = EnvironmentSanitizer.default.sanitizedProcessEnvironment()
        let tempDir = FileManager.default.temporaryDirectory
        let output = try await executor.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "pwd; echo k=${ANTHROPIC_API_KEY:-MISSING}"],
            currentDirectoryURL: tempDir,
            environment: cleaned
        )
        let lines = output.stdout.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        // pwd 는 macOS canonicalization 영향 — resolveSymlinks 후 비교.
        let pwdResolved = URL(fileURLWithPath: lines[0]).resolvingSymlinksInPath().path
        XCTAssertEqual(pwdResolved, tempDir.resolvingSymlinksInPath().path)
        XCTAssertEqual(lines[1], "k=MISSING")
    }

    func testSanitizedEnvironmentBlocksSecret() async throws {
        setenv("ANTHROPIC_API_KEY", "leak-me-please", 1)
        defer { unsetenv("ANTHROPIC_API_KEY") }
        let executor = DefaultProcessExecutor(timeout: 5)
        let cleaned = EnvironmentSanitizer.default.sanitizedProcessEnvironment()
        let output = try await executor.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo \"k=${ANTHROPIC_API_KEY:-MISSING}\""],
            currentDirectoryURL: nil,
            environment: cleaned
        )
        XCTAssertEqual(output.stdout, "k=MISSING\n")
    }
}
