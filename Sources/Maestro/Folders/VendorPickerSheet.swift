import MaestroCore
import SwiftUI

/// 폴더 등록 직전, 어떤 어댑터(vendor) 를 사용할지 사용자에게 선택받는 시트.
///
/// ## UX 원칙
/// - **친절** — 미설치 어댑터는 disabled + 설치 명령어 inline 표시.
/// - **간결** — 라디오 + 설명 1-2 줄. 각 어댑터에 가장 중요한 정보 (설치 여부 + 버전) 만.
/// - **빠른 결정** — 설치된 어댑터가 1개뿐이면 자동 선택, 사용자가 그냥 "추가" 누르면 됨.
struct VendorPickerSheet: View {
    let folderURL: URL
    @Bindable var folderViewModel: FolderViewModel
    @Bindable var detectionViewModel: AdapterDetectionViewModel

    @State private var selectedAdapterID: String = ""
    @State private var pendingInstallAdapterID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if detectionViewModel.isDetecting {
                ProgressView("어댑터 감지 중…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                adapterList
            }

            footer
        }
        .padding(20)
        .frame(width: 560)
        .task { await loadDetections() }
        .sheet(item: Binding(
            get: { pendingInstallAdapterID.map { InstallTarget(id: $0) } },
            set: { newValue in pendingInstallAdapterID = newValue?.id }
        )) { target in
            AdapterInstallSheet(
                adapterId: target.id,
                displayName: detectionViewModel.displayName(for: target.id)
            ) { success in
                pendingInstallAdapterID = nil
                if success {
                    Task {
                        await detectionViewModel.refresh()
                        if detectionViewModel.detection(for: target.id)?.isInstalled == true {
                            selectedAdapterID = target.id
                        }
                    }
                }
            }
        }
    }

    private struct InstallTarget: Identifiable { let id: String }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("어떤 에이전트를 사용할까요?")
                .font(.title2).bold()
            Text(folderURL.path)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var adapterList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(detectionViewModel.sortedAdapterIDs, id: \.self) { adapterId in
                AdapterRow(
                    adapterId: adapterId,
                    displayName: detectionViewModel.displayName(for: adapterId),
                    detection: detectionViewModel.detection(for: adapterId),
                    isSelected: selectedAdapterID == adapterId,
                    onSelect: { selectedAdapterID = adapterId },
                    onRequestInstall: { pendingInstallAdapterID = adapterId }
                )
            }
            if detectionViewModel.sortedAdapterIDs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("어댑터를 아직 감지하지 못했어요.")
                        .foregroundStyle(.secondary)
                    Button("재시도") {
                        Task { await detectionViewModel.refresh() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("취소", role: .cancel) {
                folderViewModel.cancelPendingAdd()
            }
            .keyboardShortcut(.cancelAction)
            Button("추가") {
                Task { await confirmAdd() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canConfirm)
        }
    }

    private func confirmAdd() async {
        do {
            let adapterId = try AdapterID.validated(rawValue: selectedAdapterID)
            await folderViewModel.confirmPendingAdd(adapterId: adapterId)
        } catch {
            folderViewModel.errorMessage = "어댑터 ID 가 잘못되었습니다: \(selectedAdapterID)"
            folderViewModel.cancelPendingAdd()
        }
    }

    private var canConfirm: Bool {
        guard !selectedAdapterID.isEmpty,
              let detection = detectionViewModel.detection(for: selectedAdapterID) else {
            return false
        }
        return detection.isInstalled
    }

    private func loadDetections() async {
        await detectionViewModel.refresh()
        // 첫 진입 시 첫 설치된 어댑터 자동 선택 — 친절 UX.
        if selectedAdapterID.isEmpty,
           let firstInstalled = detectionViewModel.sortedAdapterIDs.first(where: {
               detectionViewModel.detection(for: $0)?.isInstalled == true
           }) {
            selectedAdapterID = firstInstalled
        }
    }
}

/// 한 어댑터의 한 행 — 라디오 + 이름 + 상태 (✓ 버전 / ✗ 미설치 + 설치 안내).
private struct AdapterRow: View {
    let adapterId: String
    let displayName: String
    let detection: AdapterDetection?
    let isSelected: Bool
    let onSelect: () -> Void
    let onRequestInstall: () -> Void

    var body: some View {
        Button(action: handleTap) {
            HStack(alignment: .top, spacing: 12) {
                radio
                content
                Spacer()
            }
            .padding(12)
            .background(rowBackground)
            .overlay(rowBorder)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isInstalled)
        .opacity(isInstalled ? 1.0 : 0.65)
    }

    private var radio: some View {
        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .imageScale(.large)
            .padding(.top, 2)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(displayName)
                    .font(.body).bold()
                if isInstalled {
                    Label(versionBadge, systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("미설치", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            if !isInstalled, let hint = AdapterDetectionViewModel.installationHint(for: adapterId) {
                installationHint(hint)
            }
        }
    }

    @ViewBuilder
    private func installationHint(_ hint: InstallationHint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hint.description).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button("자동 설치") { onRequestInstall() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                Text(hint.command)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                if let url = hint.docsURL {
                    Link("도움말 →", destination: url)
                        .font(.caption)
                }
            }
        }
        .padding(.top, 2)
    }

    private var isInstalled: Bool { detection?.isInstalled == true }

    private var versionBadge: String {
        if let version = detection?.version, !version.isEmpty {
            return "v\(version)"
        }
        return "설치됨"
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            Color.accentColor.opacity(0.10)
        } else {
            Color.clear
        }
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                lineWidth: isSelected ? 1.5 : 1
            )
    }

    private func handleTap() {
        guard isInstalled else { return }
        onSelect()
    }
}
