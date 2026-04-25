import MaestroCore
import SwiftUI

/// Cmd+K 로 띄우는 floating modal 팔레트.
///
/// - 검색 필드 + 결과 리스트 + 카테고리 / shortcut hint 표시
/// - ↑/↓ 로 선택 이동 (`onMoveCommand`), Enter 로 실행, Esc 로 닫기
/// - VS Code / Slack / Linear 스타일 — 단일 floating panel
struct CommandPaletteView: View {
    @Bindable var viewModel: CommandPaletteViewModel

    var body: some View {
        VStack(spacing: 0) {
            queryField
            Divider()
            resultsList
        }
        .frame(width: 540, height: 420)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 24)
        .onMoveCommand { direction in
            switch direction {
            case .up: viewModel.moveSelection(by: -1)
            case .down: viewModel.moveSelection(by: 1)
            default: break
            }
        }
        .onExitCommand { viewModel.dismiss() }
    }

    private var queryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("명령 검색…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .onSubmit {
                    Task { await viewModel.executeSelected() }
                }
            Text("⌘K")
                .font(.caption.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var resultsList: some View {
        Group {
            if viewModel.results.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    List(selection: Binding(
                        get: { selectedID },
                        set: { newID in
                            if let id = newID,
                               let idx = viewModel.results.firstIndex(where: { $0.id == id }) {
                                viewModel.selectedIndex = idx
                            }
                        }
                    )) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { idx, command in
                            CommandRow(command: command, isSelected: idx == viewModel.selectedIndex)
                                .tag(command.id)
                                .id(command.id)
                                .onTapGesture {
                                    viewModel.selectedIndex = idx
                                    Task { await viewModel.executeSelected() }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: viewModel.selectedIndex) { _, newIdx in
                        guard viewModel.results.indices.contains(newIdx) else { return }
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(viewModel.results[newIdx].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var selectedID: String? {
        guard viewModel.results.indices.contains(viewModel.selectedIndex) else { return nil }
        return viewModel.results[viewModel.selectedIndex].id
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "command")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(viewModel.query.isEmpty ? "사용 가능한 명령이 없습니다." : "일치하는 명령이 없습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CommandRow: View {
    let command: Command
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            categoryIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.body)
                    .lineLimit(1)
                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let hint = command.shortcutHint {
                Text(hint)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Text(command.category.localizedName)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(categoryColor.opacity(0.18))
                .foregroundStyle(categoryColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(command.title))
        .accessibilityHint(Text(command.subtitle ?? command.category.localizedName))
    }

    private var categoryIcon: some View {
        Image(systemName: iconName)
            .foregroundStyle(categoryColor)
            .frame(width: 18)
    }

    private var iconName: String {
        switch command.category {
        case .folder: return "folder.fill"
        case .dispatch: return "paperplane.fill"
        case .discussion: return "bubble.left.and.bubble.right.fill"
        case .slash: return "terminal.fill"
        case .system: return "gearshape.fill"
        case .recent: return "clock"
        }
    }

    private var categoryColor: Color {
        switch command.category {
        case .folder: return .blue
        case .dispatch: return .green
        case .discussion: return .purple
        case .slash: return .indigo
        case .system: return .gray
        case .recent: return .orange
        }
    }
}
