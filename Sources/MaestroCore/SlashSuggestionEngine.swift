import Foundation

/// 입력창의 draft 문자열을 분석해 슬래시 명령 자동완성 후보를 결정하는 pure logic.
///
/// v0.7.0 Phase 2 — `ChatComposer` / `DispatchComposer` 의 `.onChange(of: draft)`
/// 에서 호출. UI 와 분리되어 있어 단위 테스트 가능 (SwiftUI test 인프라 불요).
///
/// ## 동작
/// - draft 의 **마지막 토큰** (가장 마지막 공백/줄바꿈 이후) 이 `/<query>` 형태이면
///   suggestion 반환.
/// - "토큰 닫혔다" 의 정의: 마지막 문자가 공백/줄바꿈이거나, `/` 가 아예 없음 → no suggestion.
/// - query 가 비어있으면 (`/` 만 있음) 전체 후보 반환.
/// - 매칭은 `FuzzyMatcher` 위임 — score 정렬.
public struct SlashSuggestionEngine: Sendable {
    public init() {}

    /// 자동완성 결과.
    public struct Suggestion: Sendable, Equatable {
        /// 매칭된 후보 (score 내림차순).
        public let candidates: [DiscoveredSlashCommand]
        /// draft 안에서 replace 대상 범위 (`/<query>` 부분).
        public let replaceRange: Range<String.Index>
        /// 추출된 query (선두 `/` 제외, lowercase 아님 — display 용).
        public let query: String

        public init(
            candidates: [DiscoveredSlashCommand],
            replaceRange: Range<String.Index>,
            query: String
        ) {
            self.candidates = candidates
            self.replaceRange = replaceRange
            self.query = query
        }
    }

    /// draft 분석 → suggestion 반환. nil = popup 표시 X.
    /// - registrySnapshot: `SlashCommandRegistry.snapshot()` 의 결과 (caller 가
    ///   actor await 후 전달).
    public func evaluate(
        draft: String,
        registrySnapshot: [DiscoveredSlashCommand]
    ) -> Suggestion? {
        guard let tokenStart = lastSlashTokenStart(in: draft) else { return nil }
        let query = String(draft[tokenStart...].dropFirst())  // drop "/"
        // 토큰 안에 공백/줄바꿈이 있으면 닫힌 토큰 — no suggestion.
        // (예: "/help world" → 마지막 token start 는 "/help" 시작 — 그러나 token 이 끝났음.
        //  실제로는 lastSlashTokenStart 가 마지막 공백 이후 `/` 만 잡으므로
        //  query 안엔 공백 없음 — defensive guard.)
        if query.contains(where: { $0.isWhitespace }) {
            return nil
        }

        let candidates: [DiscoveredSlashCommand]
        if query.isEmpty {
            // `/` 만 — 전체 후보 (source 우선순위 정렬 유지).
            candidates = registrySnapshot
        } else {
            let scored = FuzzyMatcher.filter(
                items: registrySnapshot,
                query: query,
                title: { $0.command.name }
            )
            candidates = scored
                .sorted { $0.score > $1.score }
                .map { $0.item }
        }

        guard !candidates.isEmpty else { return nil }

        let replaceRange = tokenStart..<draft.endIndex
        return Suggestion(
            candidates: candidates,
            replaceRange: replaceRange,
            query: query
        )
    }

    /// 사용자가 후보 선택 시 draft 갱신 결과 반환.
    /// - 인수 없는 명령: `/foo` (trailing space 없음 — Cmd+Enter 즉시 가능)
    /// - 인수 있는 명령: `/foo ` (trailing space — 사용자가 자유롭게 인수 타이핑)
    public func applySelection(
        draft: String,
        suggestion: Suggestion,
        selected: DiscoveredSlashCommand
    ) -> String {
        let hasArgs = (selected.command.arguments?.isEmpty == false)
        let replacement = hasArgs ? "/\(selected.command.name) " : "/\(selected.command.name)"
        var result = draft
        result.replaceSubrange(suggestion.replaceRange, with: replacement)
        return result
    }

    // MARK: - Private

    /// draft 의 마지막 `/` 위치 (그 이후 모두 query). nil = no `/` after last whitespace.
    /// 마지막 공백/줄바꿈 이후의 문자열에서 `/` 로 시작해야 함.
    private func lastSlashTokenStart(in draft: String) -> String.Index? {
        // 마지막 공백/줄바꿈 위치 찾기.
        let tokenStart: String.Index
        if let lastWhitespace = draft.lastIndex(where: { $0.isWhitespace }) {
            tokenStart = draft.index(after: lastWhitespace)
        } else {
            tokenStart = draft.startIndex
        }
        // 마지막 토큰이 비어있으면 (draft 가 공백으로 끝남) no suggestion.
        guard tokenStart < draft.endIndex else { return nil }
        // 마지막 토큰이 `/` 로 시작해야 함.
        guard draft[tokenStart] == "/" else { return nil }
        return tokenStart
    }
}
