import Foundation

/// 에이전트에게 주입할 시스템 프롬프트의 표준 섹션 — Maestro 의 dispatch 프로토콜을
/// 알리는 텍스트.
///
/// ## 사용
/// 어댑터가 createSession 또는 sendMessage 시점에 system prompt 에 prepend.
/// (현 phase 에서는 builder 만 제공 — 어댑터 통합은 Phase 14 에서 systemPrompt
/// override 인자 추가 시 wiring.)
///
/// ## 프로토콜 안내
/// - 응답에 `<REPLY_TO=envelope-id>본문</REPLY_TO>` 사용 시 명시적 reply 처리.
/// - 다른 에이전트로 위임 시 `<RELAY_TO=agent-name>지시 내용</RELAY_TO>`.
/// - 위임이 필요 없는 일반 답변은 태그 없이 그대로 작성.
///
/// 프롬프트는 한국어/영어 bilingual — 모델 다국어 지원 보장.
public enum SystemPromptBuilder {
    /// dispatch 프로토콜 섹션을 반환. 다른 시스템 프롬프트에 prepend/append.
    public static func dispatchProtocolSection() -> String {
        """
        ## Maestro 디스패치 프로토콜 / Dispatch Protocol

        당신은 Maestro 의 멀티 에이전트 환경에서 동작합니다. 다음 태그를 활용하세요:

        1. 명시적 응답 — 받은 봉투(envelope)에 답할 때:
           <REPLY_TO=envelope-id>
           응답 본문 (markdown 가능)
           </REPLY_TO>

        2. 다른 에이전트로 위임 — A→B→C 같은 릴레이가 필요할 때:
           <RELAY_TO=agent-name>
           위임할 지시 내용
           </RELAY_TO>

        규칙:
        - 위 태그가 필요 없는 일반 답변은 그대로 작성하세요. 태그를 강제로 넣지 마세요.
        - envelope-id 와 agent-name 은 반드시 받은 메시지에 명시된 값만 사용하세요.
        - 태그 안 본문에는 평문 markdown 만 작성. 코드 블록은 ``` fenced 로.

        — — —

        You are operating within Maestro's multi-agent environment. Use these tags:

        1. Explicit reply — when responding to a specific envelope:
           <REPLY_TO=envelope-id>
           response body (markdown allowed)
           </REPLY_TO>

        2. Relay to another agent — when delegation (A→B→C) is needed:
           <RELAY_TO=agent-name>
           delegated instructions
           </RELAY_TO>

        Rules:
        - For ordinary answers that need neither tag, just write the response. Do not force tags.
        - Use only envelope-ids and agent-names that appear in the received message.
        - Inside tags, use plaintext markdown only. Code blocks via ``` fences.
        """
    }
}
