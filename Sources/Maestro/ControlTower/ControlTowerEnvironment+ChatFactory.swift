import MaestroAdapters
import MaestroCore
import SwiftUI

/// v0.5.1 — `ControlTowerEnvironment.makeChatViewModelFactory` 분리 (file_length).
extension ControlTowerEnvironment {
    /// Control 폴더 + adapterId == "claude" → 동적 system prompt 가 주입된 별도
    /// ClaudeAdapter. 사용자가 control 폴더 어댑터를 다른 vendor 로 변경한 경우
    /// 일반 selector 경로로 폴백.
    /// I-NEW-2 — folder 에 영속된 sessionId 를 어댑터에 전달해 prior 대화 재개.
    /// v0.5.1 — folder.modelId 도 함께 전달 → claude `--model <id>` flag.
    static func makeChatViewModelFactory(
        selector: AdapterSelector,
        controlClaudeAdapter: ClaudeAdapter?
    ) -> @MainActor (FolderRegistration) async throws -> ChatViewModel {
        return { folder in
            if ControlAgentProvisioner.isControlFolder(folder.id),
               folder.adapterId.rawValue == "claude",
               let ctrl = controlClaudeAdapter {
                let session = try await ctrl.createSession(
                    folderPath: folder.path,
                    preferredSessionId: folder.sessionId,
                    modelId: folder.modelId
                )
                return try ChatViewModel(adapter: ctrl, session: session)
            }
            // v0.9.6: Codex / Gemini 추가 (v0.9.0 Phase 4 누락된 라우팅 회귀 fix).
            let adapter = await selector.select(
                preferred: folder.adapterId.rawValue,
                enabled: ["claude", "aider", "codex", "gemini"]
            )
            let session = try await adapter.createSession(
                folderPath: folder.path,
                preferredSessionId: folder.sessionId,
                modelId: folder.modelId
            )
            return try ChatViewModel(adapter: adapter, session: session)
        }
    }
}
