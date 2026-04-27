import Foundation
import MaestroCore
import SwiftUI

/// `DiscussionConclusionSharing` production — 자식 ChatViewModel 에 결론 메시지를
/// programmatic send 한다. 결과 메시지는 자식 채팅창에 사용자 메시지처럼 보이고,
/// 어댑터가 응답을 stream — 자식이 결론을 컨텍스트로 기억하게 됨.
///
/// control-kim 의 `share` route 를 Maestro 에 매핑한 것:
/// ```ts
/// const message = `[토론 #${d.id} 결론 공유]\n주제: ${d.topic}\n\n${conclusion}\n\n앞으로 이 맥락을 기억해주세요.`;
/// ptyPool.write(name, message);
/// ```
///
/// 캐시된 ChatViewModel 이 있으면 그걸 직접 사용, 없으면 `ensureSession` 으로
/// 생성 (자식이 아직 한 번도 안 열렸을 때 — silent miss 방지).
@MainActor
final class MaestroConclusionSharer: DiscussionConclusionSharing {
    private let chatSessionStore: ChatSessionStore
    private let folderViewModel: FolderViewModel

    init(chatSessionStore: ChatSessionStore, folderViewModel: FolderViewModel) {
        self.chatSessionStore = chatSessionStore
        self.folderViewModel = folderViewModel
    }

    nonisolated func share(
        conclusion: String,
        discussion: Discussion,
        with targets: [AgentID]
    ) async throws {
        let message = Self.formatMessage(conclusion: conclusion, discussion: discussion)
        for agent in targets {
            try await shareToOne(agent: agent, message: message)
        }
    }

    nonisolated private func shareToOne(agent: AgentID, message: String) async throws {
        let folder: FolderRegistration? = await MainActor.run {
            folderViewModel.folders.first { folder in
                ControlTowerEnvironment.syntheticAgentID(for: folder.id) == agent
            }
        }
        guard let folder else {
            throw ConclusionShareError.unknownAgent(agent: agent)
        }
        guard let chatVM = await chatSessionStore.ensureSession(for: folder) else {
            throw ConclusionShareError.sessionUnavailable(agent: agent)
        }
        await MainActor.run {
            chatVM.sendProgrammatic(message)
        }
    }

    /// 결론 공유 메시지 포맷 — title 은 user/agent 출처라 sanitize.
    nonisolated static func formatMessage(conclusion: String, discussion: Discussion) -> String {
        let safeTitle = DisplayTextSanitizer.sanitize(discussion.title)
        return """
        [토론 결론 공유]
        주제: \(safeTitle)

        \(conclusion)

        앞으로 이 맥락을 기억해 주세요.
        """
    }
}

enum ConclusionShareError: LocalizedError {
    case unknownAgent(agent: AgentID)
    case sessionUnavailable(agent: AgentID)

    var errorDescription: String? {
        switch self {
        case .unknownAgent(let a): return "알 수 없는 에이전트: \(a.rawValue)"
        case .sessionUnavailable(let a): return "세션을 준비할 수 없어요: \(a.rawValue)"
        }
    }
}
