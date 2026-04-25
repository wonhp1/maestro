import Foundation
import MaestroCore

/// Aider CLI (`aider`) 의 정적 프로파일.
///
/// `aider --version` 출력 예: `aider 0.74.2` — `aider\s+([0-9]+\.[0-9]+\.[0-9]+)` 매칭.
public enum AiderProfile {
    public static let adapterID: String = "aider"
    public static let displayName: String = "Aider"
    public static let executableName: String = "aider"
    public static let versionRegex: String = #"aider\s+([0-9]+\.[0-9]+\.[0-9]+)"#

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
