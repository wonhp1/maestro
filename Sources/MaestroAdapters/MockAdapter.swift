import Foundation
import MaestroCore

/// 테스트/UI 미리보기 전용 어댑터. 실제 외부 프로세스를 띄우지 않고 메모리에서 동작.
///
/// 사용 패턴:
/// - 테스트에서 `AdapterRegistry` 등록해 dispatch / orchestration 시뮬레이션
/// - SwiftUI 프리뷰에서 가짜 응답 표시
///
/// 동작 커스터마이징은 init 의 closure 들로 주입. 기본은 echo (들어온 body 를
/// "[Mock <id>] <body>" 로 회신).
public actor MockAdapter: AgentAdapter {
    public static let id: String = "mock"
    public static let displayName: String = "Mock Agent"
    public static let iconName: String = "ant"

    /// 현재 살아있는 세션 — id → Session.
    public private(set) var sessions: [SessionID: Session] = [:]
    /// 누적 처리한 envelope 수 (테스트 어설션용).
    public private(set) var processedCount: Int = 0
    /// `detect()` 가 반환할 값. nil 이면 기본 (`isInstalled=true`, version "0.0.0-mock").
    public var detectionOverride: AdapterDetection?
    /// `sendMessage` 가 받은 envelope → 응답 envelope 변환 hook. nil 이면 echo.
    public var responder: (@Sendable (MessageEnvelope, Session) -> MessageEnvelope)?
    /// `listSlashCommands` 가 반환할 명령 카탈로그.
    public var slashCommands: [SlashCommand]

    public init(
        slashCommands: [SlashCommand] = [],
        detectionOverride: AdapterDetection? = nil,
        responder: (@Sendable (MessageEnvelope, Session) -> MessageEnvelope)? = nil
    ) {
        self.slashCommands = slashCommands
        self.detectionOverride = detectionOverride
        self.responder = responder
    }

    public func detect() async -> AdapterDetection {
        if let override = detectionOverride { return override }
        // executablePath = nil — Mock 은 가상 어댑터이므로 실재하지 않는 경로 노출 금지
        // (Phase 4 must-fix: 다운스트림이 fileExists 로 false negative 받지 않도록).
        return AdapterDetection(
            isInstalled: true,
            version: "0.0.0-mock",
            executablePath: nil,
            detectedAt: Date()
        )
    }

    public func createSession(folderPath: URL) async throws -> Session {
        let agentId = try AgentID.validated(rawValue: "mock-agent")
        let sessionId = SessionID.new()
        let adapterId = try AdapterID.validated(rawValue: Self.id)
        let now = Date()
        let session = Session(
            id: sessionId,
            agentId: agentId,
            adapterId: adapterId,
            folderPath: folderPath,
            createdAt: now,
            lastActivityAt: now,
            status: .active
        )
        sessions[sessionId] = session
        return session
    }

    public func destroySession(_ id: SessionID) async throws {
        guard sessions.removeValue(forKey: id) != nil else {
            throw AdapterError.unknownSession(id: id)
        }
    }

    public func sendMessage(
        _ envelope: MessageEnvelope,
        in session: Session
    ) async throws -> MessageEnvelope {
        guard sessions[session.id] != nil else {
            throw AdapterError.unknownSession(id: session.id)
        }
        processedCount += 1
        if let responder = responder {
            return responder(envelope, session)
        }
        return MessageEnvelope.report(
            from: envelope.to,
            inReplyTo: envelope,
            body: "[Mock \(Self.id)] \(envelope.body)"
        )
    }

    public func listSlashCommands(in session: Session) async -> [SlashCommand] {
        slashCommands
    }
}
