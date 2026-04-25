import Foundation
import Observation

/// 채팅 뷰의 main-actor view-model.
///
/// 책임:
/// - 메시지 배열 (`messages`) 의 append-only 보유 — UI binding 소스.
/// - 사용자 입력 (`draft`) → `send()` 호출 → 어댑터 streamMessage 소비.
/// - 스트리밍 chunk 마다 placeholder 메시지의 content 갱신.
/// - cancel / 에러 처리.
///
/// `@MainActor` — UI 와 직결되는 mutable state 이므로 메인 액터 격리.
/// `@Observable` — SwiftUI binding (Phase 8 ChatView 가 소비).
///
/// ## 어댑터 호환
/// `any AgentAdapter` 를 받으므로 ClaudeAdapter / MockAdapter / 향후 AiderAdapter 모두 가능.
/// streamMessage 의 default 구현 (sendMessage 위 single chunk fallback) 도 동작.
@MainActor
@Observable
public final class ChatViewModel {
    /// 단일 메시지 content 최대 byte cap — 악성 LLM 의 OOM 차단 (Phase 8 sec must-fix).
    public static let maxMessageContentBytes: Int = 256 * 1024

    public private(set) var messages: [ChatMessage] = []
    public var draft: String = ""
    public private(set) var isStreaming: Bool = false
    /// 직전 스트림이 *실패* 했을 때의 사용자 메시지. 사용자 취소는 lastError 에 안 잡힘.
    public private(set) var lastError: String?

    private let adapter: any AgentAdapter
    private let session: Session
    private let userAgentId: AgentID
    private let assistantAgentId: AgentID
    private var streamingTask: Task<Void, Never>?
    /// 현재 활성 placeholder 의 id — 늦게 도착한 chunk 가 stale 메시지에 쓰지 않도록 가드.
    private var activePlaceholderID: UUID?

    public init(adapter: any AgentAdapter, session: Session) throws {
        self.adapter = adapter
        self.session = session
        self.userAgentId = try AgentID.validated(rawValue: "user")
        self.assistantAgentId = session.agentId
    }

    /// 사용자 입력 전송 — `draft` 를 비우고 비동기 스트림 시작.
    /// 이미 streaming 중이거나 draft 가 비어있으면 no-op.
    public func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isStreaming else { return }
        draft = ""
        lastError = nil
        messages.append(ChatMessage.user(body))
        let placeholder = ChatMessage.assistantPlaceholder()
        messages.append(placeholder)
        let placeholderID = placeholder.id
        activePlaceholderID = placeholderID
        isStreaming = true
        streamingTask = Task { [weak self] in
            await self?.runStream(body: body, placeholderID: placeholderID)
        }
    }

    /// 진행 중인 스트림 취소. 동기적으로 isStreaming false / placeholder 무효화 →
    /// 즉시 다음 send 호출 가능 (Phase 8 must-fix race).
    public func cancel() {
        guard isStreaming else { return }
        streamingTask?.cancel()
        if let placeholderID = activePlaceholderID {
            updateStatus(of: placeholderID, to: .cancelled)
        }
        activePlaceholderID = nil
        isStreaming = false
    }

    /// 외부 (e.g., 에러 모달 dismiss) 에서 에러 메시지 클리어.
    public func clearLastError() {
        lastError = nil
    }

    // MARK: - Internals

    private func runStream(body: String, placeholderID: UUID) async {
        let envelope = MessageEnvelope.task(
            from: userAgentId,
            to: assistantAgentId,
            body: body
        )
        do {
            let stream = adapter.streamMessage(envelope, in: session)
            for try await chunk in stream {
                try Task.checkCancellation()
                applyChunk(chunk, to: placeholderID)
            }
            try Task.checkCancellation()
            // 정상 종료 — placeholder 가 여전히 활성일 때만 .complete.
            if activePlaceholderID == placeholderID {
                updateStatus(of: placeholderID, to: .complete)
            }
        } catch is CancellationError {
            // cancel() 이 이미 .cancelled 로 설정 — 재설정 안 함. lastError 도 안 set.
            if activePlaceholderID == placeholderID {
                updateStatus(of: placeholderID, to: .cancelled)
            }
        } catch {
            // localizedDescription — Swift error 의 internals 노출 방지 (Phase 8 sec must-fix).
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            if activePlaceholderID == placeholderID {
                updateStatus(of: placeholderID, to: .failed(message))
            }
            lastError = message
        }
        if activePlaceholderID == placeholderID {
            activePlaceholderID = nil
            isStreaming = false
        }
        streamingTask = nil
    }

    /// chunk 적용 — placeholder 가 더 이상 활성이 아니면 silently drop (race 방어).
    private func applyChunk(_ chunk: ResponseChunk, to id: UUID) {
        guard activePlaceholderID == id,
              let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        switch chunk.kind {
        case .text:
            appendCapped(chunk.content, to: idx)
        case .error:
            appendCapped("\n\n⚠️ \(chunk.content)", to: idx)
        case .thinking, .toolUse, .toolResult, .completion:
            // Phase 8 baseline — collapsed/marker 는 Phase 18 에서 도입.
            break
        }
    }

    /// content 끝에 추가하되 `maxMessageContentBytes` 초과 시 truncation marker 부착.
    private func appendCapped(_ piece: String, to idx: Int) {
        let current = messages[idx].content
        let cap = Self.maxMessageContentBytes
        let currentBytes = current.utf8.count
        if currentBytes >= cap { return }  // 이미 cap 도달 → drop
        let remaining = cap - currentBytes
        if piece.utf8.count <= remaining {
            messages[idx].content += piece
            return
        }
        // truncate piece to remaining bytes (UTF-8 boundary safe).
        let truncated = String(decoding: piece.utf8.prefix(remaining), as: UTF8.self)
        messages[idx].content += truncated + "\n\n[…출력이 한도를 초과해 잘림]"
    }

    private func updateStatus(of id: UUID, to status: ChatMessage.Status) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].status = status
    }
}
