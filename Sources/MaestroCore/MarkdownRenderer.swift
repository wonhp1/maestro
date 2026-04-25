import Foundation

/// Markdown 텍스트를 SwiftUI `Text` 가 직접 렌더 가능한 `AttributedString` 으로 변환.
///
/// Foundation 의 `AttributedString(markdown:options:)` 위에 얹은 얇은 래퍼. SwiftUI Text
/// 는 limited markdown (`**bold**`, `*italic*`, `` `code` ``, links) 만 인라인 지원하므로
/// `.full` 옵션 + `returnPartiallyParsedIfPossible` 정책으로 최대한 보존.
///
/// ## 코드 블록
/// SwiftUI `Text` 는 multiline code block (` ```...``` `) 을 인라인으로 렌더하지 못함.
/// 호출자는 code block 을 별도 view 로 분리 (Phase 8 `MessageBubbleView` 참조).
public enum MarkdownRenderer {
    /// 허용 URL 스킴 — `javascript:`/`file:` 등 위험 스킴 차단 (Phase 8 sec must-fix).
    private static let allowedLinkSchemes: Set<String> = ["http", "https", "mailto"]

    /// 마크다운 → AttributedString. 위험 URL 스킴 자동 제거 + 비-가시 bidi 제거.
    public static func render(_ markdown: String) -> AttributedString {
        let sanitizedSource = stripBidiControls(markdown)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard var attr = try? AttributedString(markdown: sanitizedSource, options: options) else {
            return AttributedString(sanitizedSource)
        }
        for run in attr.runs where run.link != nil {
            let scheme = run.link?.scheme?.lowercased() ?? ""
            if !allowedLinkSchemes.contains(scheme) {
                attr[run.range].link = nil
            }
        }
        return attr
    }

    /// AttributedString 의 plain text 추출 — 접근성 / 검색용.
    public static func plainText(_ markdown: String) -> String {
        String(render(markdown).characters)
    }

    /// **Trojan Source 방어** — bidi override / isolate / zero-width 제어 문자 제거.
    /// CodeBlockView 가 같은 입력에 호출.
    public static func stripBidiControls(_ text: String) -> String {
        let dangerous: Set<Character> = [
            "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",  // RLE/LRE/PDF/LRO/RLO
            "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",              // LRI/RLI/FSI/PDI
            "\u{200E}", "\u{200F}",                                       // LRM/RLM
            "\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}",              // ZWSP/ZWNJ/ZWJ/BOM
        ]
        return String(text.filter { !dangerous.contains($0) })
    }

    // MARK: - Code block extraction

    /// Markdown 본문을 segment 시퀀스로 분할. UI 가 code block 을 별도 view 로 렌더할 때 사용.
    public enum Segment: Hashable, Sendable {
        case prose(String)
        case codeBlock(language: String?, code: String)
    }

    /// ` ```lang\n...\n``` ` 코드 블록을 segment 로 분리. 매칭이 없으면 [.prose(원본)].
    /// fence 는 정확히 줄 시작의 ` ``` ` 만 인식 (인라인 ``` 는 무시).
    /// CRLF 입력도 안전 처리 (Phase 8 must-fix).
    public static func segments(_ markdown: String) -> [Segment] {
        var segments: [Segment] = []
        var prose = ""
        var inCode = false
        var codeBuffer = ""
        var codeLanguage: String?

        // CRLF 정규화 — Swift 의 grapheme 단위 split 이 "\r\n" 을 단일 cluster 로
        // 다루기 때문에 사전에 LF only 로 통일.
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        for rawLine in normalized.split(
            separator: "\n" as Character,
            omittingEmptySubsequences: false
        ) {
            let line = String(rawLine)
            if line.hasPrefix("```") {
                if inCode {
                    segments.append(.codeBlock(language: codeLanguage, code: codeBuffer))
                    codeBuffer = ""
                    codeLanguage = nil
                    inCode = false
                } else {
                    if !prose.isEmpty {
                        segments.append(.prose(prose.trimmingNewlineOnly()))
                        prose = ""
                    }
                    let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLanguage = lang.isEmpty ? nil : lang
                    inCode = true
                }
                continue
            }
            if inCode {
                if !codeBuffer.isEmpty { codeBuffer += "\n" }
                codeBuffer += line
            } else {
                if !prose.isEmpty { prose += "\n" }
                prose += line
            }
        }
        // 마감 fence 누락 — 남은 buffer 를 prose 로 합쳐 datalose 방지.
        if inCode {
            let trailing = codeBuffer.isEmpty ? "" : "\n```\(codeLanguage ?? "")\n\(codeBuffer)"
            prose += trailing
        }
        if !prose.isEmpty {
            segments.append(.prose(prose.trimmingNewlineOnly()))
        }
        return segments
    }
}

private extension String {
    /// 끝의 newline 만 trim — 본문의 trailing space 는 보존.
    func trimmingNewlineOnly() -> String {
        var s = self
        while s.last == "\n" { s.removeLast() }
        return s
    }
}
