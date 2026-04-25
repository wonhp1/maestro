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
        let agentList: String
        if agents.isEmpty {
            agentList = "(아직 등록된 프로젝트 에이전트 없음)"
        } else {
            agentList = agents
                .map { entry in
                    let shortPath = entry.folderPath
                        .replacingOccurrences(of: NSHomeDirectory(), with: "~")
                    return "- **\(entry.displayName)** (id: `\(entry.agentID)`) · \(shortPath)"
                }
                .joined(separator: "\n")
        }

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

        응답 본문에 다음 형식의 태그를 포함하면 Maestro 가 자동으로 해당 에이전트에게
        메시지를 전달한다:

        ```
        RELAY_TO: <agent-id> | <위임할 작업 내용>
        ```

        예:
        ```
        파일 분석은 design-agent 에 맡기고, 결과는 다시 보고드리겠습니다.

        RELAY_TO: agent-1234 | README.md 의 디자인 챕터를 검토하고 개선점 알려줘
        ```

        여러 에이전트에 동시 위임도 가능 (한 응답에 여러 RELAY_TO 줄):
        ```
        RELAY_TO: agent-aaa | 백엔드 코드 리뷰
        RELAY_TO: agent-bbb | 프론트엔드 코드 리뷰
        ```

        위임 결과 (각 에이전트의 응답) 는 Maestro 가 자동으로 다시 너에게 전달한다.
        그 응답을 받아 사용자에게 종합한 답을 준다.

        ## 가이드라인
        - 사용자 요청이 특정 프로젝트·폴더와 연관되면 그 에이전트로 위임한다.
        - 어느 에이전트인지 불확실하면 먼저 사용자에게 확인한다.
        - **답변은 한국어**로, 구체적이고 간결하게.
        - 너 자신은 control 폴더에서 동작 — 일반 코드 작성/실행이 아닌, **오케스트레이션**이 주 역할.
        """
    }
}
