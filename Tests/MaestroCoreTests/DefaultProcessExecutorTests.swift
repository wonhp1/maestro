import Foundation
@testable import MaestroCore
import XCTest

/// DefaultProcessExecutor 의 OS 경계 동작을 실제 프로세스로 검증.
/// 모든 macOS 시스템에 존재하는 /bin/echo, /bin/sh, /bin/sleep 사용.
final class DefaultProcessExecutorTests: XCTestCase {
    func testNormalExitCapturesStdoutAndExitCodeZero() async throws {
        let executor = DefaultProcessExecutor(timeout: 5)
        let output = try await executor.run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello"]
        )
        XCTAssertEqual(output.stdout, "hello\n")
        XCTAssertEqual(output.stderr, "")
        XCTAssertEqual(output.exitCode, 0)
    }

    func testNonZeroExitDoesNotThrow() async throws {
        let executor = DefaultProcessExecutor(timeout: 5)
        let output = try await executor.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo to-err 1>&2; exit 3"]
        )
        XCTAssertTrue(output.stderr.contains("to-err"))
        XCTAssertEqual(output.exitCode, 3)
    }

    func testLaunchFailureForMissingExecutable() async {
        let executor = DefaultProcessExecutor(timeout: 5)
        do {
            _ = try await executor.run(
                executable: URL(fileURLWithPath: "/no/such/binary/at/all"),
                arguments: []
            )
            XCTFail("expected launchFailed")
        } catch let err as ProcessExecutionError {
            if case .launchFailed = err { /* pass */ } else {
                XCTFail("wrong error: \(err)")
            }
        } catch {
            XCTFail("expected ProcessExecutionError: \(error)")
        }
    }

    func testTimeoutTriggersTermination() async throws {
        let executor = DefaultProcessExecutor(timeout: 0.3, gracePeriod: 0.5)
        let start = Date()
        do {
            _ = try await executor.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["10"]
            )
            XCTFail("expected timedOut")
        } catch ProcessExecutionError.timedOut {
            let elapsed = Date().timeIntervalSince(start)
            // SIGTERM 으로 sleep 은 즉시 죽음 → grace period 도달 전 종료. 2초 안엔 끝나야.
            XCTAssertLessThan(elapsed, 2.0, "timeout enforcement too slow: \(elapsed)s")
        } catch {
            XCTFail("expected timedOut, got \(error)")
        }
    }

    func testLargeOutputDoesNotDeadlockAndCapsBuffer() async throws {
        // ~256 KiB 출력 — 단일 pipe buffer (~16-64 KiB) 보다 훨씬 큼.
        // 동시 drain 이 없으면 자식이 write 차단되어 deadlock 됨.
        let cap = 64 * 1024
        let executor = DefaultProcessExecutor(timeout: 10, maxOutputBytes: cap)
        let output = try await executor.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 262144 /dev/zero | tr '\\0' 'A'"]
        )
        XCTAssertEqual(output.exitCode, 0)
        // cap 까지만 보관, 초과분 폐기.
        XCTAssertLessThanOrEqual(output.stdout.utf8.count, cap)
        XCTAssertGreaterThan(output.stdout.utf8.count, 1024, "drain too aggressive")
    }

    func testCancellationTerminatesChildAndThrowsCancellation() async throws {
        let executor = DefaultProcessExecutor(timeout: 30)
        let task = Task {
            try await executor.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"]
            )
        }
        // 짧게 기다린 뒤 cancel.
        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        let start = Date()
        do {
            _ = try await task.value
            XCTFail("expected cancellation to surface")
        } catch is CancellationError {
            // OK — Task cancel 자체가 surface 될 수도 있음
        } catch ProcessExecutionError.timedOut {
            // OK — 자식 정리되며 timedOut 으로 surface 가능
        } catch {
            // 다른 에러 — 자식이 정리되었는지 elapsed 로 검증.
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 5.0, "cancellation didn't kill child quickly: \(elapsed)s")
    }
}
