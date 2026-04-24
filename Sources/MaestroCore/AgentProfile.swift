import Foundation

/// CLI 어댑터의 **정적 프로파일** — 감지 방법, 버전 파싱, 실행 argv 템플릿.
///
/// ## 보안 핵심
/// 실행 인자는 **문자열 템플릿이 아닌 argv 배열** (`[InvokeArg]`) 로 모델링.
/// Shell 을 거치지 않고 `Process.arguments` 에 그대로 넘길 수 있어 **shell 인젝션
/// 자체가 불가능**. `body`, `sessionId`, `folderPath` 같은 LLM/사용자 입력이
/// 자유롭게 스페셜 문자를 포함해도 안전.
///
/// ## 구성
/// - `adapterId`: 짧은 식별자 (`claude`, `aider`, ...).
/// - `executable`: 실행 파일 이름 (`claude`). PATH 에서 찾음.
/// - `detectArgs`: 설치 감지용 argv (예: `["--version"]`).
/// - `versionRegex`: detect stdout 에서 버전 추출 패턴.
/// - `invokeArgs`: 실행 argv 템플릿. `.literal` / `.placeholder` 혼용.
///
/// - Phase 4 에서 `AgentAdapter` 가 이 프로파일을 소비.
/// - Phase 6 의 `ProcessRunner` 가 `Process.arguments = renderedArgv` 로 호출.
public struct AgentProfile: Codable, Hashable, Sendable {
    public let adapterId: AdapterID
    public let displayName: String
    public let executable: String
    public let detectArgs: [String]
    public let versionRegex: String
    public let invokeArgs: [InvokeArg]

    public init(
        adapterId: AdapterID,
        displayName: String,
        executable: String,
        detectArgs: [String],
        versionRegex: String,
        invokeArgs: [InvokeArg]
    ) {
        self.adapterId = adapterId
        self.displayName = displayName
        self.executable = executable
        self.detectArgs = detectArgs
        self.versionRegex = versionRegex
        self.invokeArgs = invokeArgs
    }
}

/// argv 의 각 원소 — 리터럴 또는 플레이스홀더.
public enum InvokeArg: Codable, Hashable, Sendable {
    /// 그대로 전달되는 리터럴. 예: `"-p"`, `"--resume"`.
    case literal(String)
    /// 런타임 치환될 플레이스홀더. 이름으로 참조. 예: `.placeholder("prompt")`.
    case placeholder(String)
}

public extension AgentProfile {
    /// 플레이스홀더를 실제 값으로 치환하여 `[String]` argv 생성.
    /// 누락된 키가 있으면 throws — `Process.arguments` 전달 직전 반드시 성공해야 함.
    func renderArgv(substitutions: [String: String]) throws -> [String] {
        var rendered: [String] = []
        for arg in invokeArgs {
            switch arg {
            case .literal(let value):
                rendered.append(value)
            case .placeholder(let name):
                guard let value = substitutions[name] else {
                    throw AgentProfileError.unresolvedPlaceholder(name: name)
                }
                rendered.append(value)
            }
        }
        return rendered
    }

    /// 사람이 읽기 위한 **디스플레이 전용** 렌더. Process 에 절대 전달하지 말 것.
    /// 인자는 공백으로 join 되며 이스케이프 없음 — 로그/UI 미리보기에만 사용.
    func displayCommand(substitutions: [String: String] = [:]) -> String {
        let parts: [String] = invokeArgs.map { arg in
            switch arg {
            case .literal(let value):
                return value
            case .placeholder(let name):
                return substitutions[name] ?? "{\(name)}"
            }
        }
        return ([executable] + parts).joined(separator: " ")
    }

    /// 플레이스홀더 이름 목록 (중복 제거, 순서 유지).
    var placeholderNames: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for arg in invokeArgs {
            if case .placeholder(let name) = arg, !seen.contains(name) {
                seen.insert(name)
                ordered.append(name)
            }
        }
        return ordered
    }
}

public enum AgentProfileError: Error, Equatable {
    case unresolvedPlaceholder(name: String)
}
