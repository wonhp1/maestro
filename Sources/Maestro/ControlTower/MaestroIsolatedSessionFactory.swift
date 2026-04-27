import MaestroCore
import SwiftUI

/// `IsolatedSessionFactory` production 구현 — `FolderViewModel` + `AdapterRegistry`
/// 결합으로 토론 격리용 ephemeral 세션을 만든다.
///
/// ## 동작
/// 1. agent (예: `agent-{uuid}`) 를 `FolderViewModel` 에서 매칭되는 `FolderRegistration`
///    으로 역해석.
/// 2. 폴더의 `adapterId` 로 `AdapterRegistry.adapter(for:)` 어댑터 lookup.
/// 3. `adapter.createSession(folderPath:preferredSessionId: subSessionId)` 호출 —
///    어댑터가 ephemeral SessionID 로 새 세션 spawn (또는 같은 ID 로 `--resume`).
/// 4. `ResolvedAgent { adapter, session }` 반환.
///
/// 자식의 메인 ChatViewModel 세션 (`ChatSessionStore` 캐시) 은 절대 건드리지 않음 —
/// 토론 발언이 자식의 일반 채팅 컨텍스트 오염되는 문제 (v0.4.x) 의 근본 해결.
///
/// ## 동시성
/// `@MainActor` — `FolderViewModel.folders` 접근에 hop 필요. nonisolated 메서드는
/// MainActor.run 으로 lookup.
@MainActor
final class MaestroIsolatedSessionFactory: IsolatedSessionFactory {
    private let folderViewModel: FolderViewModel
    private let adapterRegistry: AdapterRegistry

    init(folderViewModel: FolderViewModel, adapterRegistry: AdapterRegistry) {
        self.folderViewModel = folderViewModel
        self.adapterRegistry = adapterRegistry
    }

    nonisolated func makeIsolatedSession(
        for agent: AgentID,
        sessionId: SessionID
    ) async throws -> ResolvedAgent {
        let folder: FolderRegistration? = await MainActor.run {
            // v0.5.0: control 메타 에이전트는 literal "control" 로 dispatch 됨
            // (자식 에이전트는 합성 syntheticAgentID). 결론 요약기가 "control" 호출.
            if agent.rawValue == "control" {
                return folderViewModel.folders.first { folder in
                    ControlAgentProvisioner.isControlFolder(folder.id)
                }
            }
            return folderViewModel.folders.first { folder in
                ControlTowerEnvironment.syntheticAgentID(for: folder.id) == agent
            }
        }
        guard let folder else {
            throw AgentResolverError.unknownAgent(id: agent)
        }
        guard let adapter = await adapterRegistry.adapter(for: folder.adapterId.rawValue) else {
            throw AgentResolverError.unknownAgent(id: agent)
        }
        let session = try await adapter.createSession(
            folderPath: folder.path,
            preferredSessionId: sessionId
        )
        return ResolvedAgent(adapter: adapter, session: session)
    }
}
