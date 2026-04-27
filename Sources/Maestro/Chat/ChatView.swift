import MaestroCore
import SwiftUI

/// 단일 에이전트 채팅 — 메시지 리스트 + composer.
public struct ChatView: View {
    @Bindable var viewModel: ChatViewModel

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            modelHeader
            Divider()
            messageList
            Divider()
            ChatComposer(viewModel: viewModel) {
                viewModel.send()
            }
            errorBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// v0.5.1 — 어댑터 + 모델 표시 헤더.
    private var modelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.adapter.iconName.isEmpty
                  ? "terminal" : viewModel.adapter.iconName)
                .foregroundStyle(.tint)
                .imageScale(.small)
            Text(viewModel.adapter.displayName)
                .font(.caption.weight(.semibold))
            Text("·").foregroundStyle(.tertiary).font(.caption)
            Text(modelLabel)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .help("폴더 설정 (⌘,) 에서 변경")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private var modelLabel: String {
        let raw = viewModel.session.modelId ?? ""
        if raw.isEmpty { return "기본 모델" }
        // 사용자 친화 라벨: "claude-sonnet-4-5" → "Sonnet 4.5"
        return Self.prettyClaudeModel(raw)
    }

    static func prettyClaudeModel(_ id: String) -> String {
        let lower = id.lowercased()
        if lower.contains("sonnet") { return id.contains("4-5") ? "Sonnet 4.5" : "Sonnet" }
        if lower.contains("opus") { return id.contains("4-1") ? "Opus 4.1" : "Opus" }
        if lower.contains("haiku") { return id.contains("4-5") ? "Haiku 4.5" : "Haiku" }
        return id
    }

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    }
                    ForEach(viewModel.messages) { msg in
                        MessageBubbleView(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(.vertical, 8)
            }
            // 새 메시지 추가 시 (count 변화) 만 애니메이션 스크롤. streaming 도중의 chunk
            // 별 미세 스크롤은 안 함 — 사용자가 위로 스크롤해 읽는 동안 yank 방지.
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToLast(proxy, animated: true)
            }
        }
    }

    private func scrollToLast(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let lastID = viewModel.messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("🎼 \(MaestroConfig.appName)")
                .font(.title2.weight(.semibold))
            Text("AI 코딩 에이전트 공용 지휘소")
                .font(.body)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Label("Cmd + Enter 로 전송", systemImage: "return")
                Label("Cmd + . 로 스트리밍 취소", systemImage: "stop.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private var errorBar: some View {
        if let error = viewModel.lastError {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .lineLimit(2)
                Spacer()
                Button("Dismiss") { viewModel.clearLastError() }
                    .controlSize(.small)
            }
            .padding(8)
            .background(Color.red.opacity(0.08))
        }
    }
}
