import MaestroCore
import SwiftUI

/// 컨트롤 타워 우측 inspector — 받은 메시지 모음 + 폴더 필터링.
///
/// 폴더가 선택되어 있으면 그 폴더의 메시지만, 없으면 전체.
struct InboxPanel: View {
    @Bindable var store: InboxStore
    let selectedFolderID: FolderID?
    let folderTitleResolver: (FolderID) -> String
    /// v0.4.8 — AgentID → displayName (예: agent-{uuid} → "cfo", "control" → "Control").
    /// 기본값은 raw rawValue (옛 호출자 호환). 호출자가 FolderViewModel.displayName(for:)
    /// 를 넘기면 사용자 친화 이름이 row 에 표시됨.
    var agentDisplayResolver: (AgentID) -> String = { $0.rawValue }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filteredItems.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .frame(minWidth: 260, idealWidth: 320, maxWidth: 480)
    }

    private var header: some View {
        HStack {
            Image(systemName: "tray")
            Text("보고함")
                .font(.headline)
            Spacer()
            if store.totalUnread > 0 {
                Text("\(store.totalUnread)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            if !filteredItems.isEmpty {
                Button {
                    if let id = selectedFolderID {
                        store.markAllRead(folderID: id)
                    } else {
                        // 폴더 미선택 시 — 모든 폴더 읽음 처리 (a11y/UX must-fix).
                        for folderID in store.unreadCountsByFolder.keys {
                            store.markAllRead(folderID: folderID)
                        }
                    }
                } label: {
                    Image(systemName: "envelope.open")
                }
                .buttonStyle(.borderless)
                .help("모두 읽음")
                .accessibilityLabel("모두 읽음")
                .accessibilityHint(
                    selectedFolderID == nil
                    ? "모든 폴더의 받은 메시지를 읽음 표시"
                    : "선택된 폴더의 받은 메시지를 읽음 표시"
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("받은 메시지가 없습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemList: some View {
        List {
            ForEach(filteredItems) { item in
                InboxRow(
                    item: item,
                    folderTitle: folderTitleResolver(item.folderID),
                    senderDisplay: agentDisplayResolver(item.from),
                    recipientDisplay: agentDisplayResolver(item.to)
                )
                    .onTapGesture {
                        store.markRead(itemID: item.id)
                    }
            }
        }
        .listStyle(.inset)
    }

    private var filteredItems: [InboxItem] {
        guard let id = selectedFolderID else { return store.items }
        return store.items.filter { $0.folderID == id }
    }
}

private struct InboxRow: View {
    let item: InboxItem
    let folderTitle: String
    let senderDisplay: String
    let recipientDisplay: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            unreadIndicator
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(folderTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(senderDisplay)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(recipientDisplay)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                    Spacer(minLength: 0)
                    Text(item.receivedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(item.preview)
                    .font(.callout)
                    .foregroundStyle(item.isRead ? .secondary : .primary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var unreadIndicator: some View {
        Circle()
            .fill(item.isRead ? Color.clear : Color.accentColor)
            .frame(width: 8, height: 8)
            .padding(.top, 4)
    }
}
