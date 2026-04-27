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
    /// v0.6.0 — let → var: `resume(addingTurns:)` 가 종료된 토론을 다시 active 로
    /// 살릴 때 maxTurns 를 늘림 (기본 동작은 init 후 변경 X — 신규 토론 동등).
    public internal(set) var maxTurns: Int
    public private(set) var state: DiscussionState
    public private(set) var turns: [DiscussionTurn]
    /// v0.5.0 — 참가자별 ephemeral subSession ID. 토론 발언이 자식의 메인 세션을
    /// 오염하지 않도록 격리. `DiscussionEngine.start` 가 채워넣고
    /// `DiscussionTurnDispatcher` 가 ClaudeAdapter 호출 시 사용.
    /// 옛 형식 디코딩 시 빈 dict.
    public private(set) var subSessions: [AgentID: SessionID]
    /// v0.5.0 — 사회자가 작성하고 사용자가 편집한 결론. nil 이면 아직 미작성.
    public var conclusion: String?
    /// v0.5.0 — 결론을 공유한 자식 에이전트 목록. nil 이면 아직 미공유.
    public private(set) var sharedWith: [AgentID]?
    /// v0.5.0 — 공유 시각. `sharedWith` 와 동시 set/clear.
    public private(set) var sharedAt: Date?

    public init(
        id: ThreadID,
        title: String,
        participants: [AgentID],
        moderatorId: AgentID?,
        maxTurns: Int,
        state: DiscussionState,
        turns: [DiscussionTurn],
        subSessions: [AgentID: SessionID] = [:],
        conclusion: String? = nil,
        sharedWith: [AgentID]? = nil,
        sharedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.participants = participants
        self.moderatorId = moderatorId
        self.maxTurns = maxTurns
        self.state = state
        self.turns = turns
        self.subSessions = subSessions
        self.conclusion = conclusion
        self.sharedWith = sharedWith
        self.sharedAt = sharedAt
    }

    // MARK: Codable — 옛 형식 (v0.4.x) 백워드 컴팩

    private enum CodingKeys: String, CodingKey {
        case id, title, participants, moderatorId, maxTurns, state, turns
        case subSessions, conclusion, sharedWith, sharedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(ThreadID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.participants = try c.decode([AgentID].self, forKey: .participants)
        self.moderatorId = try c.decodeIfPresent(AgentID.self, forKey: .moderatorId)
        self.maxTurns = try c.decode(Int.self, forKey: .maxTurns)
        self.state = try c.decode(DiscussionState.self, forKey: .state)
        self.turns = try c.decode([DiscussionTurn].self, forKey: .turns)
        // v0.5.0 신규 필드 — 옛 형식엔 없음. 빈 dict / nil 으로 폴백.
        self.subSessions = try c.decodeIfPresent(
            [AgentID: SessionID].self, forKey: .subSessions
        ) ?? [:]
        self.conclusion = try c.decodeIfPresent(String.self, forKey: .conclusion)
        self.sharedWith = try c.decodeIfPresent([AgentID].self, forKey: .sharedWith)
        self.sharedAt = try c.decodeIfPresent(Date.self, forKey: .sharedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(participants, forKey: .participants)
        try c.encodeIfPresent(moderatorId, forKey: .moderatorId)
        try c.encode(maxTurns, forKey: .maxTurns)
        try c.encode(state, forKey: .state)
        try c.encode(turns, forKey: .turns)
        // 빈 dict 도 명시 — round-trip 보존.
        try c.encode(subSessions, forKey: .subSessions)
        try c.encodeIfPresent(conclusion, forKey: .conclusion)
        try c.encodeIfPresent(sharedWith, forKey: .sharedWith)
        try c.encodeIfPresent(sharedAt, forKey: .sharedAt)
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

    // MARK: v0.5.0 — subSessions / conclusion / sharing helpers

    /// 참가자에게 ephemeral subSessionID 할당. `DiscussionEngine.start` 가 호출.
    /// 같은 agent 에 다시 할당하면 덮어씀 (재시작 시 새 격리).
    mutating func assignSubSession(_ session: SessionID, for agent: AgentID) {
        subSessions[agent] = session
    }

    /// 사회자/사용자가 작성한 결론 set.
    mutating func setConclusion(_ text: String) {
        conclusion = text
    }

    /// 결론을 자식들에게 공유했음을 기록. 실제 자식 메인 세션 typing 은
    /// `DiscussionEngine.share(targets:)` 가 처리.
    mutating func markShared(with targets: [AgentID], at time: Date) {
        sharedWith = targets
        sharedAt = time
    }

    /// v0.6.0 — 종료된 토론을 다시 active 로. 사용자가 명시적으로 resume 의도
    /// 트리거. **별도 method** 로 분리해 일반 `transition(to:)` 매트릭스 보존
    /// (옛 testAllInvalidTransitions 깨지지 않게).
    /// - completed/paused → active. addingTurns 만큼 maxTurns 늘림.
    /// - aborted 는 영구 종료 — throws (사용자가 의도적으로 abort 한 토론은
    ///   부활시키지 않음. 새 토론으로 시작 권장).
    /// - active/pending 에서 호출은 의미 X — throws.
    /// - addingTurns 0 도 OK (paused → active 만 원할 때).
    mutating func resume(addingTurns extra: Int) throws {
        switch state {
        case .completed:
            // /team review LOW — completed 에서 extra=0 면 즉시 또 completed 로
            // re-entry 하며 spurious .terminated 이벤트 발행. 명시적 reject.
            guard extra > 0 else {
                throw DiscussionError.cannotResume(
                    reason: "completed 토론은 addingTurns > 0 필요 (현재 \(turns.count)/\(maxTurns) 도달)."
                )
            }
        case .paused:
            // paused 는 turns.count < maxTurns 가능 → extra=0 도 의미 (단순 unpause).
            guard extra >= 0 else {
                throw DiscussionError.cannotResume(reason: "addingTurns 음수 불가.")
            }
        case .aborted:
            throw DiscussionError.cannotResume(reason: "abort 된 토론은 재개 불가 — 새 토론으로 시작하세요.")
        case .active, .pending:
            throw DiscussionError.cannotResume(reason: "이미 진행 가능한 상태 (\(state)) — resume 불요.")
        }
        state = .active
        maxTurns += extra
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
    /// v0.6.0 — `resume(addingTurns:)` 가 거부.
    case cannotResume(reason: String)
}
