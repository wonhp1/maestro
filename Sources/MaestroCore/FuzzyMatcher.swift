import Foundation

/// 간단한 subsequence-based fuzzy matcher — VS Code / Sublime 스타일.
///
/// ## 알고리즘
/// 1. query 의 각 문자가 title 에서 순서대로 등장하는지 확인 — 모두 매칭되면 score 계산.
/// 2. score 는: (a) **연속 매칭 보너스** (b) **시작 위치 패널티** (c) **단어 경계 보너스**.
/// 3. case-insensitive + diacritic-insensitive (한글 NFD/NFC 호환).
///
/// ## 보안
/// query 는 사용자 입력 — `validate` 없이 fold/lowercase 만. 길이는 caller 가 cap.
///
/// ## 성능
/// O(query.count * title.count) per match — 100 commands × 평균 30자 title × 짧은
/// query → 수만 ops, 60fps 한 frame 안에 충분.
public enum FuzzyMatcher {
    /// query 가 title 의 부분 시퀀스이면 score 반환, 아니면 nil.
    public static func score(query: String, in title: String) -> Int? {
        let normalizedQuery = normalize(query)
        let normalizedTitle = normalize(title)
        guard !normalizedQuery.isEmpty else { return 0 }
        guard normalizedQuery.count <= normalizedTitle.count else { return nil }

        let queryChars = Array(normalizedQuery)
        let titleChars = Array(normalizedTitle)

        var score = 0
        var queryIdx = 0
        var lastMatchIdx: Int = -2
        var bestStreak = 0
        var streak = 0

        for (titleIdx, char) in titleChars.enumerated() {
            guard queryIdx < queryChars.count else { break }
            if char == queryChars[queryIdx] {
                if lastMatchIdx == titleIdx - 1 {
                    streak += 1
                    score += 5  // 연속 매칭 보너스
                } else {
                    streak = 1
                    score += 1
                }
                bestStreak = max(bestStreak, streak)
                // 단어 경계 보너스
                if titleIdx == 0 || isWordBoundary(titleChars[titleIdx - 1]) {
                    score += 3
                }
                lastMatchIdx = titleIdx
                queryIdx += 1
            }
        }

        guard queryIdx == queryChars.count else { return nil }
        // 시작 위치 패널티 — 너무 뒤에서 시작한 매칭은 score 감점
        let firstMatch = titleChars.firstIndex(of: queryChars[0]) ?? 0
        score -= firstMatch / 2
        score += bestStreak * 2
        return score
    }

    /// 여러 후보 중 매칭되는 것만 score 와 함께 반환 — 정렬은 caller.
    public static func filter<T>(
        items: [T],
        query: String,
        title: (T) -> String
    ) -> [(item: T, score: Int)] {
        items.compactMap { item in
            guard let s = score(query: query, in: title(item)) else { return nil }
            return (item, s)
        }
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    private static func isWordBoundary(_ char: Character) -> Bool {
        char.isWhitespace || char == "-" || char == "_" || char == "."
            || char == "/" || char == "@"
    }
}
