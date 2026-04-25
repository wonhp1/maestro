import Foundation
import Observation

/// "+ 새 토론" 시트의 입력 상태 + 검증 + 시작 액션을 보유한 @Observable.
///
/// ## 책임
/// - 사용자 입력 (주제 / 참가자 / moderator 전략 / maxTurns) 누적
/// - `canStart` 로 폼 유효성 노출 (UI 가 "시작" 버튼 disabled binding)
/// - `start()` 호출 시 `DiscussionStartAction` 실행 — 실제 engine spawn 은 환경 책임
///
/// ## 동시성
/// `@MainActor` — UI input. `startAction` 은 비동기 throws, 실패 시 errorMessage set.
@MainActor
@Observable
public final class DiscussionStartViewModel {
    public var topic: String = ""
    public var selectedParticipants: Set<AgentID> = []
    public var moderatorChoice: ModeratorChoice = .roundRobin
    public var maxTurns: Int = DiscussionStartViewModel.defaultMaxTurns
    public var errorMessage: String?

    public let availableParticipants: [DiscussionParticipantOption]

    @ObservationIgnored
    private let startAction: @MainActor (DiscussionStartRequest) async throws -> ThreadID

    public init(
        availableParticipants: [DiscussionParticipantOption],
        startAction: @escaping @MainActor (DiscussionStartRequest) async throws -> ThreadID
    ) {
        self.availableParticipants = availableParticipants
        self.startAction = startAction
    }

    /// 폼이 시작 가능한 상태인지. 주제 비어있지 않고 참가자 ≥ 2.
    public var canStart: Bool {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && selectedParticipants.count >= 2
    }

    /// `maxTurns` 를 합리 범위로 클램프 — UI slider 가 그대로 표시.
    public var clampedMaxTurns: Int {
        min(Self.maxMaxTurns, max(Self.minMaxTurns, maxTurns))
    }

    /// 토론 시작. 유효성 통과 시 startAction 호출 → 새 ThreadID 반환.
    /// 실패 시 errorMessage set 후 throws.
    @discardableResult
    public func start() async throws -> ThreadID {
        guard canStart else {
            errorMessage = "주제와 참가자 (최소 2명) 가 필요합니다."
            throw DiscussionStartError.invalidInput
        }
        errorMessage = nil
        let request = DiscussionStartRequest(
            topic: topic.trimmingCharacters(in: .whitespacesAndNewlines),
            participants: Array(selectedParticipants),
            moderatorChoice: moderatorChoice,
            maxTurns: clampedMaxTurns
        )
        do {
            return try await startAction(request)
        } catch {
            errorMessage = "토론 시작 실패: \(error.localizedDescription)"
            throw error
        }
    }

    public static let minMaxTurns: Int = 4
    public static let maxMaxTurns: Int = 100
    public static let defaultMaxTurns: Int = 20
}

/// 사용자가 선택할 수 있는 참가자 한 옵션 — 폴더 → 합성된 AgentID 와 displayName.
public struct DiscussionParticipantOption: Equatable, Hashable, Sendable, Identifiable {
    public let agentId: AgentID
    public let displayName: String

    public init(agentId: AgentID, displayName: String) {
        self.agentId = agentId
        self.displayName = displayName
    }

    public var id: AgentID { agentId }
}

/// moderator 전략 선택지 — UI segmented control 옵션.
public enum ModeratorChoice: Equatable, Sendable {
    case roundRobin
    case random
    /// LLM moderator — 어떤 에이전트가 moderator 역할을 할지 명시. 보통 control 폴더.
    case llm(controlAgentId: AgentID)
}

/// 시작 시점에 viewModel 이 만들어 startAction 으로 전달하는 값 객체.
public struct DiscussionStartRequest: Equatable, Sendable {
    public let topic: String
    public let participants: [AgentID]
    public let moderatorChoice: ModeratorChoice
    public let maxTurns: Int

    public init(
        topic: String,
        participants: [AgentID],
        moderatorChoice: ModeratorChoice,
        maxTurns: Int
    ) {
        self.topic = topic
        self.participants = participants
        self.moderatorChoice = moderatorChoice
        self.maxTurns = maxTurns
    }
}

public enum DiscussionStartError: Error, Equatable, Sendable {
    case invalidInput
}
