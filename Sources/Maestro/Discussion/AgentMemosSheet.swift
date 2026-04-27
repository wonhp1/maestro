import MaestroCore
import MarkdownUI
import SwiftUI

/// v0.5.1 — 모든 토론 메모를 목록으로 보여주는 시트. 활성 토글 / 본문 편집 / 삭제.
///
/// 진입점: ControlTowerView 헤더의 "메모" 버튼 (Phase C 에서 추가).
struct AgentMemosSheet: View {
    @Bindable var viewModel: AgentMemoViewModel
    var agentDisplayResolver: (AgentID) -> String = { $0.rawValue }
    let dismiss: () -> Void

    @State private var selectedMemoId: ThreadID?
    @State private var draftBody: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.memos.isEmpty {
                emptyState
            } else {
                content
            }
            Divider()
            footer
        }
        .frame(width: 700, height: 500)
        .task { await viewModel.reload() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.tint)
            Text("토론 메모").font(.title3.weight(.semibold))
            Spacer()
            Text("\(viewModel.memos.count)개").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
            Text("저장된 메모가 없어요").font(.callout).foregroundStyle(.secondary)
            Text("토론 결론을 자식에게 공유하면 자동으로 메모가 생성됩니다.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        HStack(spacing: 0) {
            list
            Divider()
            detail
        }
    }

    private var list: some View {
        List(selection: $selectedMemoId) {
            ForEach(viewModel.memos) { memo in
                memoRow(memo)
                    .tag(memo.id)
            }
        }
        .listStyle(.sidebar)
        .frame(width: 250)
        .onChange(of: selectedMemoId) { _, newId in
            if let id = newId, let memo = viewModel.memos.first(where: { $0.id == id }) {
                draftBody = memo.body
            }
        }
    }

    private func memoRow(_ memo: DiscussionMemo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: memo.active
                      ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(memo.active ? .green : .secondary)
                    .imageScale(.small)
                Text(memo.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.caption2).foregroundStyle(.tertiary)
                Text("\(memo.sharedWith.count)명")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary).font(.caption2)
                Text(memo.updatedAt, style: .relative)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selectedMemoId,
           let memo = viewModel.memos.first(where: { $0.id == id }) {
            memoDetail(memo)
        } else {
            VStack {
                Spacer()
                Text("메모를 선택하세요")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func memoDetail(_ memo: DiscussionMemo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(memo.title).font(.headline).lineLimit(1)
                Spacer()
                Toggle(isOn: Binding(
                    get: { memo.active },
                    set: { newVal in
                        Task { await viewModel.toggleActive(memoId: memo.id, active: newVal) }
                    }
                )) {
                    Text("활성").font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            sharedRow(memo)
            TextEditor(text: $draftBody)
                .font(.body)
                .padding(6)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button(role: .destructive) {
                    Task {
                        await viewModel.delete(memoId: memo.id)
                        selectedMemoId = nil
                    }
                } label: {
                    Label("삭제", systemImage: "trash")
                }
                Button {
                    Task { await viewModel.updateBody(memoId: memo.id, body: draftBody) }
                } label: {
                    Label("본문 저장", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftBody == memo.body)
            }
        }
        .padding(12)
    }

    private func sharedRow(_ memo: DiscussionMemo) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Text("공유됨:").font(.caption).foregroundStyle(.secondary)
                ForEach(memo.sharedWith, id: \.self) { agent in
                    Text(agentDisplayResolver(agent))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let err = viewModel.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(2)
                Button("닫기") { viewModel.dismissError() }
                    .controlSize(.small)
            }
            Spacer()
            Button("닫기", action: dismiss)
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }
}
