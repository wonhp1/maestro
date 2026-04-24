import Foundation

/// 에이전트 간 메시지의 "봉투". 모든 에이전트 간 통신의 기본 단위.
///
/// 봉투는 **불변** — 수정 시 새 봉투를 만든다. 반드시 `threadId` 에 귀속되며,
/// `inReplyTo` 로 이전 봉투를 참조해 대화 트리를 구성한다.
public struct MessageEnvelope: Codable, Hashable, Sendable, Identifiable {
    /// 봉투 고유 식별자.
    public let id: EnvelopeID

    /// 이 봉투가 속한 스레드.
    public let threadId: ThreadID

    /// 응답의 경우 원본 봉투의 ID. 루트 메시지면 `nil`.
    public let inReplyTo: EnvelopeID?

    /// 발신 에이전트.
    public let from: AgentID

    /// 수신 에이전트.
    public let to: AgentID

    /// 메시지 목적 분류.
    public let type: MessageType

    /// 메시지 본문 (Markdown 허용).
    public let body: String

    /// 생성 시각.
    public let createdAt: Date

    /// 응답을 기대하는가. `false` 이면 발신자는 응답 없이도 진행 가능.
    public let expectReply: Bool

    public init(
        id: EnvelopeID,
        threadId: ThreadID,
        inReplyTo: EnvelopeID?,
        from: AgentID,
        to: AgentID,
        type: MessageType,
        body: String,
        createdAt: Date,
        expectReply: Bool
    ) {
        self.id = id
        self.threadId = threadId
        self.inReplyTo = inReplyTo
        self.from = from
        self.to = to
        self.type = type
        self.body = body
        self.createdAt = createdAt
        self.expectReply = expectReply
    }
}

// MARK: - Factories

public extension MessageEnvelope {
    /// 새 스레드의 루트 task 메시지를 생성.
    static func task(
        from: AgentID,
        to: AgentID,
        body: String,
        thread: ThreadID = .new(),
        now: Date = Date()
    ) -> MessageEnvelope {
        MessageEnvelope(
            id: .new(),
            threadId: thread,
            inReplyTo: nil,
            from: from,
            to: to,
            type: .task,
            body: body,
            createdAt: now,
            expectReply: true
        )
    }

    /// 이전 봉투에 대한 report 응답 생성. `to`/`from` 은 자동 반전.
    static func report(
        from: AgentID,
        inReplyTo original: MessageEnvelope,
        body: String,
        now: Date = Date()
    ) -> MessageEnvelope {
        MessageEnvelope(
            id: .new(),
            threadId: original.threadId,
            inReplyTo: original.id,
            from: from,
            to: original.from,
            type: .report,
            body: body,
            createdAt: now,
            expectReply: false
        )
    }

    /// 특정 필드만 교체한 새 봉투 생성 (불변 업데이트).
    func with(threadId: ThreadID) -> MessageEnvelope {
        MessageEnvelope(
            id: id,
            threadId: threadId,
            inReplyTo: inReplyTo,
            from: from,
            to: to,
            type: type,
            body: body,
            createdAt: createdAt,
            expectReply: expectReply
        )
    }
}
