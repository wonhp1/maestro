import Foundation

/// 토론에서 다음 발언자를 결정하는 전략.
///
/// ## 의미론
/// `nextSpeaker` 는 현재 토론 상태를 받고 다음에 발언할 에이전트를 반환.
/// `nil` 반환은 **종료 신호** — `DiscussionEngine` 이 `.completed` 로 전이.
///
/// ## 구현체 (Phase 14)
/// - `RoundRobinModerator`: 참가자 목록을 순환. moderator 자신은 skip.
/// - `RandomModerator`: 균등 random. 같은 사람 두 번 연속 가능.
/// - `LLMModeratorStrategy`: Phase 14+ — Claude 등 LLM 에게 다음 발언자 묻기 (defer).
///
/// ## Sendable
/// 전략은 immutable struct 또는 actor — `DiscussionEngine` 이 cross-actor 호출.
public protocol ModeratorStrategy: Sendable {
    /// 다음 발언자 결정. 종료 시 nil.
    /// - Parameter discussion: 현재 상태 (turns / participants / state).
    func nextSpeaker(in discussion: Discussion) async -> AgentID?
}

/// 라운드로빈 — 참가자 목록을 순환. moderator 가 지정되어 있으면 그를 skip.
///
/// 첫 호출은 첫 참가자부터. 이후는 `discussion.turns.last?.speaker` 다음 인덱스.
public struct RoundRobinModerator: ModeratorStrategy {
    public init() {}

    public func nextSpeaker(in discussion: Discussion) async -> AgentID? {
        let speakers = eligibleSpeakers(in: discussion)
        guard !speakers.isEmpty else { return nil }
        guard let lastSpeaker = discussion.turns.last?.speaker else {
            return speakers.first
        }
        if let lastIdx = speakers.firstIndex(of: lastSpeaker) {
            let nextIdx = (lastIdx + 1) % speakers.count
            return speakers[nextIdx]
        }
        // 직전 발언자가 eligible 목록에서 제거된 경우 — 첫 사람부터 재시작.
        return speakers.first
    }

    private func eligibleSpeakers(in discussion: Discussion) -> [AgentID] {
        guard let moderator = discussion.moderatorId else {
            return discussion.participants
        }
        return discussion.participants.filter { $0 != moderator }
    }
}

/// 균등 random — 직전 발언자도 다시 뽑힐 수 있음.
public struct RandomModerator: ModeratorStrategy {
    public init() {}

    public func nextSpeaker(in discussion: Discussion) async -> AgentID? {
        let pool = discussion.moderatorId.map { mod in
            discussion.participants.filter { $0 != mod }
        } ?? discussion.participants
        return pool.randomElement()
    }
}

/// 테스트용 미리 정해진 순서 — 결정론적.
public actor ScriptedModerator: ModeratorStrategy {
    private var schedule: [AgentID]

    public init(schedule: [AgentID]) {
        self.schedule = schedule
    }

    public func nextSpeaker(in discussion: Discussion) async -> AgentID? {
        guard !schedule.isEmpty else { return nil }
        return schedule.removeFirst()
    }
}
