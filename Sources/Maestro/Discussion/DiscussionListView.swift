import MaestroCore
import SwiftUI

/// 진행 중 + 최근 종료 토론 목록 — sidebar 또는 inspector slot 에 mount.
struct DiscussionListView: View {
    @Bindable var store: DiscussionStore
    @Binding var selectedID: ThreadID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.orderedViewModels.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(minWidth: 240)
    }

    private var header: some View {
        HStack {
            Image(systemName: "bubble.left.and.bubble.right.fill")
            Text("토론")
                .font(.headline)
            Spacer()
            Text("\(store.activeViewModels.count) 진행 중")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("진행 중인 토론이 없습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List(selection: $selectedID) {
            ForEach(store.orderedViewModels, id: \.discussion.id) { vm in
                DiscussionListRow(viewModel: vm)
                    .tag(Optional(vm.discussion.id))
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await store.evict(id: vm.discussion.id) }
                        } label: {
                            Label("토론 종료 + 제거", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct DiscussionListRow: View {
    let viewModel: DiscussionViewModel

    var body: some View {
        HStack(spacing: 8) {
            stateGlyph
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.discussion.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(Array(viewModel.discussion.participants.prefix(4)), id: \.self) { agent in
                        ParticipantAvatar(agentId: agent, size: 14)
                    }
                    Text("\(viewModel.envelopes.count)/\(viewModel.discussion.maxTurns)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var stateGlyph: some View {
        switch viewModel.state {
        case .active:
            Image(systemName: "circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .paused:
            Image(systemName: "pause.circle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .aborted:
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .pending:
            Image(systemName: "circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
