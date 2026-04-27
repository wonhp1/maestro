import MaestroCore
import SwiftUI

/// 컨트롤 타워의 "보내기" 패널 — 폴더(=대상 에이전트) 선택 + 메시지 작성 + 전송.
///
/// `safeAreaInset(edge: .bottom)` 으로 ChatView 하단에 attach. 빈 상태 (폴더 없음)
/// 일 때는 hidden.
struct DispatchComposer: View {
    @Bindable var folderViewModel: FolderViewModel
    let onSend: (FolderRegistration, String) async -> Void
    /// v0.7.0 Phase 1 — Cmd+K 팔레트 → 입력창 prepopulate side-channel.
    /// 호출자가 `$environment.pendingSlashInsertion` 로 binding 주입.
    /// 테스트/preview 는 `.constant(nil)` 사용.
    var slashInsertion: Binding<String?>

    @State private var draft: String = ""
    @State private var targetID: FolderID?
    @State private var isSending: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                targetPicker
                messageField
                sendButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .onChange(of: folderViewModel.selectedFolderID) { _, newValue in
            if targetID == nil { targetID = newValue }
        }
        .onChange(of: slashInsertion.wrappedValue) { _, newValue in
            // pendingSlashInsertion consume — self-recursion 은 resolve(nil) → guard 차단.
            guard let resolved = SlashInsertionConsumer.resolve(pending: newValue) else {
                return
            }
            draft = resolved
            slashInsertion.wrappedValue = nil
        }
    }

    private var targetPicker: some View {
        Picker("대상", selection: Binding(
            get: { targetID ?? folderViewModel.selectedFolderID },
            set: { targetID = $0 }
        )) {
            Text("대상 선택").tag(FolderID?.none)
            ForEach(folderViewModel.folders) { folder in
                Text(folder.displayName).tag(Optional(folder.id))
            }
        }
        .labelsHidden()
        .frame(maxWidth: 180)
    }

    private var messageField: some View {
        TextField("메시지 입력 — Cmd+Return 으로 전송", text: $draft, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...6)
            .onSubmit(send)
    }

    private var sendButton: some View {
        Button {
            send()
        } label: {
            if isSending {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "paperplane.fill")
            }
        }
        .keyboardShortcut(.return, modifiers: [.command])
        .buttonStyle(.borderedProminent)
        .disabled(!canSend)
        .accessibilityLabel("보내기")
    }

    private var canSend: Bool {
        guard !isSending else { return false }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let id = targetID ?? folderViewModel.selectedFolderID
        return id != nil
    }

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = targetID ?? folderViewModel.selectedFolderID
        guard !trimmed.isEmpty, let resolvedID = id,
              let folder = folderViewModel.folders.first(where: { $0.id == resolvedID }) else {
            return
        }
        isSending = true
        let body = trimmed
        draft = ""
        Task {
            await onSend(folder, body)
            isSending = false
        }
    }
}
