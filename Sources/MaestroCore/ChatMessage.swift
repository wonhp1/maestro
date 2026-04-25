import Foundation

/// UI 채팅 화면이 소비하는 단일 메시지 DTO.
///
/// `MessageEnvelope` 와 분리:
/// - Envelope = 디스크/와이어 단위 (영속성 + 라우팅 메타).
/// - ChatMessage = UI lifecycle 단위 (status: streaming/complete/failed, content 가변).
///
/// `id` 가 placeholder 로 emit 된 후, 스트리밍 chunk 가 도착할 때마다 같은 id 의 content 가 grow.
public struct ChatMessage: Identifiable, Hashable, Sendable {
    public enum Role: String, Codable, Hashable, Sendable, CaseIterable {
        case user
        case assistant
        /// 시스템 알림 / 에러 / 연결 상태 변화 — UI 가 다른 styling.
        case system
    }

    public enum Status: Hashable, Sendable {
        /// 사용자 메시지 — 전송 진행 중. 보통 한 turn 안에서 즉시 .complete.
        case sending
        /// 어시스턴트 응답 streaming 중 — content 가 grow.
        case streaming
        /// 정상 완료.
        case complete
        /// 사용자가 명시적으로 취소 — 에러가 아님 (Phase 8 must-fix).
        case cancelled
        /// 실패. 사용자에게 보일 짧은 사유.
        case failed(String)
    }

    public let id: UUID
    public let role: Role
    public var content: String
    public var status: Status
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        status: Status,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.status = status
        self.createdAt = createdAt
    }
}

public extension ChatMessage {
    /// 사용자가 입력한 메시지 — 즉시 .complete.
    static func user(_ body: String, at time: Date = Date()) -> ChatMessage {
        ChatMessage(role: .user, content: body, status: .complete, createdAt: time)
    }

    /// 어시스턴트의 streaming 시작 — 빈 content + .streaming.
    static func assistantPlaceholder(at time: Date = Date()) -> ChatMessage {
        ChatMessage(role: .assistant, content: "", status: .streaming, createdAt: time)
    }

    /// 시스템 알림.
    static func system(_ body: String, at time: Date = Date()) -> ChatMessage {
        ChatMessage(role: .system, content: body, status: .complete, createdAt: time)
    }
}
