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
        // v0.5.2 — view 진입 시 어댑터에 현재 모델 한 번 물어봄. 응답 1회 받은
        // 어댑터는 즉시 정확한 라벨 (예: "claude-sonnet-4-5") 반환.
        .task { await viewModel.refreshCurrentModel() }
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
        // v0.5.5 — 정직: explicit modelId → 응답 capture → "감지 중…" (추측 X).
        let raw = viewModel.currentModel ?? viewModel.session.modelId ?? ""
        if raw.isEmpty { return "감지 중… (메시지 보내면 자동 감지)" }
        return Self.prettyModel(raw)
    }

    /// v0.5.6 — 일반 패턴 기반 압축. hardcode 한 버전 매치 (옛 4-5/4-1 만 인식)
    /// 대신 `claude-(family)-(version)(-date)?` 추출.
    /// 예시:
    ///   - "sonnet" → "Sonnet"
    ///   - "claude-sonnet-4-5" → "Sonnet 4.5"
    ///   - "claude-sonnet-4-5-20250929" → "Sonnet 4.5"
    ///   - "claude-sonnet-4-6" → "Sonnet 4.6" (미래 버전도 자동)
    ///   - "claude-opus-4-1" → "Opus 4.1"
    ///   - "gpt-4o" → "Gpt 4o" (다른 어댑터 alias 도 자연스럽게)
    static func prettyModel(_ id: String) -> String {
        var trimmed = id
        if trimmed.hasPrefix("claude-") {
            trimmed = String(trimmed.dropFirst("claude-".count))
        }
        var parts = trimmed.split(separator: "-").map(String.init)
        guard let family = parts.first else { return id }
        parts.removeFirst()
        // YYYYMMDD date suffix 떼기 (8자리 숫자).
        if let last = parts.last,
           last.count == 8,
           last.allSatisfy({ $0.isNumber }) {
            parts.removeLast()
        }
        let familyCap = family.prefix(1).uppercased() + family.dropFirst()
        if parts.isEmpty { return familyCap }
        return "\(familyCap) \(parts.joined(separator: "."))"
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
