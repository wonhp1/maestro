import MaestroCore
import SwiftUI

/// 컨트롤 타워 상단 status bar — 진행 중/방금 완료된 dispatch 들을 한 줄로 표시.
///
/// 비어있을 때는 자체 hidden — 화면 공간 차지 안 함.
struct OrchestrationStatusBar: View {
    @Bindable var model: OrchestrationStatusModel
    /// v0.4.8 — AgentID → displayName resolver. 호출자가 FolderViewModel.displayName
    /// (for:) 를 넘기면 raw "agent-{uuid}" 대신 폴더 이름이 칩에 표시됨.
    var agentDisplayResolver: (AgentID) -> String = { $0.rawValue }

    var body: some View {
        if model.entries.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.entries) { entry in
                        EntryChip(
                            entry: entry,
                            fromDisplay: agentDisplayResolver(entry.from),
                            toDisplay: agentDisplayResolver(entry.to)
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
    }
}

private struct EntryChip: View {
    let entry: OrchestrationEntry
    let fromDisplay: String
    let toDisplay: String

    var body: some View {
        HStack(spacing: 6) {
            indicator
            Text(fromDisplay)
                .font(.caption)
                .lineLimit(1)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(toDisplay)
                .font(.caption)
                .lineLimit(1)
            stateLabel
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(background)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var indicator: some View {
        switch entry.state {
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch entry.state {
        case .running:
            Text("진행 중")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .completed:
            Text("완료")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    private var background: Color {
        switch entry.state {
        case .running: return Color.blue.opacity(0.08)
        case .completed: return Color.green.opacity(0.08)
        case .failed: return Color.red.opacity(0.08)
        }
    }

    private var accessibilityText: String {
        switch entry.state {
        case .running:
            return "진행 중: \(fromDisplay)에서 \(toDisplay)로"
        case .completed:
            return "완료: \(fromDisplay)에서 \(toDisplay)로"
        case .failed(let msg):
            return "실패: \(fromDisplay)에서 \(toDisplay)로 — \(msg)"
        }
    }
}
