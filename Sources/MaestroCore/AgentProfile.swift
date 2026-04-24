import Foundation

/// CLI 어댑터의 **정적 프로파일** — 감지 방법, 버전 파싱, 실행 템플릿.
///
/// - 사용자 머신에 어떤 CLI 가 설치되어 있는지 알려주고, 실행 시 인자를 어떻게
///   조합할지 규정한다. Phase 4 에서 `AgentAdapter` 가 이 프로파일을 소비.
/// - 프로파일 자체는 순수 데이터 — 런타임 상태를 갖지 않는다.
public struct AgentProfile: Codable, Hashable, Sendable {
    /// 짧은 식별자. Adapter 매칭 키. 예: `"claude"`, `"aider"`.
    public let adapterId: String
    /// UI 에 표시할 이름. 예: `"Claude Code"`.
    public let displayName: String
    /// 설치 여부 감지용 명령. 예: `"claude --version"`.
    public let detectCommand: String
    /// `detectCommand` 출력에서 버전을 추출할 정규식.
    public let versionRegex: String
    /// 실행 명령 템플릿. `{placeholder}` 구문으로 치환.
    /// 예: `"claude -p {prompt} --resume {session}"`
    public let invokeTemplate: String

    public init(
        adapterId: String,
        displayName: String,
        detectCommand: String,
        versionRegex: String,
        invokeTemplate: String
    ) {
        self.adapterId = adapterId
        self.displayName = displayName
        self.detectCommand = detectCommand
        self.versionRegex = versionRegex
        self.invokeTemplate = invokeTemplate
    }
}

public extension AgentProfile {
    /// 치환 키를 템플릿에 적용 (관대한 버전 — 누락된 키는 그대로 남김).
    func renderInvokeCommand(substitutions: [String: String]) -> String {
        var result = invokeTemplate
        for (key, value) in substitutions {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }

    /// 치환 키를 엄격하게 적용 (누락 시 throws). 실행 직전 호출에 사용.
    func strictInvokeCommand(substitutions: [String: String]) throws -> String {
        let rendered = renderInvokeCommand(substitutions: substitutions)
        if let name = AgentProfile.firstPlaceholder(in: rendered) {
            throw AgentProfileError.unresolvedPlaceholder(name: name)
        }
        return rendered
    }

    private static func firstPlaceholder(in text: String) -> String? {
        guard
            let openIndex = text.firstIndex(of: "{"),
            let closeIndex = text[openIndex...].firstIndex(of: "}")
        else {
            return nil
        }
        let range = text.index(after: openIndex)..<closeIndex
        return String(text[range])
    }
}

public enum AgentProfileError: Error, Equatable {
    case unresolvedPlaceholder(name: String)
}
