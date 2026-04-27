import MaestroCore
import SwiftUI

/// 폴더 설정 시트 — 표시 이름 변경, 어댑터 변경, 삭제.
///
/// ⌘, 단축키 또는 컨텍스트 메뉴 "설정..." 으로 진입.
struct FolderSettingsSheet: View {
    let folder: FolderRegistration
    @Bindable var viewModel: FolderViewModel
    let dismiss: () -> Void

    /// 어댑터 감지 VM — 있으면 라이브 목록 사용, 없으면 폴더 자신의 어댑터만 표시 (테스트/preview).
    var detectionViewModel: AdapterDetectionViewModel?
    /// v0.5.5 — 어댑터로부터 사용 가능 모델 alias 받아옴. nil 이면 picker 숨김.
    var adapterRegistry: AdapterRegistry?
    /// v0.6.0 — 모델/어댑터 변경 시 사용자가 "지금 적용" 선택하면 호출. 호출자
    /// (SidebarView) 가 ChatSessionStore.evict(folderID:) 로 캐시된 ChatViewModel
    /// 제거 → 다음 진입 시 새 모델로 createSession.
    /// nil 이면 alert 자체를 띄우지 않음 — 변경은 디스크에 저장되고 다음 진입
    /// 시 자동 적용 (preview / 테스트 / 부분 wiring 호환). 정상 production 경로
    /// 는 항상 callback 전달.
    var onRequestRestart: ((FolderID) -> Void)?

    @State private var displayName: String
    @State private var adapterId: String
    /// v0.5.1 — 모델 선택. "" = 기본 (어댑터 default), 그 외 = 명시적 modelId.
    @State private var modelId: String
    /// v0.5.5 — 어댑터별 alias 리스트 (async 로 받아와서 cache).
    @State private var availableModels: [String] = []
    /// v0.6.0 — save 후 sessions-affecting 변경 (modelId/adapterId) 이 있으면 표시.
    @State private var showRestartPrompt: Bool = false

    init(
        folder: FolderRegistration,
        viewModel: FolderViewModel,
        detectionViewModel: AdapterDetectionViewModel? = nil,
        adapterRegistry: AdapterRegistry? = nil,
        onRequestRestart: ((FolderID) -> Void)? = nil,
        dismiss: @escaping () -> Void
    ) {
        self.folder = folder
        self.viewModel = viewModel
        self.detectionViewModel = detectionViewModel
        self.adapterRegistry = adapterRegistry
        self.onRequestRestart = onRequestRestart
        self.dismiss = dismiss
        _displayName = State(initialValue: folder.displayName)
        _adapterId = State(initialValue: folder.adapterId.rawValue)
        _modelId = State(initialValue: folder.modelId ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("폴더 설정")
                .font(.title2)
                .bold()

            Form {
                LabeledContent("경로") {
                    Text(folder.path.path)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                TextField("표시 이름", text: $displayName)
                    .textFieldStyle(.roundedBorder)

                Picker("기본 어댑터", selection: $adapterId) {
                    ForEach(availableAdapters, id: \.self) { id in
                        Text(adapterDisplayName(for: id)).tag(id)
                    }
                }

                if !availableModels.isEmpty {
                    Picker("모델", selection: $modelId) {
                        Text("기본 (CLI 가 결정 — 응답 후 자동 감지)").tag("")
                        ForEach(availableModels, id: \.self) { alias in
                            Text(alias).tag(alias)
                        }
                    }
                    .help("어댑터가 보고하는 stable alias 목록. 정확한 full version 은 응답 후 헤더에서 자동 표시.")
                }
            }
            .formStyle(.grouped)
            .task(id: adapterId) {
                // v0.5.5 — 어댑터 변경 시 alias 리스트 다시 fetch.
                guard let registry = adapterRegistry else { return }
                guard let adapter = await registry.adapter(for: adapterId) else {
                    availableModels = []
                    return
                }
                availableModels = await adapter.availableModels()
            }

            if let hint = currentAdapterHint {
                hintRow(hint)
            }

            if isControlNonClaudeWarning {
                controlVendorWarning
            }

            HStack {
                Spacer()
                Button("취소", role: .cancel, action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button("저장") {
                    Task { await applyChanges() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!hasChanges)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task { await detectionViewModel?.refresh() }
        .alert(
            "지금 적용할까요?",
            isPresented: $showRestartPrompt
        ) {
            // /team review MED — alert / sheet 동시 dismiss 가 stale binding 만들 수
            // 있어 alert 의 isPresented 를 먼저 false 로 명시.
            Button("지금 적용") {
                showRestartPrompt = false
                onRequestRestart?(folder.id)
                Task { @MainActor in dismiss() }
            }
            Button("나중에", role: .cancel) {
                showRestartPrompt = false
                Task { @MainActor in dismiss() }
            }
        } message: {
            // /team review HIGH must-fix — 옛 카피 "(대화 기록은 보존)" 가 misleading.
            // evict 는 in-memory ChatViewModel 만 제거 — 디스크 (folder.sessionId 와
            // claude 의 jsonl) 는 그대로지만, 화면의 messages 배열은 비워지고 다음
            // 진입 시 새 ChatView 가 로드 (어댑터의 --resume 이 디스크 history 사용).
            Text(
                "어댑터 또는 모델이 변경됐어요. 다음 폴더 진입 시 자동으로 새 설정이 적용됩니다.\n\n"
                + "지금 적용 = 캐시된 채팅 세션 즉시 새로 시작 (디스크의 옛 대화 기록은 보존, "
                + "다음 진입 시 어댑터가 재개하면 다시 보여요)."
            )
        }
    }

    private var availableAdapters: [String] {
        if let detection = detectionViewModel, !detection.sortedAdapterIDs.isEmpty {
            return detection.sortedAdapterIDs
        }
        // Fallback — registry 미주입 시 현재 어댑터만 노출 (변경 불가 효과).
        return [folder.adapterId.rawValue]
    }

    private func adapterDisplayName(for adapterId: String) -> String {
        detectionViewModel?.displayName(for: adapterId) ?? adapterId
    }

    private var currentAdapterHint: InstallationHint? {
        guard let detection = detectionViewModel?.detection(for: adapterId),
              !detection.isInstalled else {
            return nil
        }
        return AdapterDetectionViewModel.installationHint(for: adapterId)
    }

    @ViewBuilder
    private func hintRow(_ hint: InstallationHint) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(hint.description).font(.callout)
                Text(hint.command)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var isControlNonClaudeWarning: Bool {
        ControlAgentProvisioner.isControlFolder(folder.id) && adapterId != "claude"
    }

    @ViewBuilder
    private var controlVendorWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("Control 폴더에 Claude 외 어댑터 사용 중").font(.callout).bold()
                Text("폴더 목록 자동 주입은 Claude 전용이에요. 다른 어댑터는 일반 시스템 프롬프트만 사용됩니다 — 사용자가 직접 폴더 ID 를 알려줘야 합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var hasChanges: Bool {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines) != folder.displayName
            || adapterId != folder.adapterId.rawValue
            || normalizedModelId != (folder.modelId ?? "")
    }

    private var normalizedModelId: String {
        modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// v0.6.0 — modelId/adapterId 변경 = ChatViewModel 캐시 invalidation 필요.
    /// displayName 만 변경은 cosmetic — restart 불요.
    private var sessionAffectingChange: Bool {
        adapterId != folder.adapterId.rawValue
            || normalizedModelId != (folder.modelId ?? "")
    }

    private func applyChanges() async {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName != folder.displayName {
            await viewModel.rename(id: folder.id, to: trimmedName)
        }
        if adapterId != folder.adapterId.rawValue {
            do {
                let newAdapter = try AdapterID.validated(rawValue: adapterId)
                await viewModel.changeAdapter(id: folder.id, to: newAdapter)
            } catch {
                viewModel.errorMessage = "어댑터 ID 가 잘못되었습니다: \(adapterId)"
                return
            }
        }
        if normalizedModelId != (folder.modelId ?? "") {
            await viewModel.changeModel(id: folder.id, to: normalizedModelId)
        }
        // v0.6.0 — adapter / model 변경이 있고 onRequestRestart 콜백 set 되어 있으면
        // 사용자에게 "지금 적용" alert. 없으면 그냥 dismiss (다음 세션부터 적용).
        if sessionAffectingChange, onRequestRestart != nil {
            showRestartPrompt = true
        } else {
            dismiss()
        }
    }
}
