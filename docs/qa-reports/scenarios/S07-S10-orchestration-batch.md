# S07 / S08 / S09 / S10 — Orchestration 일괄 검증

**상태**: ✅ ALL PASS (DispatchComposer 경로)
**실행**: 2026-04-26 02:34 KST

본 시나리오는 DispatchComposer (창 하단 "대상 선택" picker + ✈) 경로로 검증.
main chat input 경로는 별도 issue I-03 참조.

## Action

1. 사이드바 Control 폴더 선택
2. 화면 하단 DispatchComposer (대상=Control) 입력란에:
   "cfo, cmo, cto 각자에게 한 문장 자기소개 받아서 종합해줘. ROLE.md 참고."
3. ⌘+Enter
4. 90초 대기 후 control 채팅 + 자식 폴더 채팅 + 보고함 모두 확인

## Observe (control 화면)

- "[control] cfo, cmo, cto 각자에게 한 문장..." (incoming dispatch user 메시지)
- Assistant: "세 에이전트에게 동시에 요청합니다.응답이 오면 종합해서 정리해 드리겠습니다."
  → ✅ **S10 RELAY 태그 strip** (XML 안 보임)
- Assistant: ✓ **cto**: example.com의 CTO로서 회사 미션을 기술 스택으로 실증...
- Assistant: ✓ **cfo**: example.com의 CFO로 재무 목표 + 리스크 관리...
- Assistant: ✓ **cmo**: example.com의 CMO로 마케팅 전략 + 콘텐츠 설계...
  → ✅ **S08 multi-turn** — 자식 응답 follow-up 으로 정확히 도착, `✓ **{Name}**: ...` 형식

## Observe (보고함 panel)

- 빨간 4 뱃지 (control + cto + cfo + cmo envelope)
- 메시지 표시: control → cto/cfo/cmo, control → control (자기 응답)
  → ✅ **S09 Inbox routing** — recipient (envelope.to) 기준 정확. control 폴더에서 모두 종합 가능 (이전 v0.4.4 의 잘못된 sender 라우팅 fix 검증)

## Observe (cfo 폴더 클릭 — 자식 ChatView)

- You: **[Control]** ~/Desktop/sample/projects/cfo 폴더의 ROLE.md를 읽고, 한 문장으로 자기소개 해줘.
- Assistant: ROLE.md는 이미 컨텍스트에 로드되어 있습니다. 저는 example.com의 CFO로...
  → ✅ **S07 자식 ChatView dispatch sync** — `[Control]` prefix + 본문 + 응답 모두 표시
- cfo 폴더 보고함: "받은 메시지가 없습니다" — 의도된 동작 (응답 라우팅이 control 로 갔기 때문)

## JSONL 검증

- `~/.claude/projects/-...Maestro-control-cwd-/E8EA0D6D-...jsonl`: control session, RELAY_TO XML 3개 정확히 발행 (UUID 일치)
- `~/.claude/projects/-...projects-team-b/...jsonl`: cfo 새 session 생성됨 + ROLE.md 응답 기록
- 동일 cmo, cto

## Verdict

- ✅ **S06**: control RELAY 발행 (UUID 정확)
- ✅ **S07**: 자식 ChatView dispatch sync (sender label prefix)
- ✅ **S08**: multi-turn relay loop (Phase 2 fix 검증)
- ✅ **S09**: inbox routing to recipient (v0.4.5 fix 검증)
- ✅ **S10**: UI tag strip (Phase 5 fix 검증)

## ⚠️ 한정 조건

**DispatchComposer 경로만 동작**. main chat input ("메시지 입력 — Cmd+Enter") 으로 control 에 직접 입력하면 RELAY 우회 — issue I-03 (S06 시나리오 파일 참조).
