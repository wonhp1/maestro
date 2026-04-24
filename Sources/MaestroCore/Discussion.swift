import Foundation

/// 여러 에이전트가 참여하는 구조화된 토론. `MessageThread` 의 특수형.
///
/// - ID 는 `ThreadID` — 토론도 결국 스레드다. 단, 참여자/규칙/상태머신이 추가.
/// - `moderatorId` 는 발언자 순서를 결정하는 에이전트 (없으면 단순 라운드 로빈).
/// - Phase 14 `DiscussionEngine` 이 이 타입을 소비, Phase 15 UI 가 렌더링.
public struct Discussion: Codable, Hashable, Sendable, Identifiable {
    public let id: ThreadID
    public let title: String
    public let participants: [AgentID]
    public let moderatorId: AgentID?
    public let maxTurns: Int
    public private(set) var state: DiscussionState
    public private(set) var turns: [DiscussionTurn]

    public init(
        id: ThreadID,
        title: String,
        participants: [AgentID],
        moderatorId: AgentID?,
        maxTurns: Int,
        state: DiscussionState,
        turns: [DiscussionTurn]
    ) {
        self.id = id
        self.title = title
        self.participants = participants
        self.moderatorId = moderatorId
        self.maxTurns = maxTurns
        self.state = state
        self.turns = turns
    }
}

public extension Discussion {
    /// 상태 전이.
    mutating func transition(to target: DiscussionState) throws {
        guard state.canTransition(to: target) else {
            throw DiscussionError.invalidTransition(from: state, to: target)
        }
        state = target
    }

    /// 봉투로부터 턴 기록. 봉투의 `threadId` 가 이 토론의 ID 와 일치해야 하며,
    /// 발신자가 참가자 목록에 있어야 한다. `maxTurns` 도달 시 `.completed` 자동 전이.
    mutating func recordTurn(from envelope: MessageEnvelope) throws {
        guard envelope.threadId == id else {
            throw DiscussionError.foreignEnvelope(expected: id, found: envelope.threadId)
        }
        try recordTurn(
            speaker: envelope.from,
            envelopeId: envelope.id,
            at: envelope.createdAt
        )
    }

    /// 저수준 턴 기록. 일반적으론 `recordTurn(from:)` 을 사용.
    ///
    /// - `state` 가 `.active` 가 아니면 throws.
    /// - `speaker` 가 `participants` 에 없으면 throws.
    /// - `turnIndex` 는 단조 증가.
    /// - `turns.count >= maxTurns` 도달 시 `.completed` 로 전이.
    mutating func recordTurn(
        speaker: AgentID,
        envelopeId: EnvelopeID,
        at time: Date
    ) throws {
        guard state == .active else {
            throw DiscussionError.notActive(currentState: state)
        }
        guard participants.contains(speaker) else {
            throw DiscussionError.notAParticipant(speaker: speaker)
        }
        let turn = DiscussionTurn(
            turnIndex: turns.count,
            speaker: speaker,
            envelopeId: envelopeId,
            timestamp: time
        )
        turns.append(turn)

        if turns.count >= maxTurns {
            state = .completed
        }
    }
}

/// 토론의 수명 상태.
///
/// 전이 매트릭스:
/// ```
///             →pending  →active  →paused  →completed  →aborted
/// pending        ✗          ✓        ✗        ✗          ✓
/// active         ✗          ✗        ✓        ✓          ✓
/// paused         ✗          ✓        ✗        ✓          ✓
/// completed      ✗          ✗        ✗        ✗          ✗  (terminal)
/// aborted        ✗          ✗        ✗        ✗          ✗  (terminal)
/// ```
public enum DiscussionState: String, Codable, Hashable, Sendable, CaseIterable {
    /// 생성되었으나 아직 시작 전.
    case pending
    /// 진행 중 — 턴 기록 가능.
    case active
    /// 사람이 개입 대기시킴. 다시 `.active` 로 복귀 가능.
    case paused
    /// 정상 종료. 추가 턴 불가.
    case completed
    /// 비정상 종료. 추가 턴 불가.
    case aborted
}

extension DiscussionState {
    func canTransition(to target: DiscussionState) -> Bool {
        switch (self, target) {
        case (.pending, .active), (.pending, .aborted):
            return true
        case (.active, .paused), (.active, .completed), (.active, .aborted):
            return true
        case (.paused, .active), (.paused, .aborted), (.paused, .completed):
            return true
        case (.completed, _), (.aborted, _):
            return false  // terminal
        default:
            return false
        }
    }
}

/// 한 턴의 메타데이터.
public struct DiscussionTurn: Codable, Hashable, Sendable {
    public let turnIndex: Int
    public let speaker: AgentID
    public let envelopeId: EnvelopeID
    public let timestamp: Date

    public init(turnIndex: Int, speaker: AgentID, envelopeId: EnvelopeID, timestamp: Date) {
        self.turnIndex = turnIndex
        self.speaker = speaker
        self.envelopeId = envelopeId
        self.timestamp = timestamp
    }
}

public enum DiscussionError: Error, Equatable {
    case invalidTransition(from: DiscussionState, to: DiscussionState)
    case notActive(currentState: DiscussionState)
    case notAParticipant(speaker: AgentID)
    case foreignEnvelope(expected: ThreadID, found: ThreadID)
}
