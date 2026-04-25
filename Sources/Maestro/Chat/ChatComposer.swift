import MaestroCore
import SwiftUI

/// 입력창 — 멀티라인 TextEditor + 전송 버튼.
/// Cmd+Enter 전송. Shift+Enter 줄바꿈 (TextEditor 기본).
struct ChatComposer: View {
    @Bindable var viewModel: ChatViewModel
    var onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $viewModel.draft)
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
            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
