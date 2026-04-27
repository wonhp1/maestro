import MarkdownUI
import SwiftUI

/// v0.5.1 — Maestro 채팅 + 토론에서 공통으로 쓰는 MarkdownUI Theme.
///
/// MarkdownUI 의 기본 테마 (`.basic`) 는 macOS 시스템 폰트와 spacing 이 약간
/// 책 같은 분위기 — 채팅 가독성을 위해:
/// - 헤더는 약간 더 작게 (h1=title2, h2=title3, h3=headline)
/// - 코드 블록 배경 색 + monospaced
/// - 인용 좌측 색 막대
/// - 단락 spacing 늘림
/// - 표 셀 padding/divider
extension Theme {
    /// MainActor 격리 — SwiftUI Color 접근이 MainActor 일 수 있어서.
    @MainActor
    static let maestro: Theme = Theme()
        .text {
            FontFamilyVariant(.normal)
            FontSize(.em(1.0))
            ForegroundColor(.primary)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.92))
            BackgroundColor(.codeInline)
        }
        .strong { FontWeight(.semibold) }
        .emphasis { FontStyle(.italic) }
        .link { ForegroundColor(.accentColor) }
        .heading1 { configuration in
            VStack(alignment: .leading, spacing: 0) {
                configuration.label
                    .markdownMargin(top: .em(0.6), bottom: .em(0.3))
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(.em(1.4))
                    }
                Divider()
            }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.6), bottom: .em(0.25))
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.25))
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.5), bottom: .em(0.2))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.1))
                }
        }
        .paragraph { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.18))
                .markdownMargin(top: .em(0.3), bottom: .em(0.3))
        }
        .blockquote { configuration in
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 3)
                configuration.label
                    .relativeLineSpacing(.em(0.18))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .codeBlock { configuration in
            VStack(alignment: .leading, spacing: 0) {
                if let lang = configuration.language, !lang.isEmpty {
                    Text(lang)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .relativeLineSpacing(.em(0.18))
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.9))
                        }
                        .padding(8)
                }
            }
            .background(Color.codeBlock)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .markdownMargin(top: .em(0.4), bottom: .em(0.4))
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.1), bottom: .em(0.1))
        }
        .table { configuration in
            configuration.label
                .markdownTableBorderStyle(
                    .init(color: Color.secondary.opacity(0.4))
                )
                .markdownTableBackgroundStyle(
                    .alternatingRows(Color.clear, Color.secondary.opacity(0.06))
                )
                .markdownMargin(top: .em(0.4), bottom: .em(0.4))
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 { FontWeight(.semibold) }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
        }
}

private extension Color {
    /// 인라인 코드 배경 — 라이트/다크 모두 자연스러운 회색.
    static var codeInline: Color { Color.secondary.opacity(0.18) }
    /// 코드 블록 배경 — 인라인 보다 약간 어두움.
    static var codeBlock: Color { Color.secondary.opacity(0.12) }
}
