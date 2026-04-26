# S06: Control RELAY_TO 발행 (+ S07 자식 sync, S08 multi-turn 의 prerequisite)

**상태**: ⚠️ PARTIAL — RELAY 발행은 OK, 자식 dispatch 안 됨 (아키텍처 갭)
**실행**: 2026-04-26 02:27 KST

## Action

Control 폴더 선택 → 메인 채팅 input ("메시지 입력 — Cmd+Enter") 에:

> "cfo, cmo, cto 각자에게 한 문장으로 자기소개 받아서 종합해줘. 각자 본인의 ROLE.md 를 참고하면 돼."
> → ⌘+Enter

## Observe

**Control 채팅 응답 (UI 표시)**:

> 세 에이전트에게 동시에 자기소개를 요청하겠습니다. 세 에이전트의 응답이 오면 종합해서 정리해 드리겠습니다.

- ✅ RELAY_TO 태그 strip (UI 깨끗)

**JSONL 직접 확인** (`E8EA0D6D-95DB-...jsonl`):

```
AS: 세 에이전트에게 동시에 자기소개를 요청하겠습니다.
<RELAY_TO=agent-e9f67443-ea0b-...>~/Desktop/sample/projects/cto 폴더의 ROLE.md를 참고해서, 한 문장으로 자기소개 해줘.</RELAY_TO>
<RELAY_TO=agent-4b72fbf8-8fe4-...>~/Desktop/sample/projects/cfo ...</RELAY_TO>
<RELAY_TO=agent-9f41ee1b-a582-...>~/Desktop/sample/projects/cmo ...</RELAY_TO>
세 에이전트의 응답이 오면 종합해서 정리해 드리겠습니다.
```

- ✅ control 가 정확한 UUID 로 3개 RELAY_TO 발행

**자식 폴더 JSONL** (~/.claude/projects):

- cto / cfo / cmo 의 새 JSONL 안 생김 (test 시작 후 5분 지났는데도)

**Inbox**:

- `~/Library/Application Support/Maestro/inbox/` 비어있음

## 진단 — 🔴 진앙

**ChatViewModel.send 흐름이 DispatchService 를 우회한다.**

흐름 분석:

- 사용자가 main chat input ("메시지 입력") 에 타이핑 → ⌘Enter
- ChatViewModel.send → adapter.streamMessage(envelope, in: session) → 응답 표시
- 응답이 ChatMessage 로만 보존, **DispatchService.dispatch 호출 X** → ReplyParser 가 RELAY_TO 를 보지 않음 → 자식 dispatch 안 일어남

다른 흐름 (DispatchComposer 하단 — "대상 선택" picker + ✈ 버튼):

- ControlTowerEnvironment.sendDispatch → dispatchService.dispatch → router → ReplyParser → relays 처리
- 이 경로로만 multi-turn 가능

**사용자 직관 불일치**: control 의 채팅창에서 직접 대화하는 게 자연스러운데 RELAY 가 안 동작.

## Fix proposal (v0.4.7)

control 폴더의 ChatViewModel 은 send 시 **두 가지 동시** 트리거:

1. 평소대로 adapter.streamMessage (UI 표시 유지)
2. 응답 완료 후 ReplyParser.parse(reply.body) → relays 가 있으면 각 자식에게 DispatchService.dispatch
3. 자식 응답 → control's ChatView 에 follow-up assistant 메시지로 append (Phase 2 의 appendRelayResult 재사용)

또는 control 폴더 전용 ChatViewModel 변형 — `ControlChatViewModel: ChatViewModel` 가 dispatch 자동 트리거.

## Verdict

- S06 (RELAY 발행) ✅ — control 가 정상 발행
- S07 (자식 sync), S08 (multi-turn), S09 (inbox routing) — 모두 검증 불가, **이 버그 의존**

→ **Active issue I-03** 등록.

## 우회로 시도 예정

DispatchComposer (창 하단 대상 picker) 로 보내면 dispatch 흐름. 그 경로로 S07/S08/S09 검증 시도 후 본 시나리오에 결과 추가.
