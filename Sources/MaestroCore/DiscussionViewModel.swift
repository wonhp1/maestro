import Foundation
import Observation

/// Slack-style 토론 뷰의 driving state — `DiscussionEngine` 이벤트를 수집해 UI 친화적
/// snapshot 으로 노출.
///
/// ## 책임
/// - `DiscussionEngine.events()` 구독 → `envelopes` / `state` / `currentSpeaker` 갱신
/// - 사용자 액션 forwarding (`pause` / `resume` / `terminate` / `start`)
/// - **typing indicator**: `currentSpeaker != nil` 일 때 UI 가 ●●● 표시
/// - **error message**: `lastError` 으로 surface
///
/// ## 동시성
/// `@MainActor` — SwiftUI 와 같은 isolation. engine actor 는 `await` 로 호출.
///
/// ## 메모리
/// envelopes 무제한 — Phase 15 task 15.9 (무한 스크롤) 후속 LRU 도입.
@MainActor
@Observable
public final class DiscussionViewModel {
    public private(set) var discussion: Discussion
    public private(set) var envelopes: [MessageEnvelope] = []
    public private(set) var state: DiscussionState
    public private(set) var currentSpeaker: AgentID?
    public private(set) var lastError: String?
    public private(set) var terminationReason: DiscussionEngine.TerminationReason?
    public private(set) var discardedCount: Int = 0

    public let engine: DiscussionEngine

    @ObservationIgnored
    private var observationTask: Task<Void, Never>?

    public init(discussion: Discussion, engine: DiscussionEngine) {
        self.discussion = discussion
        self.engine = engine
        self.state = discussion.state
        self.envelopes = []  // Phase 14 의 turns 는 metadata; envelopes 는 event 로 수집
    }

    /// v0.5.4 — 디스크에서 복원 시 호출. envelopes seed + state sync.
    public func restoreEnvelopes(_ envs: [MessageEnvelope]) {
        self.envelopes = envs
    }

    deinit {
        // MainActor 격리된 task 를 nonisolated deinit 에서 직접 cancel 불가 —
        // detach 한 Task 로 hop (Phase 15 must-fix ARCH-1).
        // observationTask 는 강한 참조 — capture 직후 self 와 분리되어 안전.
        if let task = observationTask {
            Task { task.cancel() }
        }
    }

    /// engine event 구독 시작. ContentView 의 `.task` 또는 store 가 호출.
    public func bindEvents() async {
        guard observationTask == nil else { return }
        let stream = await engine.events()
        observationTask = Task { [weak self] in
            for await event in stream {
                guard let self else { break }
                await self.apply(event)
            }
        }
    }

    public func unbindEvents() {
        observationTask?.cancel()
        observationTask = nil
    }

    private func apply(_ event: DiscussionEngine.Event) async {
        switch event {
        case .stateChanged(let newState):
            self.state = newState
            if newState != .active {
                self.currentSpeaker = nil
            }
            await refreshDiscussionSnapshot()
        case .turnStarted(let speaker, _):
            self.currentSpeaker = speaker
        case .turnCompleted(_, let envelope):
            self.envelopes.append(envelope)
            self.currentSpeaker = nil
            await refreshDiscussionSnapshot()
        case .turnFailed(let speaker, let message):
            self.lastError = "[\(speaker.rawValue)] \(message)"
            self.currentSpeaker = nil
        case .turnDiscarded:
            self.discardedCount += 1
            self.currentSpeaker = nil
        case .terminated(let reason):
            self.terminationReason = reason
            self.currentSpeaker = nil
        case .conclusionUpdated:
            await refreshDiscussionSnapshot()
        case .sharedToTargets:
            await refreshDiscussionSnapshot()
        }
    }

    private func refreshDiscussionSnapshot() async {
        self.discussion = await engine.discussion
    }

    // MARK: - User actions

    public func start() async {
        do { try await engine.start() } catch {
            lastError = error.localizedDescription
        }
    }

    public func pause() async {
        do { try await engine.pause() } catch {
            lastError = error.localizedDescription
        }
    }

    public func resume() async {
        do { try await engine.resume() } catch {
            lastError = error.localizedDescription
        }
    }

    public func terminate() async {
        do { try await engine.terminate() } catch {
            lastError = error.localizedDescription
        }
    }

    public func dismissError() {
        lastError = nil
    }

    // MARK: - v0.5.0 — Conclusion

    /// 사회자 (요약기) 호출. 진행 중 표시 위해 `isSummarizing` 토글.
    public private(set) var isSummarizing: Bool = false

    public func summarizeConclusion(using summarizer: DiscussionConclusionSummarizer) async {
        guard !isSummarizing else { return }
        isSummarizing = true
        defer { isSummarizing = false }
        do {
            _ = try await engine.summarizeConclusion(
                envelopes: envelopes, using: summarizer
            )
        } catch {
            lastError = "결론 요약 실패: \(error.localizedDescription)"
        }
    }

    /// 사용자 직접 편집. 빈 문자열도 허용 (사용자가 결론을 지우고 싶을 수 있음).
    public func updateConclusion(_ text: String) async {
        await engine.setConclusion(text)
    }

    // MARK: - v0.5.0 — Conclusion sharing

    /// 공유 진행 중 표시 — UI 가 ProgressView/buttons disable 에 사용.
    public private(set) var isSharing: Bool = false

    /// 결론을 자식 에이전트들의 메인 세션에 typing + 영구 메모 저장 (옵션 C).
    /// - Note: `discussion.conclusion` 이 비어있으면 lastError set 후 no-op.
    /// - Parameter memoStore: nil 이면 메모 저장 건너뜀 (테스트/onboarding 경로).
    public func shareConclusion(
        with targets: [AgentID],
        using sharer: DiscussionConclusionSharing,
        memoStore: AgentMemoStore? = nil
    ) async {
        guard !isSharing else { return }
        let conclusion = (discussion.conclusion ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conclusion.isEmpty else {
            lastError = "결론이 비어있어 공유할 수 없어요."
            return
        }
        guard !targets.isEmpty else {
            lastError = "공유 대상이 비어있어요."
            return
        }
        isSharing = true
        defer { isSharing = false }
        do {
            try await sharer.share(
                conclusion: conclusion,
                discussion: discussion,
                with: targets
            )
            await engine.markShared(with: targets, at: Date())
            // v0.5.0 옵션 C — 영구 메모 저장. share 와 atomically 묶이지 않지만
            // share 성공 후에만 시도 → 부분 실패는 사용자가 메모 패널에서 정정.
            if let memoStore {
                let memo = DiscussionMemo(
                    id: discussion.id,
                    title: discussion.title,
                    body: conclusion,
                    sharedWith: targets,
                    updatedAt: Date(),
                    active: true
                )
                do {
                    try await memoStore.save(memo)
                } catch {
                    lastError = "메모 저장 실패 (공유는 완료): \(error.localizedDescription)"
                }
            }
        } catch {
            lastError = "공유 실패: \(error.localizedDescription)"
        }
    }
}
