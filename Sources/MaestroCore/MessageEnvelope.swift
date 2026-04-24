import Foundation

/// 에이전트 간 메시지의 "봉투". **Envelope Protocol 의 디스크/와이어 단위**.
///
/// ## Envelope Protocol (Glossary 참조)
/// 이 타입은 **단순 DTO 가 아니라 파일시스템 기반 메시지 큐의 레코드**.
/// - `inbox/<agent>/<envelope-id>.json` 에 JSON 으로 drop.
/// - Phase 11 `EnvelopeRouter` 가 감시 → 어댑터 호출 → `outbox/<sender>/` 로 응답 append.
/// - `threads/<thread-id>.jsonl` 에 전체 이력 보관.
/// - 봉투는 **불변** — 수정 시 새 봉투를 만든다.
///
/// ## 스키마 진화
/// `schemaVersion` 은 디스크 포맷 마이그레이션 (Phase 23) 의 앵커.
/// 버전 증가 시 `Migrator` 체인이 자동 업그레이드. 현재 `1`.
///
/// ## 신뢰성 필드
/// - `correlationId`: 재전송/중복 감지. 동일 의도의 봉투는 같은 값 유지.
/// - `deliveryStatus`: Phase 11 라우터가 갱신 (`pending → delivered/failed`).
///   실패 시 `failed/` DLQ 로 이동.
public struct MessageEnvelope: Codable, Hashable, Sendable, Identifiable {
    /// 디스크 포맷 버전. Phase 23 `Migrator` 체인의 앵커.
    public let schemaVersion: Int

    /// 봉투 고유 식별자.
    public let id: EnvelopeID

    /// 이 봉투가 속한 스레드.
    public let threadId: ThreadID

    /// 응답의 경우 원본 봉투의 ID. 루트 메시지면 `nil`.
    public let inReplyTo: EnvelopeID?

    /// 재전송/중복 감지 키. 기본은 `id.rawValue` 와 동일.
    ///
    /// - Phase 11 `InboxWatcher` 가 restart+replay 시 이 값으로 중복 디스패치 회피.
    /// - 의도적 재시도는 같은 correlationId 로 새 봉투 생성.
    public let correlationId: String

    /// 발신 에이전트.
    public let from: AgentID

    /// 수신 에이전트.
    public let to: AgentID

    /// 메시지 목적 분류.
    public let type: MessageType

    /// 메시지 본문 (Markdown 허용).
    ///
    /// - Warning: **시크릿 금지** — 이 값은 `threads/*.jsonl` 에 평문으로 누적.
    ///   API 키, 토큰은 반드시 Keychain 으로 (Phase 3, 19).
    public let body: String

    /// 생성 시각.
    public let createdAt: Date

    /// 응답을 기대하는가.
    ///
    /// - 관례: `task`/`question` → `true`, `report`/`fyi` → `false`.
    /// - Phase 13 `DispatchService` 가 이 값으로 inbox 대기 여부 결정.
    /// - 호출자가 명시적으로 지정하면 관례를 override.
    public let expectReply: Bool

    /// Phase 11 라우팅 상태. 생성 시 `.pending` 기본값.
    public var deliveryStatus: DeliveryStatus

    public init(
        id: EnvelopeID,
        threadId: ThreadID,
        inReplyTo: EnvelopeID?,
        from: AgentID,
        to: AgentID,
        type: MessageType,
        body: String,
        createdAt: Date,
        expectReply: Bool,
        correlationId: String? = nil,
        deliveryStatus: DeliveryStatus = .pending,
        schemaVersion: Int = MessageEnvelope.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.threadId = threadId
        self.inReplyTo = inReplyTo
        self.correlationId = correlationId ?? id.rawValue
        self.from = from
        self.to = to
        self.type = type
        self.body = body
        self.createdAt = createdAt
        self.expectReply = expectReply
        self.deliveryStatus = deliveryStatus
    }

    /// 현재 디스크 포맷 버전. 스키마 변경 시 bump.
    public static let currentSchemaVersion: Int = 1
}

/// 봉투 라우팅 상태. 디스크에 영속된 이후 Phase 11 `EnvelopeRouter` 가 갱신.
public enum DeliveryStatus: String, Codable, Hashable, Sendable, CaseIterable {
    /// 생성됨, 아직 라우팅 전.
    case pending
    /// 타겟 어댑터로 전달 완료. 응답 대기 중 or fire-and-forget.
    case delivered
    /// 응답 수신 완료 (report/report-style 대응 봉투 도착).
    case acknowledged
    /// 라우팅 실패. `failed/` DLQ 로 이동한 상태.
    case failed
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
            expectReply: expectReply,
            correlationId: correlationId,
            deliveryStatus: deliveryStatus,
            schemaVersion: schemaVersion
        )
    }

    /// 라우팅 상태를 교체한 새 봉투.
    func with(deliveryStatus: DeliveryStatus) -> MessageEnvelope {
        MessageEnvelope(
            id: id,
            threadId: threadId,
            inReplyTo: inReplyTo,
            from: from,
            to: to,
            type: type,
            body: body,
            createdAt: createdAt,
            expectReply: expectReply,
            correlationId: correlationId,
            deliveryStatus: deliveryStatus,
            schemaVersion: schemaVersion
        )
    }
}
