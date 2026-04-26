import MaestroCore
import SwiftUI

/// 한 토론의 Slack-style 메인 뷰 — 헤더 + 메시지 리스트 + 컨트롤 + 끼어들기 입력창.
struct DiscussionDetailView: View {
    @Bindable var viewModel: DiscussionViewModel
    let onInterrupt: ((String) async -> Void)?

    @State private var interruptDraft: String = ""
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
            controlsBar
            if viewModel.state == .active || viewModel.state == .paused {
                interruptComposer
            }
        }
        .alert(
            "오류",
            isPresented: Binding(
                get: { viewModel.lastError != nil },
                set: { if !$0 { viewModel.dismissError() } }
            ),
            presenting: viewModel.lastError
        ) { _ in
            Button("확인", role: .cancel) { viewModel.dismissError() }
        } message: { msg in
            Text(msg)
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
                        DiscussionBubble(envelope: envelope)
                            .id(envelope.id)
                    }
                    if let speaker = viewModel.currentSpeaker {
                        DiscussionTypingRow(speaker: speaker)
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ParticipantAvatar(agentId: envelope.from, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(envelope.from.rawValue)
                        .font(.callout.weight(.semibold))
                    Text(envelope.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    typeBadge
                }
                // adapter 응답 body — bidi/control sanitize (must-fix SEC-1)
                Text(DisplayTextSanitizer.sanitize(envelope.body))
                    .font(.body)
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ParticipantAvatar(agentId: speaker, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(speaker.rawValue)
                    .font(.callout.weight(.semibold))
                TypingIndicator()
                    .padding(10)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
