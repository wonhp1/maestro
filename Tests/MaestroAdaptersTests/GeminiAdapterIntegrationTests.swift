import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

/// v0.9.0 Phase 3 — 실제 Gemini CLI 로 end-to-end 검증.
///
/// 환경 사전 조건:
/// 1. `gemini` CLI 가 PATH 에 있음
/// 2. OAuth 또는 GEMINI_API_KEY (~/.gemini/oauth_creds.json 자동 생성)
final class GeminiAdapterIntegrationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestSupport.makeTempDirectory(named: "gemini-integration")
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempDir)
        super.tearDown()
    }

    func testRealGeminiSendMessageReturnsResponse() async throws {
        try skipIfGeminiUnavailable()

        let adapter = try GeminiAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)
        let env = MessageEnvelope.task(
            from: try AgentID.validated(rawValue: "user"),
            to: try AgentID.validated(rawValue: "gemini"),
            body: "Reply with exactly two words"
        )
        let response = try await adapter.sendMessage(env, in: session)
        XCTAssertFalse(response.body.isEmpty, "Gemini 응답이 비어있음")
        // session_id 캡처 검증
        let captured = await adapter.geminiSessionId(for: session.id)
        XCTAssertNotNil(captured)
        // 모델 캡처 검증 (init event 의 model 필드)
        let model = await adapter.resolvedModel(for: session)
        XCTAssertNotNil(model, "init 의 model 필드 캡처")
    }

    func testRealGeminiStreamMessage() async throws {
        try skipIfGeminiUnavailable()

        let adapter = try GeminiAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)
        let env = MessageEnvelope.task(
            from: try AgentID.validated(rawValue: "user"),
            to: try AgentID.validated(rawValue: "gemini"),
            body: "Reply with exactly 'streamed'"
        )
        var chunks: [ResponseChunk] = []
        for try await chunk in adapter.streamMessage(env, in: session) {
            chunks.append(chunk)
        }
        let texts = chunks.filter { $0.kind == .text }.map(\.content).joined()
        XCTAssertFalse(texts.isEmpty, "streaming text 비어있음")
        XCTAssertEqual(chunks.last?.kind, .completion)
    }

    private func skipIfGeminiUnavailable() throws {
        guard PATHExecutableLocator().locate("gemini") != nil else {
            throw XCTSkip("gemini CLI 미설치")
        }
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let creds = homeDir.appending(path: ".gemini/oauth_creds.json", directoryHint: .notDirectory)
        let hasOAuth = FileManager.default.fileExists(atPath: creds.path)
        let hasAPIKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]?.isEmpty == false
        guard hasOAuth || hasAPIKey else {
            throw XCTSkip("Gemini 인증 안 됨")
        }
    }
}
