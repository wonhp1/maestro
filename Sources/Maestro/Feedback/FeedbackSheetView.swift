import AppKit
import MaestroCore
import SwiftUI

/// 사용자가 피드백 작성 → 시스템 정보 자동 첨부 → markdown 미리보기 → 클립보드 복사 +
/// GitHub Issues 페이지 열기 (자동 외부 전송 X).
///
/// Phase 23 의 `FeedbackComposer` 페이로드 빌드 + Phase 25 의 UI wiring.
struct FeedbackSheetView: View {
    let detectedAdapters: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var noteText: String = ""
    @State private var copiedFlash: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.tint)
                Text("피드백 보내기")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Text("아래 메시지에 시스템 정보가 자동 첨부됩니다. 외부 자동 전송은 없으니 안전합니다.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextEditor(text: $noteText)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            DisclosureGroup("미리보기 (Markdown)") {
                ScrollView {
                    Text(payload.renderMarkdown())
                        .font(.system(.callout, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 180)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(6)
            }

            HStack {
                if copiedFlash {
                    Label("클립보드에 복사됨", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
                Spacer()
                Button("클립보드에 복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(payload.renderMarkdown(), forType: .string)
                    withAnimation { copiedFlash = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        withAnimation { copiedFlash = false }
                    }
                }
                Button("GitHub Issues 열기") {
                    if let url = URL(string: "https://github.com/wonhp1/maestro/issues/new") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 520, height: 480)
    }

    private var payload: FeedbackPayload {
        FeedbackComposer.compose(
            userNote: noteText,
            detectedCLIs: detectedAdapters
        )
    }
}
