import Foundation

/// 연관된 `MessageEnvelope` 들의 묶음. 파일시스템에서는 `threads/<id>.jsonl` 로 저장.
///
/// - Note: 이름이 `Thread` 가 아니라 `MessageThread` 인 이유는 Foundation `Thread`
///   (POSIX 스레드 래퍼) 와 충돌을 피하기 위함이다. Glossary 의 "Thread" 는 이 타입을
///   지칭한다.
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
    /// 봉투를 추가. 봉투의 `threadId` 가 이 스레드와 일치하지 않으면 자동으로 조정하지 않는다 —
    /// 호출자가 책임진다. 엄격한 확인이 필요하면 `appendStrict(_:)` 사용.
    mutating func append(_ envelope: MessageEnvelope) {
        messages.append(envelope)
    }

    /// 봉투의 `threadId` 가 스레드 ID 와 일치하는 경우에만 추가. 아니면 throws.
    mutating func appendStrict(_ envelope: MessageEnvelope) throws {
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
