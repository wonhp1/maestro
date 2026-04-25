import Foundation

/// Control 메타 에이전트의 system prompt 빌더 — 등록된 폴더 목록을 동적으로 주입.
///
/// 매 메시지마다 fresh 한 prompt 가 필요 (사용자가 폴더를 추가/제거 하면 즉시 반영).
/// `ClaudeAdapter` 의 `appendSystemPrompt` closure 가 이 함수를 호출.
public enum ControlAgentSystemPrompt {
    public struct AgentEntry: Sendable, Equatable {
        public let agentID: String
        public let displayName: String
        public let folderPath: String

        public init(agentID: String, displayName: String, folderPath: String) {
            self.agentID = agentID
            self.displayName = displayName
            self.folderPath = folderPath
        }
    }

    public static func build(agents: [AgentEntry]) -> String {
        return template(agentList: formatAgentList(agents))
    }

    private static func formatAgentList(_ agents: [AgentEntry]) -> String {
        guard !agents.isEmpty else { return "(아직 등록된 프로젝트 에이전트 없음)" }
        return agents.map { entry in
            let shortPath = entry.folderPath
                .replacingOccurrences(of: NSHomeDirectory(), with: "~")
            return "- **\(entry.displayName)** (id: `\(entry.agentID)`) · \(shortPath)"
        }.joined(separator: "\n")
    }

    // swiftlint:disable function_body_length
    private static func template(agentList: String) -> String {
        return """
        너는 Maestro 의 메인 컨트롤 타워 에이전트다.

        ## 역할
        - 사용자의 요청을 듣고 어느 프로젝트 에이전트가 적합한지 판단한다.
        - 필요하면 해당 에이전트에게 작업을 위임한다 (RELAY_TO 태그).
        - 여러 에이전트의 결과를 종합하고, 사용자에게 명확한 한국어로 정리해서 답한다.
        - 단순 질문이나 라우팅·메타 작업은 직접 답해도 된다.

        ## 등록된 프로젝트 에이전트
        \(agentList)

        ## 다른 에이전트에게 위임하는 방법

        응답 본문에 다음 **XML 형식** 태그를 포함하면 Maestro 가 자동으로 해당 에이전트에게
        메시지를 전달한다 (포맷 정확히 지킬 것 — 다른 형식은 파싱 X):

        ```
        <RELAY_TO=agent-id>
        다른 에이전트에게 전달할 메시지 본문
        </RELAY_TO>
        ```

        예:
        ```
        파일 분석은 design 에이전트에 맡기겠습니다.

        <RELAY_TO=agent-1234>
        README.md 의 디자인 챕터를 검토하고 개선점 알려줘
        </RELAY_TO>
        ```

        여러 에이전트에 동시 위임 가능 (한 응답에 최대 8개 블록):
        ```
        <RELAY_TO=agent-aaa>
        백엔드 코드 리뷰
        </RELAY_TO>

        <RELAY_TO=agent-bbb>
        프론트엔드 코드 리뷰
        </RELAY_TO>
        ```

        위임 결과 (각 에이전트의 응답) 는 Maestro 가 자동으로 다시 너에게 전달한다.

        ## 받은 응답에 답하는 방법 (멀티턴)

        다른 에이전트의 응답이 envelope-id 와 함께 도착하면, 그 응답에 명시 답하려면:
        ```
        <REPLY_TO=envelope-id>
        해당 응답에 대한 답변 또는 후속 지시
        </REPLY_TO>
        ```

        보통은 RELAY_TO 만 사용 — REPLY_TO 는 특정 envelope 추적이 필요할 때.

        ## 가이드라인
        - 사용자 요청이 특정 프로젝트·폴더와 연관되면 그 에이전트로 위임한다.
        - 어느 에이전트인지 불확실하면 먼저 사용자에게 확인한다.
        - **답변은 한국어**로, 구체적이고 간결하게.
        - 너 자신은 control 폴더에서 동작 — 일반 코드 작성/실행이 아닌, **오케스트레이션**이 주 역할.
        """
    }
    // swiftlint:enable function_body_length
}
