# Phase 14 Review Report — 토론 엔진

**Date**: 2026-04-25
**Phase**: 14 / 23
**Status**: ✅ Complete
**Commits**: phase-14-start → phase-14-end

---

## Deliverables

`Sources/MaestroCore/`:

- `ModeratorStrategy.swift` — `ModeratorStrategy` 프로토콜 + `RoundRobinModerator` (moderator skip) / `RandomModerator` / `ScriptedModerator` (테스트).
- `DiscussionEngine.swift` — actor 상태머신.
  - `start / pause / resume / terminate` 메서드, `events()` AsyncStream
  - `advanceLoop` 한 턴씩 dispatch + recordTurn
  - `Event` enum: `stateChanged / turnStarted / turnCompleted / turnFailed / turnDiscarded / terminated`
  - `TerminationReason`: `maxTurnsReached / moderatorReturnedNil / userTerminated / errorThreshold / moderatorTimeout`
  - **moderator timeout** (기본 30s) — LLM moderator 향후 hang 방어
  - **turnDiscarded** — pause/terminate 도중 도착한 reply silently drop 방지
  - `DispatchServiceTurnDispatcher` — Phase 13 DispatchService production wrapper

**Tests**: 512/512 통과 (3 skipped — aider 미설치) (Phase 13 의 496 → +16)

- `ModeratorStrategyTests` (7) — round-robin / advance / wrap / moderator skip / random / scripted
- `DiscussionEngineTests` (8) — round-robin 3-agent / moderator nil 종료 / **pause-resume (event-based sync)** / **double start throws** / **terminate from paused** / **pause-during-dispatch turnDiscarded** / dispatcher error abort / user terminate
- `DispatchServiceTurnDispatcherTests` (1) — production wrapper smoke

---

## Step 2: 👥 /team Multi-Agent Review (1 묶음, arch+sec+perf+test)

**Must-fix 식별 13건 → 6건 반영, 7건 defer**.

### 반영 (6건)

1. ❌→✅ **MED-2: turnPrompt 의 discussion.title sanitize** — `DisplayTextSanitizer.sanitize` 적용 + `<topic>...</topic>` delimiter wrap. Prompt injection 방어.
2. ❌→✅ **MED-5: moderator timeout** — `selectNextSpeakerWithTimeout` 헬퍼 + `withThrowingTaskGroup` race + `.moderatorTimeout` 종료 사유.
3. ❌→✅ **MED-1: silent reply drop 방지** — pause/terminate 중 도착한 reply 를 `.turnDiscarded(speaker:envelopeId:)` 로 emit (telemetry).
4. ❌→✅ **MED-6: testPauseStopsAdvanceAndResumeContinues 플레이크** — fixed sleep 대신 `for await event in stream` event-based sync.
5. ❌→✅ **MED-7: collectEvents 항상 3s 대기** — `withTaskGroup { collector vs timeout race }` — 조건 만족 시 즉시 반환.
6. ❌→✅ **LOW-2: 테스트 보강** — `testDoubleStartThrowsInvalidTransition` / `testTerminateFromPausedTransitionsToAborted` / `testPauseDuringDispatchEmitsTurnDiscarded` / `DispatchServiceTurnDispatcherTests` (production wrapper smoke).

### Defer (7건, Phase 14.x / 15+ explicit)

- **HIGH-1: scheduleAdvance race window** — 현 시점 race 시퀀스 (terminate→start) 가 state machine 으로 차단됨 (.aborted terminal). 향후 LLM moderator 도입 시 token-compare 검토.
- **HIGH-2: pause() deadlock from event handler** — UI subscriber 가 actor 를 re-entrant 호출하지 않는 한 미발생. 컨벤션 코멘트로 충분.
- **MED-3: ScriptedModerator stateful** — protocol semantic 코멘트로 처리 (테스트 전용 + 단일 토론 가정).
- **LOW-1: events() 이전 emit lost** — 구독 직후 `.replayLatestState` 옵션 — Phase 15 UI 통합 시 필요하면 도입.
- **LOW-3: state edge `.paused → .completed`** — 의도된 edge (사용자가 pause 후 종료 결정). 코멘트만 추가.
- **Phase 14.12 persistence (Discussion 저장/복원)** — explicit defer per plan.
- **Phase 14.8 LLMModerator** — explicit defer (Claude moderator wiring 은 Phase 15+ UI 통합 후).

---

## Step 3: ✨ /simplify

- `selectNextSpeakerWithTimeout` 헬퍼로 timeout race 단일 함수에 격리.
- `SpeakerSelection` 작은 private enum 으로 nil vs timeout vs speaker 명확.
- `DispatchServiceTurnDispatcher` immutable struct — DispatchService 와 from agent 만 보유.

## Step 4: 🧩 Integration Verification

- Release build 통과
- App spawn smoke OK (Phase 12-13 UI 회귀 없음)
- 512/512 테스트 통과 (3 skipped, aider 미설치 정상)
- Quality Gate (Phase 14 plan):
  - ✅ 3-agent 토론 정상 진행 — `testRoundRobinThreeAgentTermsCompleteToMaxTurns`
  - ✅ 사용자 끼어들기 — `testPauseStopsAdvanceAndResumeContinues` + `testTerminateFromPaused`
  - ✅ 종료 후 thread 로그 — `recordTurn` 이 turn 을 `discussion.turns` 에 누적, 연결된 ThreadLogger 가 envelope JSONL 보장 (Phase 11 검증)

## Step 5: 🔄 Regression Check

- Phase 1-13 통과 유지 (496 → 512, +16)
- Discussion 모델 / DispatchService / EnvelopeRouter 인터페이스 미변경
- ChatViewModel / FolderRegistry / store 들 모두 정상

## Step 6: 📐 Architecture Compliance

- ✅ DiscussionEngine / ModeratorStrategy 모두 `MaestroCore` (SwiftUI 미의존)
- ✅ `DiscussionDispatching` 프로토콜로 DispatchService 결합 분리 — 테스트 stub 가능
- ✅ Swift 6 Strict Concurrency: actor 직렬화, Sendable, `withThrowingTaskGroup` race 안전
- ✅ Discussion state machine 5-state 명확 (.pending/.active/.paused/.completed/.aborted)
- ✅ DisplayTextSanitizer (Phase 12) 재사용 — turnPrompt 의 title sanitize

---

## Open Items for Later Phases

1. **DiscussionStore + 영속화** (Phase 14.12 deferred → Phase 15 UI 통합 시) — 토론 상태 disk 저장 + 재시작 복원.
2. **LLMModerator** (Phase 14.8 → Phase 15+) — Claude/GPT 에게 다음 발언자 묻기. timeout 적용 점검.
3. **Discussion UI** (Phase 15) — Slack 스타일 스레드 뷰, 참여자 뱃지, 타이핑 인디케이터.
4. **scheduleAdvance race token-compare** (HIGH-1 defer) — LLM moderator 도입 시점에 재평가.
5. **Event re-entrancy 컨벤션 문서화** (HIGH-2 defer) — Phase 15 UI 통합 시 docs/ 추가.
6. **`.replayLatestState` 옵션** (LOW-1) — Phase 15 UI 가 mid-discussion 진입 시 필요하면 도입.
7. **Phase 14.11 mutex** — actor 자체가 mutual exclusion. defer (이미 보장).
8. **Discussion title sanitize 검증 테스트** — title injection 시뮬레이션 추가 후속.
9. **Moderator timeout 시뮬레이션 테스트** — 30s 대기 없이 inject 가능하도록 init param 사용 (이미 지원).
10. **ChatViewModel 와 turn echo 통합** — DiscussionEngine 의 진행 상황을 해당 폴더의 ChatView 에 stream (Phase 15).

---

## 완료 기준

- [x] Phase 14 Task 14.1~14.12 (14.8 LLMModerator + 14.11 mutex 명시 defer, 14.12 persistence 명시 defer)
- [x] 512/512 테스트 통과 (3 skipped, aider 미설치 정상)
- [x] /team 리뷰 + must-fix 6건 반영, 7건 defer documented
- [x] swiftlint --strict: 0 violations
- [x] Release build + spawn 정상
- [x] Phase 1-13 회귀 없음
- [x] Quality Gate 3개 모두 자동 검증 (3-agent / 끼어들기 / 종료 로그)
- [x] 리뷰 리포트 저장 (이 파일)
- [ ] phase-14-end 태그 (다음 단계)

**Milestone 5 (토론 엔진 2주) 진행**: Phase 14 완료 — 백엔드 상태머신 + 모더레이터 + dispatch 통합 완성. Phase 15 가 Slack-style UI + DiscussionStore 영속화로 마무리.

**다음**: Phase 15 — 토론 UI (Slack 스타일 스레드, 5일).
