import Foundation

/// `AgentID` → 활성 어댑터 + 세션 매핑. Router 가 dispatch 시 호출.
///
/// ## 책임 분리
/// 라우터 자체는 어댑터/세션을 어떻게 얻는지 모른다. 이 protocol 이 그 결정 로직을
/// 캡슐화 — 테스트에서는 stub 으로 임의 매핑, production 에서는 `AdapterRegistry` +
/// 세션 캐시를 결합한 구현체.
///
/// ## Sendable
/// Router 가 cross-actor 로 호출하므로 구현체는 Sendable. 보통 actor 또는 immutable.
public protocol AgentResolving: Sendable {
    /// 주어진 agent 의 활성 (adapter, session). 없으면 throws.
    func resolve(agent: AgentID) async throws -> ResolvedAgent
}

/// Router 가 dispatch 시 사용할 어댑터 + 세션 묶음.
public struct ResolvedAgent: Sendable {
    public let adapter: any AgentAdapter
    public let session: Session

    public init(adapter: any AgentAdapter, session: Session) {
        self.adapter = adapter
        self.session = session
    }
}

/// 테스트용 stub — 미리 등록된 매핑을 즉시 반환.
public actor StubAgentResolver: AgentResolving {
    private var registrations: [AgentID: ResolvedAgent] = [:]

    public init() {}

    public func register(_ agent: ResolvedAgent, for id: AgentID) {
        registrations[id] = agent
    }

    public func resolve(agent: AgentID) async throws -> ResolvedAgent {
        guard let resolved = registrations[agent] else {
            throw AgentResolverError.unknownAgent(id: agent)
        }
        return resolved
    }
}

public enum AgentResolverError: Error, Equatable, Sendable {
    case unknownAgent(id: AgentID)
}
