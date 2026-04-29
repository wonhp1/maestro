import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

/// v0.9.0 Phase 2B — 실제 Codex CLI 로 end-to-end 검증.
///
/// 환경 사전 조건:
/// 1. `codex` CLI 가 PATH 에 있음
/// 2. OAuth 로그인 됨 (`codex login status` → "Logged in")
///
/// 위 조건 미충족 시 자동 skip — CI 가 깨지지 않도록.
final class CodexAdapterIntegrationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestSupport.makeTempDirectory(named: "codex-integration")
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempDir)
        super.tearDown()
    }

    /// 실 Codex 가 설치 + 인증된 환경에서만 실행. Mock 없이 실제 OpenAI API 호출.
    func testRealCodexSendMessageReturnsResponse() async throws {
        try skipIfCodexUnavailable()

        let adapter = try CodexAdapter()  // default executor / detector
        let session = try await adapter.createSession(folderPath: tempDir)
        let env = MessageEnvelope.task(
            from: try AgentID.validated(rawValue: "user"),
            to: try AgentID.validated(rawValue: "codex"),
            body: "Reply with exactly one word: 'integration-ok'"
        )

        let response = try await adapter.sendMessage(env, in: session)
        XCTAssertFalse(response.body.isEmpty, "Codex 응답이 비어있음")
        // 모델이 정확히 따르지 않을 수 있어 substring 만 검증
        XCTAssertTrue(
            response.body.lowercased().contains("integration") ||
            response.body.lowercased().contains("ok"),
            "응답에 핵심 키워드 없음: \(response.body)"
        )
        // thread_id 캡처 검증
        let threadId = await adapter.threadId(for: session.id)
        XCTAssertNotNil(threadId, "thread_id 캡처 안 됨")
        let initialized = await adapter.isInitialized(session.id)
        XCTAssertTrue(initialized)
    }

    /// 같은 세션 두 번째 호출이 resume 동작 + 같은 thread_id 유지 확인.
    /// 컨텍스트 의존 prompt 는 tool 호출 트리거 가능 (workspace-write sandbox) 로
    /// 시간 변동 큼 → 단순 echo prompt 로 thread_id 보존만 검증.
    func testRealCodexSecondCallUsesResume() async throws {
        try skipIfCodexUnavailable()

        let adapter = try CodexAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)

        let env1 = MessageEnvelope.task(
            from: try AgentID.validated(rawValue: "user"),
            to: try AgentID.validated(rawValue: "codex"),
            body: "Reply with exactly 'first'"
        )
        _ = try await adapter.sendMessage(env1, in: session)
        let firstThreadId = await adapter.threadId(for: session.id)
        XCTAssertNotNil(firstThreadId)
        let initialized = await adapter.isInitialized(session.id)
        XCTAssertTrue(initialized, "첫 호출 후 initialized")

        let env2 = MessageEnvelope.task(
            from: try AgentID.validated(rawValue: "user"),
            to: try AgentID.validated(rawValue: "codex"),
            body: "Reply with exactly 'second'"
        )
        _ = try await adapter.sendMessage(env2, in: session)
        // resume 가 정상 동작하면 같은 thread_id 유지
        let secondThreadId = await adapter.threadId(for: session.id)
        XCTAssertEqual(secondThreadId, firstThreadId, "resume 가 thread 보존")
    }

    // MARK: - Skip helper

    private func skipIfCodexUnavailable() throws {
        // codex CLI 존재 검사
        guard PATHExecutableLocator().locate("codex") != nil else {
            throw XCTSkip("codex CLI 미설치 — integration 테스트 skip")
        }
        // OAuth 또는 API key 검사
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let authPath = homeDir.appending(path: ".codex/auth.json", directoryHint: .notDirectory)
        let hasAuth = FileManager.default.fileExists(atPath: authPath.path)
        let hasAPIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.isEmpty == false
        guard hasAuth || hasAPIKey else {
            throw XCTSkip("Codex 인증 안 됨 (OAuth 또는 OPENAI_API_KEY 필요)")
        }
    }
}
