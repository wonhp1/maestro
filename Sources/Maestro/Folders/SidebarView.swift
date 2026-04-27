import MaestroCore
import SwiftUI

/// 사이드바 — 등록된 폴더 목록 + "+ 폴더 추가" 버튼.
///
/// ## 책임
/// - `FolderViewModel.folders` 를 List 로 표시
/// - 각 행: 폴더 이름 + 어댑터 chip + lastUsedAt 상대 시간
/// - 우클릭 / swipe → 삭제 confirm 다이얼로그
/// - 하단 "+ 폴더 추가" 버튼 → `viewModel.addFolderViaPicker()`
/// - ⌘, → 선택 폴더 설정 시트 열기
///
/// ## 상태 관리
/// `@Bindable` 로 `FolderViewModel` 의 변경에 자동 반응. 추가 로컬 state 는
/// `pendingDeletion` (confirm 대상) 과 `showingSettings` (시트 표시) 만.
struct SidebarView: View {
    @Bindable var viewModel: FolderViewModel
    /// Phase 12 — 폴더 행에 status badge / unread badge 표시. nil 이면 미표시 (Phase 10 호환).
    var statusStore: AgentStatusStore?
    var inboxStore: InboxStore?
    /// Phase v0.4.3 — vendor picker sheet 가 사용. nil 이면 sheet 미표시 (구 호환).
    var adapterRegistry: AdapterRegistry?
    /// Phase v0.4.3 — 토론 entry. 두 closure 가 nil 이면 토론 진입점 미표시.
    var discussionStore: DiscussionStore?
    var discussionStartViewModelFactory: (() -> DiscussionStartViewModel)?
    /// Phase v0.4.3 — 토론 선택 binding. 사용자가 토론을 선택하면 detail 이 전환됨.
    var selectedDiscussionID: Binding<ThreadID?> = .constant(nil)
    @State private var activeAlert: SidebarAlert?
    @State private var showingSettings: Bool = false
    /// v0.5.4 — 우클릭 / 톱니 버튼으로 settings 열 때 대상 folder. 옛 코드는
    /// selectedFolderID 만 사용 → 우클릭한 folder 와 다른 folder 의 설정이 열리던 버그.
    @State private var settingsTargetFolder: FolderRegistration?
    @State private var showingDiscussionStart: Bool = false
    @State private var detectionViewModel: AdapterDetectionViewModel?
    @State private var pendingDiscussionStart: DiscussionStartViewModel?

    /// **두 alert 동시 발생 (예: 삭제 confirm 표시 중 errorMessage 가 set) 시 SwiftUI
    /// 가 두 번째를 silently drop** — UX must-fix. enum 으로 단일 alert 채널화.
    private enum SidebarAlert: Identifiable {
        case deleteConfirm(FolderRegistration)
        case error(String)

        var id: String {
            switch self {
            case .deleteConfirm(let folder): return "delete-\(folder.id.rawValue)"
            case .error(let message): return "error-\(message.hashValue)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            folderList
            if let store = discussionStore, !store.orderedViewModels.isEmpty {
                Divider()
                discussionSection(store: store)
            }
            Divider()
            addButton
            if discussionStore != nil, discussionStartViewModelFactory != nil {
                Divider()
                addDiscussionButton
            }
            Divider()
            versionFooter
        }
        .frame(minWidth: 220)
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .deleteConfirm(let folder):
                return Alert(
                    title: Text("폴더 삭제"),
                    message: Text("\(folder.displayName) 을(를) 목록에서 제거합니다. 디스크의 실제 폴더는 삭제되지 않습니다."),
                    primaryButton: .destructive(Text("삭제")) {
                        Task { await viewModel.deleteFolder(id: folder.id) }
                    },
                    secondaryButton: .cancel(Text("취소"))
                )
            case .error(let message):
                return Alert(
                    title: Text("오류"),
                    message: Text(message),
                    dismissButton: .cancel(Text("확인")) {
                        viewModel.dismissError()
                    }
                )
            }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            // errorMessage 가 채워지면 alert 채널 통합 — 동시성 race 차단.
            if let message = newValue {
                activeAlert = .error(message)
            }
        }
        .onDeleteCommand {
            // 키보드 ⌫ — 선택된 폴더 삭제 confirm.
            if let id = viewModel.selectedFolderID,
               let folder = viewModel.folders.first(where: { $0.id == id }) {
                activeAlert = .deleteConfirm(folder)
            }
        }
        .sheet(isPresented: $showingSettings) {
            // v0.5.4 — settingsTargetFolder 우선 (우클릭/톱니 진입), 없으면
            // selectedFolderID fallback (단축키 진입).
            if let folder = settingsTargetFolder
                ?? viewModel.selectedFolderID
                .flatMap({ id in viewModel.folders.first(where: { $0.id == id }) }) {
                FolderSettingsSheet(
                    folder: folder,
                    viewModel: viewModel,
                    detectionViewModel: detectionViewModel,
                    adapterRegistry: adapterRegistry
                ) {
                    showingSettings = false
                    settingsTargetFolder = nil
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.pendingFolderURL != nil },
            set: { newValue in
                if !newValue { viewModel.cancelPendingAdd() }
            }
        )) {
            if let url = viewModel.pendingFolderURL,
               let detection = detectionViewModel {
                VendorPickerSheet(
                    folderURL: url,
                    folderViewModel: viewModel,
                    detectionViewModel: detection
                )
            }
        }
        .task(id: adapterRegistry.map { ObjectIdentifier($0) }) {
            // 첫 번째로 registry 가 들어왔을 때 detection VM 생성.
            if detectionViewModel == nil, let registry = adapterRegistry {
                detectionViewModel = AdapterDetectionViewModel(registry: registry)
            }
        }
        // I-NEW-4 fix — 옛 ⌘, hidden Button 제거. SwiftUI Settings scene 의 ⌘,
        // (앱 환경설정) 와 충돌해서 폴더 설정 시트가 먼저 열리는 버그. 폴더 설정은
        // 우클릭 → 메뉴 또는 SidebarView 내부 다른 진입점으로 사용 (단축키는 ⌘, 가
        // 아니라 다른 키 또는 미배정).
    }

    private var folderList: some View {
        List(selection: Binding(
            get: { viewModel.selectedFolderID },
            set: { newValue in
                guard let id = newValue else {
                    viewModel.selectedFolderID = nil
                    return
                }
                // I-NEW-8 fix — 폴더를 명시적으로 클릭하면 표시 중인 discussion 을
                // 자동으로 닫음. 안 그러면 detailContent 가 discussion 을 우선해서
                // 사용자 클릭이 무시된 것처럼 보임.
                selectedDiscussionID.wrappedValue = nil
                Task { await viewModel.select(id: id) }
            }
        )) {
            if viewModel.folders.isEmpty {
                emptyState
            } else {
                ForEach(viewModel.folders.sorted(by: { lhs, rhs in
                    // Control 폴더가 항상 sidebar 첫 자리
                    if ControlAgentProvisioner.isControlFolder(lhs.id) { return true }
                    if ControlAgentProvisioner.isControlFolder(rhs.id) { return false }
                    return lhs.displayName < rhs.displayName
                })) { folder in
                    FolderRow(
                        folder: folder,
                        status: statusStore?.status(for: folder.id),
                        unreadCount: inboxStore?.unreadCount(folderID: folder.id) ?? 0,
                        onSettings: {
                            settingsTargetFolder = folder
                            showingSettings = true
                        }
                    )
                    .tag(folder.id)
                    .contextMenu {
                        Button(role: .destructive) {
                            activeAlert = .deleteConfirm(folder)
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                        Button {
                            settingsTargetFolder = folder
                            showingSettings = true
                        } label: {
                            Label("설정...", systemImage: "gearshape")
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("등록된 폴더가 없습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("아래 + 버튼으로 폴더를 추가하세요.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    /// 사이드바 최하단 버전 표시 — MaestroConfig.appVersion 단일 source.
    private var versionFooter: some View {
        HStack {
            Spacer()
            Text("v\(MaestroConfig.appVersion)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var addButton: some View {
        Button {
            Task { await viewModel.addFolderViaPicker() }
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("폴더 추가")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func discussionSection(store: DiscussionStore) -> some View {
        DiscussionListView(store: store, selectedID: selectedDiscussionID)
            .frame(maxHeight: 240)
    }

    private var addDiscussionButton: some View {
        Button {
            guard let factory = discussionStartViewModelFactory else { return }
            pendingDiscussionStart = factory()
            showingDiscussionStart = true
        } label: {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(.purple)
                Text("새 토론")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showingDiscussionStart) {
            if let vm = pendingDiscussionStart {
                DiscussionStartSheet(viewModel: vm) { _ in
                    showingDiscussionStart = false
                    pendingDiscussionStart = nil
                }
            }
        }
    }
}

/// 사이드바 한 행 — 폴더 메타 + status badge + unread badge + v0.5.4 톱니 버튼.
private struct FolderRow: View {
    let folder: FolderRegistration
    let status: AgentStatus?
    let unreadCount: Int
    /// v0.5.4 — 명시적 설정 버튼 콜백. 우클릭 메뉴만으로는 발견 어려워 항상 보이는
    /// 톱니바퀴 추가.
    var onSettings: (() -> Void)?

    @State private var hovering: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ControlAgentProvisioner.isControlFolder(folder.id) ? "star.circle.fill" : "folder.fill")
                .foregroundStyle(ControlAgentProvisioner.isControlFolder(folder.id) ? Color.orange : Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(folder.displayName)
                        .font(.body)
                        .lineLimit(1)
                        .bold(ControlAgentProvisioner.isControlFolder(folder.id))
                    if let status {
                        AgentStatusBadge(status: status)
                    }
                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 4) {
                    Text(folder.adapterId.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                    if let modelId = folder.modelId, !modelId.isEmpty {
                        Text(modelId)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let last = folder.lastUsedAt {
                        Text(last, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            if let onSettings, hovering {
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("폴더 설정 (이름 / 어댑터 / 모델)")
                .accessibilityLabel("폴더 설정")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

#Preview {
    let paths = AppSupportPaths(root: FileManager.default.temporaryDirectory)
    let registry = FolderRegistry(paths: paths)
    let picker = StubFolderPicker(results: [])
    let vm = FolderViewModel(
        registry: registry,
        picker: picker,
        defaultAdapterID: AdapterID(rawValue: "claude")
    )
    return SidebarView(viewModel: vm, statusStore: nil, inboxStore: nil)
        .frame(width: 260, height: 400)
}
