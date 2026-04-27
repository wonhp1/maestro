import MaestroCore
import SwiftUI

/// 입력창 — 멀티라인 TextEditor + 전송 버튼.
/// Cmd+Enter 전송. Shift+Enter 줄바꿈 (TextEditor 기본).
struct ChatComposer: View {
    @Bindable var viewModel: ChatViewModel
    var onSend: () -> Void
    /// v0.7.0 Phase 1 — Cmd+K 팔레트 → 입력창 prepopulate side-channel.
    /// 호출자 (ChatView) 가 `$environment.pendingSlashInsertion` 로 binding 주입.
    /// 테스트/preview 는 `.constant(nil)` 사용.
    /// Race UX (ChatComposer + DispatchComposer 같은 binding share — first-fire wins,
    /// other no-ops on nil) 는 v0.7.0 Phase 1 의 알려진 trade-off. focus tracking 은
    /// 후속 polish.
    var slashInsertion: Binding<String?>
    /// v0.7.0 Phase 2 — `/` 인라인 자동완성 popover 용 registry. nil 이면 popup X.
    var slashRegistry: SlashCommandRegistry?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            textEditor
            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: slashInsertion.wrappedValue) { _, newValue in
            // pendingSlashInsertion consume — clear 시 self-recursion 은
            // resolve(nil) → nil → guard exit 로 차단.
            guard let resolved = SlashInsertionConsumer.resolve(pending: newValue) else {
                return
            }
            viewModel.draft = resolved
            slashInsertion.wrappedValue = nil
        }
    }

    /// TextEditor + slash popover modifier. helper 추출은 file_length 회피 +
    /// modifier 옵셔널 attach 분기 처리.
    @ViewBuilder
    private var textEditor: some View {
        let editor = TextEditor(text: $viewModel.draft)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(minHeight: 40, maxHeight: 160)
            .overlay(alignment: .topLeading) {
                if viewModel.draft.isEmpty {
                    Text("메시지 입력 — Cmd+Enter 로 전송")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            // .onSubmit 은 macOS TextEditor 에서 fire 안 됨 — Cmd+Enter 만 의지.
            .accessibilityLabel("Message input")
        if let slashRegistry {
            editor.modifier(SlashSuggestionsModifier(
                draft: $viewModel.draft, registry: slashRegistry
            ))
        } else {
            editor
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        if viewModel.isStreaming {
            Button(role: .destructive) {
                viewModel.cancel()
            } label: {
                Image(systemName: "stop.fill")
                    .imageScale(.large)
            }
            .keyboardShortcut(".", modifiers: .command)
            .help("Cancel (Cmd+.)")
            .accessibilityLabel("Cancel streaming")
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .imageScale(.large)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Send (Cmd+Enter)")
            .accessibilityLabel("Send message")
        }
    }
}
