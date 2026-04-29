import Foundation
import MaestroCore

/// v0.9.0 — OpenAI Codex CLI (`codex`) 의 정적 프로파일.
///
/// `codex --version` 출력 예: `codex-cli 0.125.0` — `\d+\.\d+\.\d+` 패턴 매칭.
///
/// ## 인증
/// 두 가지 흐름 지원:
/// - **OAuth (구독)**: `codex login` 명령 → ChatGPT Plus/Pro 구독 토큰 풀 사용
/// - **API key**: `OPENAI_API_KEY` 환경변수 또는 `codex login --with-api-key`
///
/// ## 비대화형 모드
/// `codex exec [PROMPT]` — Maestro 가 사용. `--json` 으로 JSONL 출력.
public enum CodexProfile {
    public static let adapterID: String = "codex"
    public static let displayName: String = "Codex (OpenAI)"
    public static let executableName: String = "codex"
    /// `codex-cli 0.125.0` 형식. 첫 매치된 semver 추출.
    public static let versionRegex: String = #"\b([0-9]+\.[0-9]+\.[0-9]+)\b"#

    /// `CLIDetector` 가 사용하는 정적 프로파일.
    public static func makeProfile(executable: String = executableName) throws -> AgentProfile {
        AgentProfile(
            adapterId: try AdapterID.validated(rawValue: adapterID),
            displayName: displayName,
            executable: executable,
            detectArgs: ["--version"],
            versionRegex: versionRegex,
            invokeArgs: []  // 동적 argv — adapter 내부 빌드
        )
    }
}
