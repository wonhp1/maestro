# Phase 13 Review Report — @dispatch + 양방향 보고 루프

**Date**: 2026-04-25
**Phase**: 13 / 23
**Status**: ✅ Complete
**Commits**: phase-13-start → phase-13-end

---

## Deliverables

`Sources/MaestroCore/`:

- `ReplyParser.swift` — `<REPLY_TO>` / `<RELAY_TO>` 태그 추출.
  - **input cap** (256 KiB), **fan-out cap** (8 relays/reply), **stripDispatchTags** static helper (HIGH-3 방어).
- `SystemPromptBuilder.swift` — bilingual dispatch protocol prompt section (Phase 14 어댑터 통합 예정).
- `DispatchService.swift` — actor 기반 고수준 façade.
  - `dispatch(from:to:body:expectReply:)` — 자동 sanitize (cap + 태그 strip)
  - timeout (기본 5분, withThrowingTaskGroup)
  - relay depth cap (4) + 자동 RELAY_TO 추적
  - `DispatchObserving` 프로토콜 — store wiring 분리
  - `RecordingDispatchObserver` 테스트 헬퍼
- `ControlTowerDispatchObserver.swift` — actor, Phase 12 store 들 (OrchestrationStatusModel / AgentStatusStore / InboxStore) 에 lifecycle push.
- `ChatViewModel.swift` 변경: `adapter`/`session` `nonisolated public let` 노출 (DispatchService 가 회수).

`Sources/Maestro/ControlTower/`:

- `DispatchComposer.swift` — 폴더 picker + multiline TextField + Cmd+Return send + ProgressView.
- `ControlTowerView.swift` 확장:
  - `ControlTowerEnvironment.dispatchService` — `wireDispatchService` 가 부팅 시 wiring
  - `ChatSessionAgentResolver` — 합성 AgentID 매핑 + **자동 ensureSession** (HIGH-4 방어)
  - `sendDispatch(to:body:)` — 대상 폴더 세션 ensure + dispatch
  - `safeAreaInset(edge: .bottom)` 으로 DispatchComposer mount

**Tests**: 496/496 통과 (3 skipped — aider 미설치) (Phase 12 의 477 → +19)

- `ReplyParserTests` (12) — 단일 reply / relay / mix / multiline / 잘못된 attribute / path traversal / **wide fan-out cap** / **strip nested REPLY/RELAY** / **input cap**
- `DispatchServiceTests` (7) — sendAndReceive / **timeout** / **relay** A→B→C / unknown agent skip / depth cap loop / **strip nested tags from user body** / **truncate oversized body**

---

## Step 2: 👥 /team Multi-Agent Review

### Architecture + Security Reviewer — Must-fix 4 HIGH + 6 MED + 4 LOW (5건 반영)

1. ❌→✅ **HIGH-1: DispatchComposer no length cap** — `DispatchService.dispatch` 가 `sanitizeOutgoingBody` 통해 256 KiB cap 적용.
2. ❌→✅ **HIGH-2: wide relay fan-out** — `ReplyParser.maxRelaysPerReply` (기본 8) 도입. 초과 분량은 `invalidTagCount` 로 카운트.
3. ❌→✅ **HIGH-3: nested tag injection** — `ReplyParser.stripDispatchTags` static helper. DispatchService 가 user body + relay body 모두 strip 후 envelope 생성.
4. ❌→✅ **HIGH-4: ChatSessionAgentResolver silent fail for unopened folders** — resolver 가 `ensureSession` 자동 호출. relay 가 한 번도 안 열린 폴더로 가도 정상 동작.
5. ❌→✅ **MED-2: agentToFolder double MainActor hop** — observer 의 5개 lifecycle 메서드에서 `agentToFolder` await 후 `MainActor.run` 한 번에 처리.
6. ⏭️ **MED-1: ChatViewModel adapter/session 노출** — `nonisolated public let` 로 변경 (Phase 14+ 에서 더 좁은 protocol seam 도입 검토).
7. ⏭️ **MED-3: 합성 AgentID 매핑 brittle** — Phase 14+ 에서 `FolderRegistration.agentId` 필드 도입 시 교체.
8. ⏭️ **MED-4: ReplyParser O(n²)** — HIGH-1 cap 도입으로 입력 자체가 작음. 실측 후 결정.
9. ⏭️ **MED-5: ControlTowerEnvironment 의 storage/logger inline** — Phase 14 test infra 도입 시점에 init 주입.
10. ⏭️ **MED-6: bootstrap error surface** — Phase 19 진단 화면 후보.
11. ⏭️ **LOW-1/2/3**: SystemPromptBuilder 주입 안전성 (코멘트 보강) / relaySkipped logging / 동일 envelopeId dedupe — Phase 14+/19.

### Test Reviewer (architecture+security 묶음에 통합) — Must-fix 1건 반영

- ❌→✅ **LOW-4: wide fan-out / body cap 미커버** — `testWideRelayFanoutCapped` + `testStripDispatchTagsRemovesNestedReply/Relay` + `testInputCapTruncatesAdversarialPayload` + `testDispatchStripsNestedTagsFromUserBody` + `testDispatchTruncatesOversizedBody`.

---

## Step 3: ✨ /simplify

이번 phase 의 단순화:

- `ReplyParser.parseInternal` → `extractReplies` + `extractRelays` 두 helper 로 분리 (function body length 60 line cap 준수).
- `DispatchService.sanitizeOutgoingBody` 단일 helper 로 cap + strip 통합.
- `ChatSessionAgentResolver.resolve` — MainActor 블록 + `ensureSession` 두 단계로 흐름 명확.

## Step 4: 🧩 Integration Verification

- Release build 통과
- App spawn smoke OK (DispatchComposer 하단 표시 + 폴더 선택 → 보내기 흐름)
- 496/496 테스트 통과 (3 skipped, aider 미설치 정상)
- Quality Gate (Phase 13 plan):
  - ✅ 컨트롤 타워 → CPO dispatch → 응답 자동 도착 — `testDispatchReturnsReplyEnvelope` + observer wiring (`InboxStore.record`)
  - ✅ 릴레이 A→B→C 동작 — `testRelayTriggersSecondaryDispatch`
  - ✅ 타임아웃 UI 피드백 — `dispatchTimedOut` → `OrchestrationStatusModel.recordFailure(message: "타임아웃 (5분 초과)")` → status bar 표시

## Step 5: 🔄 Regression Check

- Phase 1-12 통과 유지 (477 → 496, +19)
- ChatViewModel adapter/session 노출 변경 — 기존 caller 영향 없음 (private → public 확장)
- EnvelopeRouter / ChatSessionStore / InboxStore 인터페이스 미변경

## Step 6: 📐 Architecture Compliance

- ✅ DispatchService / ReplyParser / SystemPromptBuilder / ControlTowerDispatchObserver 모두 `MaestroCore` (SwiftUI 미의존)
- ✅ `DispatchObserving` 프로토콜 — Core ↔ store 결합 분리, 테스트 stub 가능
- ✅ Swift 6 Strict Concurrency: actor 직렬화, MainActor hop 명시, Sendable 일관
- ✅ Envelope 프로토콜 준수: schemaVersion / correlationId 보존, 정규화는 EnvelopeRouter
- ✅ 보안 레이어 일관: dispatch entry sanitize (cap + tag strip), 내부 로직은 trusted

---

## 식별된 Must-fix 요약

**총 14건 식별** (HIGH 4 + MED 6 + LOW 4) → **6건 반영, 8건 defer**

핵심 반영:

- **보안 4건**: input cap (256 KiB), wide fan-out cap (8), nested tag strip, auto ensureSession
- **퍼포먼스 1건**: agentToFolder double hop 통합
- **테스트 5건**: fan-out cap / strip / input cap / body cap / dispatch sanitize

**Defer (Phase 14+ explicit 또는 단일 사용자 trust 모델 외)**:

- ChatViewModel protocol seam (Phase 14 — 더 narrow surface)
- FolderRegistration.agentId persisted (Phase 14)
- ControlTowerEnvironment storage/logger DI (Phase 14 test infra)
- bootstrap error surface (Phase 19)
- SystemPromptBuilder injection 보안 (Phase 14 wiring + adapter system prompt 확장 시)
- relaySkipped logging (Phase 19 진단)
- envelope dedupe (Phase 14)
- ReplyParser O(n²) re-evaluation (input cap 후 자연 해결, 측정만)

---

## Open Items for Later Phases

1. **System prompt 통합** (Phase 14) — `SystemPromptBuilder.dispatchProtocolSection()` 을 ClaudeAdapter / AiderAdapter 가 createSession 시 prepend.
2. **FolderRegistration.agentId** (Phase 14) — Phase 10 deferred + Phase 13 합성 매핑 교체.
3. **ChatSessionAgentResolver → AgentResolverFactory** (Phase 14) — adapter type 별 (Claude/Aider) 다른 어댑터 인스턴스 주입.
4. **EnvelopeRouter ↔ DispatchService 통합 inbox 처리** (Phase 14) — 현재 dispatch 는 in-process. inbox 파일 drop 도 DispatchService 를 거치도록 통합.
5. **DispatchService backpressure semaphore** (Phase 14) — 다중 폴더 동시 dispatch 시.
6. **타임아웃 UI custom message** — 현재 모든 dispatch 가 5분 cap. 사용자가 "긴 작업" 표시 시 cap 늘리는 옵션.
7. **DispatchComposer 메시지 history** (Phase 17 slash commands 통합) — 위/아래 키로 이전 dispatch 재호출.
8. **릴레이 체인 시각화** (Phase 14+ — task 13.12 deferred) — ThreadView 의 inReplyTo 트리 풍부화.
9. **Reply attribution UI** — InboxItem 클릭 시 ThreadView 에서 원본 envelope 으로 jump.

---

## 완료 기준

- [x] Phase 13 Task 13.1~13.12 완료 (13.11/12 UX polish 는 explicit defer)
- [x] 496/496 테스트 통과 (3 skipped, aider 미설치 정상)
- [x] /team 리뷰 + must-fix 6건 반영 (4 HIGH 전건), 8건 defer documented
- [x] swiftlint --strict: 0 violations
- [x] Release build + spawn 정상
- [x] Phase 1-12 회귀 없음
- [x] Quality Gate 3개 모두 자동 검증
- [x] 리뷰 리포트 저장 (이 파일)
- [ ] phase-13-end 태그 (다음 단계)

**Milestone 4 (컨트롤 타워 3주) 완료**: Phase 13 까지 마무리 — 사용자가 컨트롤 타워에서 폴더(에이전트) 선택 → 보내기 → 응답 inbox + status bar 자동 표시. 릴레이도 동작.

**다음**: Phase 14 — Discussion engine 시작 (Milestone 5, 2주, 5일 예상).
