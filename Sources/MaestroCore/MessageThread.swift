import Foundation

/// 연관된 `MessageEnvelope` 들의 묶음. 파일시스템에서는 `threads/<id>.jsonl` 로 저장.
///
/// - Note: 이름이 `Thread` 가 아니라 `MessageThread` 인 이유는 Foundation `Thread`
///   (POSIX 스레드 래퍼) 와 충돌을 피하기 위함이다. **Glossary 의 "Thread" 는 이
///   타입을 지칭한다.**
/// - Phase 11 `ThreadLogger` 가 모든 envelope 를 JSONL 로 append.
/// - Phase 12 UI 의 `ThreadView` 가 트리 구조 시각화.
public struct MessageThread: Codable, Hashable, Sendable, Identifiable {
    public let id: ThreadID
    public let parentId: ThreadID?
    public let title: String
    public let createdAt: Date
    public private(set) var messages: [MessageEnvelope]

    public init(
        id: ThreadID,
        parentId: ThreadID?,
        title: String,
        createdAt: Date,
        messages: [MessageEnvelope] = []
    ) {
        self.id = id
        self.parentId = parentId
        self.title = title
        self.createdAt = createdAt
        self.messages = messages
    }
}

public extension MessageThread {
    /// 봉투 추가. **봉투의 `threadId` 가 이 스레드와 일치해야 함** — 아니면 throws.
    ///
    /// 초기 설계에서 "관대한" non-strict append 도 제공했으나, phantom-typed ID 를
    /// 도입한 이유 자체가 "잘못된 ID 전달" 방지이므로 strict 만 유지하는 것이 일관.
    mutating func append(_ envelope: MessageEnvelope) throws {
        guard envelope.threadId == id else {
            throw MessageThreadError.foreignEnvelope(
                expected: id, found: envelope.threadId
            )
        }
        messages.append(envelope)
    }
}

public enum MessageThreadError: Error, Equatable {
    case foreignEnvelope(expected: ThreadID, found: ThreadID)
}
