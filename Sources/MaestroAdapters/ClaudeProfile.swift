import Foundation
import MaestroCore

/// Claude Code CLI (`claude`) 의 정적 프로파일.
///
/// `claude --version` 출력 예: `2.1.118 (Claude Code)` — `\d+\.\d+\.\d+` 패턴 매칭.
public enum ClaudeProfile {
    public static let adapterID: String = "claude"
    public static let displayName: String = "Claude Code"
    public static let executableName: String = "claude"
    public static let versionRegex: String = #"\b([0-9]+\.[0-9]+\.[0-9]+)\b"#

    /// `CLIDetector` 가 사용하는 정적 프로파일.
    public static func makeProfile(executable: String = executableName) throws -> AgentProfile {
        AgentProfile(
            adapterId: try AdapterID.validated(rawValue: adapterID),
            displayName: displayName,
            executable: executable,
            detectArgs: ["--version"],
            versionRegex: versionRegex,
            invokeArgs: []  // 동적 argv — adapter 내부에서 빌드
        )
    }
}
