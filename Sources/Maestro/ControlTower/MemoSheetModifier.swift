import MaestroCore
import SwiftUI

/// v0.5.1 — ControlTowerView 의 file_length 회피용 분리. 토론 메모 시트 + 툴바
/// 버튼을 한 modifier 로.
struct MemoSheetModifier: ViewModifier {
    @Bindable var environment: ControlTowerEnvironment
    @Binding var showSheet: Bool
    @Binding var viewModel: AgentMemoViewModel?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showSheet) {
                if let vm = viewModel {
                    AgentMemosSheet(
                        viewModel: vm,
                        agentDisplayResolver: environment.folderViewModel.map { fvm in
                            fvm.displayName(for:)
                        } ?? { $0.rawValue }
                    ) { showSheet = false }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if viewModel == nil {
                            viewModel = AgentMemoViewModel(
                                store: environment.agentMemoStore
                            )
                        }
                        showSheet = true
                    } label: {
                        Label("메모", systemImage: "doc.text.magnifyingglass")
                    }
                    .help("토론 메모 관리 — 활성/비활성, 본문 편집, 삭제")
                }
            }
    }
}
