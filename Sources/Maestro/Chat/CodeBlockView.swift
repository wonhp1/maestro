import MaestroCore
import SwiftUI

/// Markdown 코드 블록 단일 렌더 — monospaced + 배경 + 옵션 언어 라벨.
/// **Phase 8 sec must-fix**: bidi/zero-width 제어 문자 strip — Trojan Source 방어.
struct CodeBlockView: View {
    let language: String?
    let code: String

    private var sanitizedCode: String {
        MarkdownRenderer.stripBidiControls(code)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(sanitizedCode)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
