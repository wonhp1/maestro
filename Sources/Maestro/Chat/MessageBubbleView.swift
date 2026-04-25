import MaestroCore
import SwiftUI

/// 단일 채팅 메시지 — role 별 정렬/색상 + markdown 렌더링 + status 표시.
struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: alignment, spacing: 6) {
                roleBadge
                bubbleContent
                statusFooter
            }
            if message.role != .user { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Pieces

    private var alignment: HorizontalAlignment {
        message.role == .user ? .trailing : .leading
    }

    private var roleBadge: some View {
        Text(roleLabel)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Assistant"
        case .system: return "System"
        }
    }

    /// 표시용 본문 — assistant 응답에서 `<RELAY_TO=...>...</RELAY_TO>` /
    /// `<REPLY_TO=...>...</REPLY_TO>` XML 태그 제거. 디스패치 시스템은 원본 본문을
    /// 그대로 파싱하므로 표시 단에서만 sanitize.
    private var displayContent: String {
        guard message.role == .assistant else { return message.content }
        let stripped = ReplyParser.stripDispatchTags(message.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? message.content : stripped
    }

    @ViewBuilder
    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MarkdownRenderer.segments(displayContent), id: \.self) { segment in
                switch segment {
                case .prose(let text):
                    if !text.isEmpty {
                        Text(MarkdownRenderer.render(text))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .codeBlock(let lang, let code):
                    CodeBlockView(language: lang, code: code)
                }
            }
            // streaming 중에는 항상 작은 인디케이터 표시 (content 가 비어있지 않아도).
            if case .streaming = message.status {
                StreamingDot()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user: return Color.accentColor.opacity(0.12)
        case .assistant: return Color.secondary.opacity(0.08)
        case .system: return Color.orange.opacity(0.10)
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        switch message.status {
        case .sending:
            Text("Sending…").font(.caption2).foregroundStyle(.secondary)
        case .streaming:
            Text("Streaming…").font(.caption2).foregroundStyle(.secondary)
        case .complete:
            EmptyView()
        case .cancelled:
            Text("Cancelled").font(.caption2).foregroundStyle(.secondary)
        case .failed(let reason):
            Text("Failed: \(reason)")
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private var accessibilityLabel: String {
        "\(roleLabel): \(MarkdownRenderer.plainText(displayContent))"
    }

    private var accessibilityValue: String {
        switch message.status {
        case .sending: return "Sending"
        case .streaming: return "Streaming"
        case .complete: return ""
        case .cancelled: return "Cancelled"
        case .failed(let reason): return "Failed: \(reason)"
        }
    }
}

/// streaming 중 표시되는 작은 pulsing dot.
private struct StreamingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color.secondary.opacity(0.6))
            .frame(width: 6, height: 6)
            .scaleEffect(pulsing ? 1.4 : 0.8)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
            .accessibilityHidden(true)
    }
}
