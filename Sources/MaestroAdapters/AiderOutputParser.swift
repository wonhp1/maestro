import Foundation

/// Aider 의 `--no-pretty` plain stdout 에서 어시스턴트 응답만 추출.
///
/// ## 출력 형식 가정 (Aider 0.7x 기준)
/// ```
/// Aider v0.74.2
/// Main model: claude-sonnet-4-5 with diff edit format
/// Git repo: .git with 3 files
/// Repo-map: using 1024 tokens
/// Added /path/to/file.py to the chat.
///
/// > <user message echo>
///
/// <assistant response — plain text or markdown, 여러 줄>
///
/// Tokens: 1.2k sent, 234 received. Cost: $0.01
/// ```
///
/// ## 추출 규칙 (defensive — Aider 버전 변동에 robust)
/// - 마지막에 등장하는 `> ` prefix 라인 (user echo) 다음부터 시작.
/// - `Tokens:` / `Cost:` / `Commit ` 으로 시작하는 footer 라인 직전에서 종료.
/// - 시작/종료 빈 줄 trim.
/// - user echo 가 없으면: `===== user =====` / `========` 등의 구분선 폴백 시도. 그도 없으면
///   stdout 전체에서 헤더 prefix (`Aider v`, `Main model:`, `Git repo:`, ...) 라인만 제거.
public enum AiderOutputParser {
    /// Aider stdout → 어시스턴트 응답 본문.
    public static func extractAssistantResponse(from stdout: String) -> String {
        let normalized = stdout.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n" as Character, omittingEmptySubsequences: false)
            .map(String.init)

        if let body = extractBetweenUserEchoAndFooter(lines: lines) {
            return body
        }
        return stripKnownHeaderLines(lines: lines)
    }

    /// 명시적 에러 시그니처 (auth 실패, model not found 등) 가 stdout 에 있는지 검사.
    public static func detectKnownError(in stdout: String) -> String? {
        let lower = stdout.lowercased()
        let needles = [
            "litellm.exceptions.authenticationerror",
            "openai.authenticationerror",
            "anthropic.authenticationerror",
            "no api key",
            "missing api key",
            "could not find your api key",
            "invalid api key",
            "rate limit",
            "model not found",
        ]
        for needle in needles where lower.contains(needle) {
            return needle
        }
        return nil
    }

    // MARK: - Internals

    private static func extractBetweenUserEchoAndFooter(lines: [String]) -> String? {
        // **첫** `> ` (user echo) 위치 — 마지막을 쓰면 assistant 의 markdown blockquote
        // (`> note:`) 가 anchor 가 되어 본문이 잘림 (Phase 9 must-fix).
        var firstUserEchoIdx: Int?
        for (idx, line) in lines.enumerated() where line.hasPrefix("> ") {
            firstUserEchoIdx = idx
            break
        }
        guard let startIdx = firstUserEchoIdx else { return nil }
        var endIdx = lines.count
        for idx in (startIdx + 1)..<lines.count where isFooterLine(lines[idx]) {
            endIdx = idx
            break
        }
        let slice = Array(lines[(startIdx + 1)..<endIdx])
        return trimBlanks(slice).joined(separator: "\n")
    }

    private static func isFooterLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("Tokens:")
            || trimmed.hasPrefix("Cost:")
            || trimmed.hasPrefix("Commit ")
            || trimmed.hasPrefix("Applied edit to")
    }

    /// 알려진 헤더 prefix 라인들을 제거하고 나머지 본문 join. 폴백 경로.
    private static func stripKnownHeaderLines(lines: [String]) -> String {
        let headerPrefixes = [
            "Aider v", "Main model:", "Weak model:", "Editor model:",
            "Git repo:", "Repo-map:", "Added ", "Tokens:", "Cost:",
            "VSCode:", "Update:",
        ]
        let kept = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return true }
            return !headerPrefixes.contains { trimmed.hasPrefix($0) }
        }
        return trimBlanks(kept).joined(separator: "\n")
    }

    /// 시퀀스 양 끝의 빈/공백 라인을 제거.
    private static func trimBlanks(_ lines: [String]) -> [String] {
        var result = lines
        while let first = result.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            result.removeFirst()
        }
        while let last = result.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            result.removeLast()
        }
        return result
    }
}
