import Foundation
import MaestroCore

/// v0.9.0 — Google Gemini CLI (`gemini`) 의 정적 프로파일.
///
/// `gemini --version` 출력 예: `0.40.0` — `\d+\.\d+\.\d+` 패턴 매칭.
///
/// ## 인증
/// - **OAuth (자동)**: 첫 실행 시 브라우저 자동 오픈 → Google 계정 로그인
///   → `~/.gemini/oauth_creds.json` 자동 생성. 별도 `gemini auth login` 명령 X.
/// - **API key**: `GEMINI_API_KEY` 환경변수
///
/// ## 비대화형 모드
/// `gemini -p "<PROMPT>" -o stream-json --skip-trust` — Maestro 가 사용.
public enum GeminiProfile {
    public static let adapterID: String = "gemini"
    public static let displayName: String = "Gemini (Google)"
    public static let executableName: String = "gemini"
    public static let versionRegex: String = #"\b([0-9]+\.[0-9]+\.[0-9]+)\b"#

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
