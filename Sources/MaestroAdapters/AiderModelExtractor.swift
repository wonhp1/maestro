import Foundation

/// v0.6.0 Phase 1 — Aider stdout 의 `Main model: <id> ...` 라인에서 모델 ID 추출.
///
/// Aider 는 ClaudeAdapter 와 달리 JSON 응답 모드가 없어 model 정보 query 가 없음.
/// 대신 stdout 첫 부분에 `Main model: gpt-4o with diff edit format ...` 같은
/// header 라인을 출력 — 그걸 휴리스틱하게 파싱.
///
/// 패턴: "Main model: " 뒤 첫 토큰 (whitespace 까지).
///
/// 한계: Aider 가 라벨 형식 변경 시 fragile. nil 반환 (silent fail) → adapter 가
/// fallback (sessionId 의 modelId 또는 nil → UI 가 "감지 중…").
public enum AiderModelExtractor {
    /// 한 라인에서 model id 추출. 매칭 안 되면 nil.
    public static func extractMainModel(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefix = "Main model:"
        guard trimmed.hasPrefix(prefix) else { return nil }
        let rest = trimmed.dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespaces)
        // 첫 whitespace 까지 = model id (그 뒤는 "with diff edit format ..." 등 metadata).
        // split (omittingEmptySubsequences=default true) 가 빈 first 안 줌 → 추가 가드 불요.
        return rest.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }

    /// stdout 에서 model 추출. **앞부분만 scan** — Aider header 는 항상 처음 ~10 줄
    /// 안에 위치하므로 16MiB 전체 traverse 불필요 + 중간 LLM 응답이 "Main model:"
    /// 라벨 echo 했을 때 spoofing 방어 (display 만 영향이지만).
    public static func extractFromStdout(_ stdout: String) -> String? {
        let scanWindow = stdout.prefix(8192)
        for line in scanWindow.split(separator: "\n", omittingEmptySubsequences: true) {
            if let model = extractMainModel(from: String(line)) {
                return model
            }
        }
        return nil
    }
}
