import MaestroCore
import MarkdownUI
import SwiftUI

/// 한 토론의 Slack-style 메인 뷰 — 헤더 + 메시지 리스트 + 컨트롤 + 끼어들기 입력창.
struct DiscussionDetailView: View {
    @Bindable var viewModel: DiscussionViewModel
    let onInterrupt: ((String) async -> Void)?
    /// v0.5.0 — 결론 자동 요약기 (control 어댑터 호출). nil 이면 "다시 요약" 버튼 비활성.
    var summarizer: DiscussionConclusionSummarizer?
    /// v0.5.0 — 결론 공유기 (자식 메인 세션 typing). nil 이면 "공유" 버튼 비활성.
    var sharer: DiscussionConclusionSharing?
    /// v0.5.0 — 영구 메모 저장소. share 시 함께 저장.
    var memoStore: AgentMemoStore?
    /// v0.5.0 — agentDisplayResolver: AgentID → 폴더 displayName. 칩 라벨에 사용.
    /// 기본값은 raw — 호출자가 FolderViewModel.displayName(for:) 주입 권장.
    var agentDisplayResolver: (AgentID) -> String = { $0.rawValue }

    @State private var interruptDraft: String = ""
    /// v0.5.0 — TextEditor binding state. 결론 변경 시 동기화.
    @State private var conclusionDraft: String = ""
    /// v0.5.0 — 사용자가 선택한 공유 대상 (chip 토글). 기본 — 모든 참가자 선택.
    @State private var shareTargets: Set<AgentID> = []
    @State private var shareInitialized: Bool = false
    /// 사용자가 최근 envelope 가까이에 있을 때만 auto-scroll — 위로 스크롤해서 과거 읽고
    /// 있을 때 yank 방지 (must-fix UX-1).
    @State private var pinnedToBottom: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            Divider()
            errorBanner
            controlsBar
            if viewModel.state == .active || viewModel.state == .paused {
                interruptComposer
            }
            if viewModel.state == .completed || viewModel.state == .aborted {
                Divider()
                DiscussionConclusionView(
                    viewModel: viewModel,
                    summarizer: summarizer,
                    sharer: sharer,
                    memoStore: memoStore,
                    agentDisplayResolver: agentDisplayResolver,
                    conclusionDraft: $conclusionDraft,
                    shareTargets: $shareTargets
                )
            }
        }
        .onChange(of: viewModel.discussion.conclusion) { _, new in
            // engine 이 conclusionUpdated broadcast 했을 때 draft 동기화
            if (new ?? "") != conclusionDraft {
                conclusionDraft = new ?? ""
            }
        }
        .onAppear {
            conclusionDraft = viewModel.discussion.conclusion ?? ""
            if !shareInitialized {
                shareTargets = Set(viewModel.discussion.participants)
                shareInitialized = true
            }
        }
        // I-NEW-6 fix — 옛 modal `.alert("오류", ...)` 제거. cryptic UUID + Swift
        // literal 이 사용자를 차단했음. 같은 정보가 곧바로 detail bar 의
        // "사유: 오류가 누적되어 자동 중단" 으로 노출되고, lastError 자체는 inline
        // notice 로 떨어진다 (controlsBar 위 errorBanner). 사용자가 직접 닫을 필요 X.
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = viewModel.lastError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("닫기") { viewModel.dismissError() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.1))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                // 사용자 입력 title — bidi/control sanitize (must-fix SEC-1)
                Text(DisplayTextSanitizer.sanitize(viewModel.discussion.title))
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(viewModel.discussion.participants, id: \.self) { agent in
                        ParticipantAvatar(agentId: agent, size: 20)
                    }
                    Text("· \(viewModel.envelopes.count)/\(viewModel.discussion.maxTurns) 턴")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            stateBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch viewModel.state {
        case .pending:
            badge(text: "대기", color: .gray)
        case .active:
            badge(text: "진행 중", color: .green)
        case .paused:
            badge(text: "일시 정지", color: .orange)
        case .completed:
            badge(text: "완료", color: .blue)
        case .aborted:
            badge(text: "중단됨", color: .red)
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.envelopes) { envelope in
                        DiscussionBubble(
                            envelope: envelope,
                            agentDisplayResolver: agentDisplayResolver
                        )
                        .id(envelope.id)
                    }
                    if let speaker = viewModel.currentSpeaker {
                        DiscussionTypingRow(
                            speaker: speaker,
                            agentDisplayResolver: agentDisplayResolver
                        )
                        .id("typing")
                    }
                }
                .padding(16)
            }
            .overlay(alignment: .bottomTrailing) {
                if !pinnedToBottom {
                    Button {
                        pinnedToBottom = true
                        if let last = viewModel.envelopes.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    } label: {
                        Label("최신 보기", systemImage: "arrow.down.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .accessibilityLabel("최신 메시지로 스크롤")
                }
            }
            .onChange(of: viewModel.envelopes.count) { _, _ in
                guard pinnedToBottom, let last = viewModel.envelopes.last else { return }
                if reduceMotion {
                    proxy.scrollTo(last.id, anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.currentSpeaker) { _, speaker in
                guard pinnedToBottom, speaker != nil else { return }
                if reduceMotion {
                    proxy.scrollTo("typing", anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
            // 사용자 스크롤 감지 — bottom anchor visibility 로 pinnedToBottom 토글
            .simultaneousGesture(DragGesture().onChanged { _ in
                pinnedToBottom = false
            })
        }
    }

    // MARK: - Controls

    private var controlsBar: some View {
        HStack(spacing: 8) {
            switch viewModel.state {
            case .pending:
                Button("시작", systemImage: "play.fill") {
                    Task { await viewModel.start() }
                }
                .buttonStyle(.borderedProminent)
            case .active:
                Button("일시 정지", systemImage: "pause.fill") {
                    Task { await viewModel.pause() }
                }
                Button("종료", systemImage: "stop.fill", role: .destructive) {
                    Task { await viewModel.terminate() }
                }
            case .paused:
                Button("재개", systemImage: "play.fill") {
                    Task { await viewModel.resume() }
                }
                .buttonStyle(.borderedProminent)
                Button("종료", systemImage: "stop.fill", role: .destructive) {
                    Task { await viewModel.terminate() }
                }
            case .completed, .aborted:
                Text(viewModel.terminationReason.map { "사유: \($0.localizedDescription)" } ?? "종료")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.discardedCount > 0 {
                Text("폐기 \(viewModel.discardedCount)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("pause/terminate 중 도착해 폐기된 응답 수")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Interrupt composer

    private var interruptComposer: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.tint)
            TextField("🎤 잠깐 끼어들기 — Enter 로 전송", text: $interruptDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { sendInterrupt() }
                .disabled(onInterrupt == nil)
            Button("보내기") { sendInterrupt() }
                .buttonStyle(.borderedProminent)
                .disabled(canInterrupt == false)
                .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var canInterrupt: Bool {
        guard onInterrupt != nil else { return false }
        return !interruptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendInterrupt() {
        let trimmed = interruptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let onInterrupt else { return }
        interruptDraft = ""
        Task { await onInterrupt(trimmed) }
    }
}

// MARK: - Bubble + Typing row

private struct DiscussionBubble: View {
    let envelope: MessageEnvelope
    /// v0.5.3 — AgentID → 폴더 displayName resolver. raw "agent-{uuid}" 대신
    /// 폴더 이름 (예: "cfo") 표시. 토론창이 컨트롤타워 다른 화면과 같은 라벨 사용.
    let agentDisplayResolver: (AgentID) -> String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ParticipantAvatar(agentId: envelope.from, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(agentDisplayResolver(envelope.from))
                        .font(.callout.weight(.semibold))
                    Text(envelope.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    typeBadge
                }
                // v0.5.1 — MarkdownUI 로 렌더 (이전 plain Text 가 가독성 망쳤음).
                // sanitize 는 raw text 단계에서 — MarkdownUI 가 다시 파싱하므로
                // bidi/control 문자 제거가 syntax 깨지 않도록 sanitize 후 전달.
                Markdown(DisplayTextSanitizer.sanitize(envelope.body))
                    .markdownTheme(.maestro)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var typeBadge: some View {
        Text(envelope.type.rawValue)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(typeColor.opacity(0.18))
            .foregroundStyle(typeColor)
            .clipShape(Capsule())
    }

    private var typeColor: Color {
        switch envelope.type {
        case .task: return .blue
        case .question: return .orange
        case .report: return .green
        case .fyi: return .secondary
        }
    }
}

private struct DiscussionTypingRow: View {
    let speaker: AgentID
    /// v0.5.3 — DiscussionBubble 와 동일한 displayName resolver.
    let agentDisplayResolver: (AgentID) -> String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ParticipantAvatar(agentId: speaker, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(agentDisplayResolver(speaker))
                    .font(.callout.weight(.semibold))
                TypingIndicator()
                    .padding(10)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
