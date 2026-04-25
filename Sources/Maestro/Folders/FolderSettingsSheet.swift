import MaestroCore
import SwiftUI

/// 폴더 설정 시트 — 표시 이름 변경, 어댑터 변경, 삭제.
///
/// ⌘, 단축키 또는 컨텍스트 메뉴 "설정..." 으로 진입.
struct FolderSettingsSheet: View {
    let folder: FolderRegistration
    @Bindable var viewModel: FolderViewModel
    let dismiss: () -> Void

    @State private var displayName: String
    @State private var adapterId: String
    @State private var availableAdapters: [String]

    init(
        folder: FolderRegistration,
        viewModel: FolderViewModel,
        availableAdapters: [String] = ["claude", "aider"],
        dismiss: @escaping () -> Void
    ) {
        self.folder = folder
        self.viewModel = viewModel
        self.dismiss = dismiss
        _displayName = State(initialValue: folder.displayName)
        _adapterId = State(initialValue: folder.adapterId.rawValue)
        _availableAdapters = State(initialValue: availableAdapters)
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
                        Text(id).tag(id)
                    }
                }
            }
            .formStyle(.grouped)

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
    }

    private var hasChanges: Bool {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines) != folder.displayName
            || adapterId != folder.adapterId.rawValue
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
        dismiss()
    }
}
