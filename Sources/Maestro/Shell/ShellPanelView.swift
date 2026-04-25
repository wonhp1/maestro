import MaestroCore
import SwiftUI

/// 한 폴더의 쉘 패널 — 탭 strip + 활성 탭 터미널.
///
/// **현재 폼**: SwiftUI `TextEditor` 가 PTY 출력을 monospace 로 표시 + 입력은 별도
/// `TextField`. 완전한 ANSI/escape 렌더링은 Phase 20.5+ 에서 SwiftTerm 으로 교체.
struct ShellPanelView: View {
    @Bindable var viewModel: ShellTabsViewModel
    let cwd: URL?

    @State private var inputBuffer: String = ""

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider()
            terminalArea
        }
        .task {
            if viewModel.tabs.isEmpty {
                _ = await viewModel.openNewTab(cwd: cwd)
            }
        }
    }

    @ViewBuilder
    private var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(viewModel.tabs) { tab in
                tabChip(tab)
            }
            Button {
                Task { _ = await viewModel.openNewTab(cwd: cwd) }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func tabChip(_ tab: ShellTab) -> some View {
        HStack(spacing: 4) {
            Text(tab.title)
                .lineLimit(1)
            Button {
                Task { await viewModel.closeTab(id: tab.id) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(viewModel.activeTabID == tab.id
                      ? Color.accentColor.opacity(0.15)
                      : Color.gray.opacity(0.08))
        )
        .onTapGesture { viewModel.selectTab(id: tab.id) }
    }

    @ViewBuilder
    private var terminalArea: some View {
        if let active = viewModel.activeTab {
            VStack(spacing: 0) {
                ScrollView {
                    Text(active.outputBuffer)
                        .font(.system(.callout, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .background(Color.black.opacity(0.04))
                Divider()
                inputRow(active)
            }
        } else {
            ContentUnavailableView(
                "쉘 탭 없음",
                systemImage: "terminal",
                description: Text("+ 버튼으로 새 탭을 추가하세요")
            )
        }
    }

    private func inputRow(_ tab: ShellTab) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
            TextField("입력 후 Enter…", text: $inputBuffer)
                .textFieldStyle(.plain)
                .font(.system(.callout, design: .monospaced))
                .onSubmit {
                    let line = inputBuffer + "\n"
                    inputBuffer = ""
                    Task { await tab.send(line) }
                }
            if tab.hasExited, let code = tab.exitCode {
                Text("종료 \(code)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }
}
