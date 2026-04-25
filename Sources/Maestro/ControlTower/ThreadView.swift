import MaestroCore
import SwiftUI

/// 한 thread 의 envelope 들을 시간순 트리로 시각화 (Phase 12 단순 버전).
///
/// Phase 13+ 에서 inReplyTo 기반 indent 트리, 코드 미리보기, 토글 펼침 등 확장 예정.
struct ThreadView: View {
    let envelopes: [MessageEnvelope]

    var body: some View {
        if envelopes.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("이 스레드는 비어있습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(envelopes) { envelope in
                        ThreadEntry(envelope: envelope, indentLevel: indentLevel(for: envelope))
                    }
                }
                .padding(12)
            }
        }
    }

    private func indentLevel(for envelope: MessageEnvelope) -> Int {
        // 단순 모델: inReplyTo 가 있으면 1 indent. depth 트리는 Phase 13.
        envelope.inReplyTo == nil ? 0 : 1
    }
}

private struct ThreadEntry: View {
    let envelope: MessageEnvelope
    let indentLevel: Int

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if indentLevel > 0 {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
                    .padding(.leading, CGFloat(indentLevel) * 16)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(envelope.from.rawValue)
                        .font(.caption.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(envelope.to.rawValue)
                        .font(.caption.weight(.semibold))
                    typeBadge
                    Spacer(minLength: 0)
                    Text(envelope.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(envelope.body)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var typeBadge: some View {
        Text(envelope.type.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
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
