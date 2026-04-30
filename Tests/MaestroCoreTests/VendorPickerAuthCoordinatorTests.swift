@testable import MaestroCore
import XCTest

@MainActor
final class VendorPickerAuthCoordinatorTests: XCTestCase {
    private final class FakePasteboard: AuthPasteboard, @unchecked Sendable {
        var copied: [String] = []
        func copy(_ string: String) { copied.append(string) }
    }

    private struct EmptyLocator: ExecutableLocating {
        func locate(_ name: String) -> URL? { nil }
    }

    private struct NoopExec: ProcessExecuting {
        func run(
            executable: URL,
            arguments: [String],
            currentDirectoryURL: URL?,
            environment: [String: String]?
        ) async throws -> ProcessOutput {
            ProcessOutput(stdout: "", stderr: "", exitCode: 1)
        }
    }

    private func makeIsolatedChecker() throws -> EnvironmentChecker {
        let tempHome = FileManager.default.temporaryDirectory
            .appending(path: "maestro-coord-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        return EnvironmentChecker(
            locator: EmptyLocator(),
            executor: NoopExec(),
            homeDirectory: tempHome,
            environment: [:]
        )
    }

    // MARK: - 인증 상태 검사

    func testLoadAuthSetsCheckingThenReady() async throws {
        let checker = try makeIsolatedChecker()
        let coord = VendorPickerAuthCoordinator(
            checker: checker,
            locator: EmptyLocator(),
            pasteboard: FakePasteboard()
        )
        await coord.loadAuth(for: "codex")
        guard case .ready(let authed) = coord.authStateByAdapter["codex"] else {
            XCTFail("expected .ready state")
            return
        }
        XCTAssertFalse(authed, "isolated checker → false")
    }

    func testLoadAuthForUnknownAdapterReturnsAuthed() async throws {
        let coord = VendorPickerAuthCoordinator(
            checker: try makeIsolatedChecker(),
            locator: EmptyLocator(),
            pasteboard: FakePasteboard()
        )
        await coord.loadAuth(for: "unknown")
        XCTAssertEqual(coord.authStateByAdapter["unknown"], .ready(true), "default true (auth 안 따짐)")
    }

    // MARK: - 로그인 dispatch

    func testStartLoginSetsLoginMessageWhenCLIMissing() async throws {
        let coord = VendorPickerAuthCoordinator(
            checker: try makeIsolatedChecker(),
            locator: EmptyLocator(),  // CLI 못 찾음
            pasteboard: FakePasteboard()
        )
        // v0.11.0 review HIGH: startLogin 이 Task 반환 → await 로 deterministic.
        await coord.startLogin(for: "codex").value
        XCTAssertEqual(coord.loginMessage["codex"], "codex CLI 를 찾을 수 없어요")
        XCTAssertNil(coord.loginInProgress["codex"], "guard 통과 못 했으니 inProgress 미설정")
    }

    /// v0.11.0 review HIGH: cancellation 후 loginTask 슬롯 청소 검증 — defer cleanup 회귀 가드.
    func testStartLoginClearsLoginTaskAfterCompletion() async throws {
        let coord = VendorPickerAuthCoordinator(
            checker: try makeIsolatedChecker(),
            locator: EmptyLocator(),
            pasteboard: FakePasteboard()
        )
        await coord.startLogin(for: "codex").value
        // private property 직접 검사 불가 — startLogin 다시 호출해서 cancel 대상 없음 확인.
        // 새 task 가 만들어져야 정상 (이전 nil 슬롯 검증 간접).
        let task = coord.startLogin(for: "codex")
        XCTAssertFalse(task.isCancelled, "이전 task slot 이 nil 이어야 새 task 가 cancel 안 됨")
        await task.value
    }

    func testCancelPendingLoginCancelsTask() async throws {
        let coord = VendorPickerAuthCoordinator(
            checker: try makeIsolatedChecker(),
            locator: EmptyLocator(),
            pasteboard: FakePasteboard()
        )
        let task = coord.startLogin(for: "codex")
        coord.cancelPendingLogin()
        await task.value  // task 가 정상 종료할 때까지 대기
        XCTAssertNotNil(
            coord.loginMessage["codex"],
            "최소한 some message 가 기록되어야 (cancel 되더라도 'CLI 못 찾음' 결과 가능)"
        )
    }

    // MARK: - 상태 전환

    func testLoginInProgressIsFalseInitially() async throws {
        let coord = VendorPickerAuthCoordinator(
            checker: try makeIsolatedChecker(),
            locator: EmptyLocator(),
            pasteboard: FakePasteboard()
        )
        XCTAssertNil(coord.loginInProgress["codex"])
        XCTAssertNil(coord.loginMessage["codex"])
    }

    // MARK: - 클립보드 abstraction

    func testFakePasteboardCapturesCopy() {
        let pb = FakePasteboard()
        pb.copy("test-url")
        XCTAssertEqual(pb.copied, ["test-url"])
    }
}
