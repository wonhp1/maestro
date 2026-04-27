# Implementation Plan: v0.6.0 — 마무리 + 토론 resume

**Status**: 🔄 In Progress
**Started**: 2026-04-27
**Last Updated**: 2026-04-27
**Estimated Completion**: 2026-04-27 (당일 — 약 8-10h)

---

**⚠️ CRITICAL INSTRUCTIONS**: After completing each phase:

1. ✅ Check off completed task checkboxes
2. 🧪 Run all quality gate validation commands
3. ⚠️ Verify ALL quality gate items pass
4. 📅 Update "Last Updated" date above
5. 📝 Document learnings in Notes section
6. ➡️ Only then proceed to next phase

⛔ **DO NOT skip quality gates or proceed with failing checks**

---

## 📋 Overview

### Feature Description

v0.5.x 시리즈에서 직전 명시적 요구의 **마무리 작업** + **토론 영속화의 미완성 (history-only)** 해결. 세 가지 묶음:

1. **A1 — Aider 어댑터 모델 보고**: v0.5.5 에서 `AgentAdapter.availableModels()` 프로토콜 일반화는 했지만 ClaudeAdapter 만 override. Aider 폴더 사용 시 picker 비고 헤더 정체. 사용자 명시 요구 ("다른 회사 CLI 도 마찬가지") 의 미완성.
2. **A3 — 모델 변경 즉시 반영**: 사용자가 폴더 설정 picker 에서 모델 바꿔도 현재 ChatViewModel 캐시된 동안엔 옛 모델 유지. 다음 세션 (앱 재시작/폴더 재선택) 부터 반영. UI 안내도 없음 (`FolderViewModel.changeModel` 의 `// TODO`).
3. **B4 — 토론 resume**: v0.5.4 에서 토론 디스크 영속화는 했지만 복원된 토론은 `NoopRestoreDispatcher` 라 view-only. 사용자가 옛 토론을 다시 active 로 살리거나, completed 토론에 추가 발언 트리거하는 흐름 X.

### Success Criteria

- [ ] Aider 폴더 채팅 시 헤더에 모델명 표시 + 폴더 설정에 Aider alias picker 활성
- [ ] 폴더 설정에서 모델 변경 시 명확한 UI 안내 (즉시 반영 X 인 경우) 또는 즉시 반영
- [ ] 사이드바의 옛 토론 (completed/aborted/paused) 우클릭 → "재개" 가능
- [ ] 재개된 토론에 추가 턴 보낼 수 있고 정상 dispatch (subSessions 그대로 사용)
- [ ] 총 4 phase 통과, swiftlint --strict 0 violation, 모든 기존 테스트 + 신규 통과

### User Impact

- BYOA 철학 일관성: Aider 사용자도 Claude 사용자와 같은 UX (모델 표시 + 변경)
- 토론 영속화의 진짜 가치: "기록 보기" 외 "진짜 재개" 로 작업 흐름 끊김 방지
- 사용자 혼란 감소: picker 변경의 적용 시점 명확화

---

## 🏗️ Architecture Decisions

| Decision                                                                                    | Rationale                                                                           | Trade-offs                                                                      |
| ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Aider 모델 capture: stdout 의 `Main model: <id>` 라인 파싱 (이미 stripper 가 인식)          | Aider 가 model query CLI 미제공. stdout 첫 메시지가 정보. 추가 spawn 비용 X         | parser depend on stdout format (Aider 업데이트 시 fragile) → 못 잡으면 nil 폴백 |
| Aider availableModels: hardcoded common alias (`gpt-4o`, `claude-sonnet`, `deepseek-coder`) | `aider --models <pattern>` 도 있지만 spawn cost + 사용자 환경 의존. alias 만 stable | full version 모름 (응답 capture 로 보완)                                        |
| 모델 변경 즉시 반영: ChatSessionStore.evict(folderID:) 후 사용자에게 "재시작" 버튼          | hot-swap (Session.modelId mutate) 은 어댑터 cache 재구성 위험. evict 가 가장 안전   | 사용자 한 번 click 필요 (자동 X) — 명확한 안내로 수용                           |
| 토론 resume: 복원 viewModel 의 dispatcher swap (Noop → Isolated) + 새 maxTurns              | engine 새로 만들지 않고 dispatcher 만 교체 — 기존 envelopes / subSessions 보존      | DiscussionEngine 에 setDispatcher API 필요 (지금까지 init-only)                 |
| 재개 시 새 maxTurns 다이얼로그                                                              | completed 는 `turns.count >= maxTurns` 라서 그대로면 즉시 또 completed              | UX 추가 단계 — "최대 턴 수 추가" 의도 명확                                      |

---

## 📦 Dependencies

### Required Before Starting

- [x] v0.5.6 main 브랜치 머지 (현재 HEAD)
- [x] 빌드/테스트 그린 (832 tests pass, lint 0)
- [x] DiscussionStorage / DiscussionRecord (v0.5.4)
- [x] AgentAdapter.availableModels / resolvedModel 프로토콜 (v0.5.5)

### External Dependencies

- 없음. 외부 라이브러리 추가 없이 모두 내부 변경.

---

## 🧪 Test Strategy Overview

- **단위 테스트**: 각 phase 별 RED-GREEN-REFACTOR. AiderAdapter / DiscussionEngine / DiscussionStore 신규 동작.
- **통합 테스트**: ChatViewModel 의 모델 변경 안내 흐름, DiscussionViewModel 의 resume 흐름.
- **수동 테스트**: 매 phase 후 `.app` 빌드 + 직접 GUI 검증 (특히 phase 4).
- **Coverage 목표**: 각 phase 의 새 로직 80%+, 기존 832 tests 유지.

---

## 📊 Phase Breakdown

### Phase 1 — Aider 어댑터 모델 보고 (A1)

**Goal**: Aider 폴더 채팅창 헤더 + 폴더 설정 picker 가 Claude 와 동일하게 동작.

**Test Strategy**:

- 단위: `AiderAdapter.availableModels()` 가 stable alias 반환, `resolvedModel(for:)` 가 응답에서 capture 한 lastSeen 우선 반환.
- 단위: stdout 파서가 `Main model: gpt-4o` line 에서 model id 추출.
- 코드 path: ChatViewModel 의 `refreshCurrentModel` 가 Aider 어댑터로도 정확히 동작.

**Tasks (TDD)**:

1. **RED 1.1** — `Tests/MaestroAdaptersTests/AiderAdapterTests.swift` 에 추가:
   - [ ] `testAvailableModelsReturnsStableAliases` (예: `["gpt-4o", "claude-sonnet", "deepseek-coder"]`)
   - [ ] `testResolvedModelCapturesFromMainModelLine`
   - [ ] `testResolvedModelExplicitWhenSet`
2. **RED 1.2** — `AiderModelExtractor` 단위 테스트:
   - [ ] `testExtractMainModelLine` ("Main model: gpt-4o" → "gpt-4o")
   - [ ] `testExtractReturnsNilForUnrelatedLine`
3. **GREEN 1.3** — `Sources/MaestroAdapters/AiderModelExtractor.swift` 신규:
   - [ ] `static func extractMainModel(from line: String) -> String?`
4. **GREEN 1.4** — `AiderAdapter` 확장:
   - [ ] `lastSeenModelBySession: [SessionID: String]` 캐시
   - [ ] `availableModels()` override → hardcoded alias
   - [ ] `resolvedModel(for:)` override (lastSeen 우선)
   - [ ] `sendMessage` (sync) + `driveStream` 의 stdout 라인 처리 시 `extractMainModel` 호출 + 캐시 업데이트
5. **REFACTOR 1.5** — extractor 와 stripper (`isHeaderOrFooter`) 의 prefix 리스트 중복 제거 (단일 source).

**Quality Gate**:

- [ ] swift build / swift test 통과 (+5~7 신규 tests)
- [ ] swiftlint --strict 0 violations
- [ ] 수동 검증: Aider 폴더 (사용자 환경에 있으면) 헤더 + picker 정상

**Coverage Target**: AiderModelExtractor 100%, AiderAdapter 새 경로 80%+.

**Dependencies**: 없음 (v0.5.5 어댑터 protocol 사용).

**Rollback**: AiderAdapter 의 `availableModels` / `resolvedModel` override 제거 (default impl 으로 폴백). extractor 파일 삭제.

---

### Phase 2 — 모델 변경 안내 + 즉시 적용 옵션 (A3)

**Goal**: 폴더 설정에서 모델 picker 변경 시 사용자가 변경 적용 시점을 명확히 알고, 즉시 적용 원하면 한 click.

**Test Strategy**:

- 단위: `ChatSessionStore.evict(folderID:)` 가 캐시 ChatViewModel 제거 + 콜백.
- 단위: `FolderViewModel.changeModel` 후 store 가 callback 받음.
- UI: FolderSettingsSheet 의 "변경 후 적용 안내" + "지금 재시작" 버튼.

**Tasks (TDD)**:

1. **RED 2.1** — `Tests/MaestroCoreTests/ChatSessionStoreTests.swift` (없으면 신규):
   - [ ] `testEvictRemovesCachedViewModelAndNotifies`
   - [ ] `testEvictThenEnsureCreatesFreshViewModel`
2. **RED 2.2** — `Tests/MaestroCoreTests/FolderViewModelTests.swift`:
   - [ ] `testChangeModelTriggersOnModelChangedCallback` (옵션 — store 가 폴더 변화 구독 패턴이라면 callback 단위 테스트)
3. **GREEN 2.3** — `ChatSessionStore.evict(folderID:)` 가 이미 있으면 콜백 추가, 없으면 구현:
   - [ ] `onEvicted: ((FolderID) -> Void)?` 또는 `evictedSubject` AsyncStream
4. **GREEN 2.4** — `FolderSettingsSheet` 에 안내 + "지금 재시작" 버튼:
   - [ ] modelId 변경 detection
   - [ ] save 시 `viewModel.changeModel` 후 사용자에게 "다음 세션부터 반영. 지금 적용?" 다이얼로그
   - [ ] confirm 시 `chatSessionStore.evict(folderID:)` 호출 → 다음 폴더 진입 시 새 ChatViewModel
5. **GREEN 2.5** — `FolderViewModel.changeModel` 의 `// TODO` 주석 해소 (이 phase 결과로 안내 메커니즘 마련됨).
6. **REFACTOR 2.6** — 안내 문구 i18n 친화적으로 (현재는 한국어 hardcode).

**Quality Gate**:

- [ ] swift build / swift test 통과
- [ ] swiftlint --strict 0 violations
- [ ] 수동: picker 변경 → "지금 적용" → 헤더 즉시 반영

**Coverage Target**: ChatSessionStore.evict 100%, sheet 의 새 안내 path 검증.

**Dependencies**: Phase 1 와 독립 (병렬 가능, 순차 권장).

**Rollback**: `FolderSettingsSheet` 의 안내 + 버튼 제거. ChatSessionStore.evict 콜백은 backward-compat (옵션 추가만이라 기존 경로 보존).

---

### Phase 3 — 토론 resume engine 메커니즘 (B4 part 1)

**Goal**: 디스크에서 복원된 토론 (또는 paused/completed/aborted 상태) 을 다시 active 로 살리고 새 턴 dispatch.

**Test Strategy**:

- 단위: `Discussion.transition` 매트릭스 확장 — `.completed → .active` 가 새 maxTurns 와 함께 허용. **단**, completed → active 는 의도적 사용자 액션이므로 별도 method (`Discussion.resume(addingTurns:)`) 로 분리해 일반 transition 매트릭스 보존.
- 단위: `DiscussionEngine.swapDispatcher(_:)` — Noop 에서 Isolated 로 교체 가능.
- 단위: `DiscussionStore.resume(id:engineFactory:)` — 복원된 viewModel 에 새 dispatcher + start.
- 통합: 영속화된 토론 → resume → 새 turn 발생 → 다시 영속화.

**Tasks (TDD)**:

1. **RED 3.1** — `DiscussionTests`:
   - [ ] `testResumeFromCompletedExtendsMaxTurns`
   - [ ] `testResumeFromAbortedThrows` (의도적 — aborted 는 영구 종료)
   - [ ] `testResumeFromPausedRespectsExistingMaxTurns`
2. **RED 3.2** — `DiscussionEngineTests`:
   - [ ] `testSwapDispatcherDuringResume`
3. **RED 3.3** — `DiscussionStoreSelectionTests` (또는 신규):
   - [ ] `testResumePersistedDiscussionStartsAdvancing`
4. **GREEN 3.4** — `Discussion.resume(addingTurns:)` mutating method:
   - [ ] state == .completed/.paused 만 허용
   - [ ] `.aborted` 는 throws (영구 종료 보존)
   - [ ] state → .active, maxTurns += addingTurns
5. **GREEN 3.5** — `DiscussionEngine.swapDispatcher(_:)` actor-isolated:
   - [ ] dispatcher 교체
   - [ ] 다음 advanceLoop 부터 새 dispatcher 사용
6. **GREEN 3.6** — `DiscussionStore.resume(id:dispatcherFactory:)`:
   - [ ] 캐시된 viewModel 찾음
   - [ ] discussion.resume(addingTurns:) 호출
   - [ ] dispatcherFactory 로 IsolatedTurnDispatcher 만들어 engine.swapDispatcher
   - [ ] engine.start() (paused → active 또는 completed → active 같이 작동)
   - [ ] 변화 디스크 sync (이미 polling 있음)
7. **REFACTOR 3.7** — `restoreDiscussionViewModel` 의 NoopRestoreDispatcher 와 production IsolatedTurnDispatcher 사이 transition path 명확화.

**Quality Gate**:

- [ ] swift build / swift test 통과 (+6~8 신규 tests)
- [ ] swiftlint --strict 0 violations
- [ ] 영속화 → 종료 → 재시작 → resume → 추가 턴 시나리오 수동 검증

**Coverage Target**: Discussion.resume 100%, DiscussionEngine.swapDispatcher 100%, store.resume 80%+.

**Dependencies**: v0.5.4 의 DiscussionStorage / restoreDiscussionViewModel.

**Rollback**: resume 메서드 + swapDispatcher 제거. NoopRestoreDispatcher 그대로 사용 → view-only 복원으로 되돌아감.

---

### Phase 4 — 토론 resume UI (B4 part 2)

**Goal**: 사용자가 사이드바 옛 토론 우클릭 → "재개" → maxTurns 추가 입력 → 토론 진짜 재개.

**Test Strategy**:

- 단위: `DiscussionViewModel.resume(addingTurns:dispatcherFactory:)`.
- UI: DiscussionDetailView 에 state 별 액션 ("재개" 버튼 — completed/paused 시).
- UI: 사이드바 컨텍스트 메뉴에 "재개" + "삭제" 분리.

**Tasks (TDD)**:

1. **RED 4.1** — `DiscussionViewModelTests`:
   - [ ] `testResumeFromCompletedAdvances` (resume 호출 후 turn 추가됨)
   - [ ] `testResumeFromAbortedSetsLastError`
2. **GREEN 4.2** — `DiscussionViewModel.resume(addingTurns:dispatcherFactory:)`:
   - [ ] store 의 resume API 호출
   - [ ] error → lastError surface
3. **GREEN 4.3** — `DiscussionDetailView` controlsBar 확장:
   - [ ] state == .completed → "재개 (턴 추가)" 버튼
   - [ ] state == .paused → 기존 "재개" 버튼 (이미 있음 — 동작 확인 + maxTurns 안 늘림)
4. **GREEN 4.4** — `DiscussionListView` 컨텍스트 메뉴:
   - [ ] state == .completed/.aborted/.paused 에서 "재개" 옵션
   - [ ] aborted 일 땐 disabled + tooltip
5. **GREEN 4.5** — "턴 추가" 다이얼로그:
   - [ ] Stepper 또는 TextField (예: 5 턴 추가)
   - [ ] confirm 시 viewModel.resume(addingTurns:N, dispatcherFactory: ...)
6. **GREEN 4.6** — ControlTowerEnvironment 가 dispatcherFactory 제공 (resume 시 IsolatedTurnDispatcher).
7. **REFACTOR 4.7** — `controlsBar` 의 state 분기 정리 (resume 분기 추가로 복잡해짐).

**Quality Gate**:

- [ ] swift build / swift test 통과 (+3~5 신규 tests)
- [ ] swiftlint --strict 0 violations
- [ ] 수동: 옛 토론 재개 → 새 turn 발생 → conclusion 갱신 가능 → 디스크 영속화 확인

**Coverage Target**: ViewModel.resume 100%, UI 액션 통합 검증.

**Dependencies**: Phase 3 의 store.resume + engine.swapDispatcher.

**Rollback**: ViewModel.resume + UI 추가 부분 제거. Phase 3 이 underlying 제공하므로 UI 만 hide 하면 옛 동작.

---

## 🛡️ Quality Gates (모든 phase 공통)

**Review 순서 (각 phase 마다 필수, PLAN_maestro 패턴)**:

1. 🔍 Self check (build + test + lint pass)
2. ✨ `/simplify` — 코드 단순화 / dead code / 과도한 추상화 검토 → must-fix 반영
3. 👥 `/team` — 종합 리뷰 (보안 / arch / regression / UX) → must-fix 반영
4. ➡️ 두 리뷰 통과 후 commit + push + CI watch + 다음 phase

⛔ /simplify 와 /team 둘 다 통과 못 한 채 다음 phase 진입 금지.
순서는 simplify 먼저 — dead code / 추상화 정리 후 team 이 깨끗한 surface 리뷰.

**Build & Compilation**:

- [ ] `swift build` 0 errors
- [ ] Xcode/SourceKit warning 신규 0

**TDD**:

- [ ] 각 phase 의 RED 가 실제로 fail 함을 commit 전 확인 (또는 commit message 에 RED → GREEN 흐름 기록)
- [ ] 새 코드의 단위 테스트 ≥80% line coverage
- [ ] 통합 테스트 (resume, evict) 추가

**Testing**:

- [ ] 기존 832 tests 모두 통과 (regression 0)
- [ ] 신규 테스트 12-20 개 추가
- [ ] 전체 swift test 5분 이내

**Code Quality**:

- [ ] swiftlint --strict 0 violations
- [ ] type body length / file length lint 위반 시 분리

**Functionality**:

- [ ] 매 phase 후 .app 빌드 + 직접 GUI 검증 (Phase 4 가장 중요)
- [ ] CI green (gh run watch)

**Security**:

- [ ] resume 시 새 ephemeral SessionID 발급 (subSessions 그대로 사용 — 이미 v0.5.0 design)
- [ ] 새 dispatcher 가 기존 envelopes 의 신뢰 경계 침해 X

**Performance**:

- [ ] resume 후 polling save (1초) 가 무한 turn 시나리오 부하 X — verify
- [ ] DiscussionStore.loadAllPersisted 100+ 토론 시 응답성 (lazy load 검토)

---

## ⚠️ Risk Assessment

| Risk                                                                    | Probability | Impact | Mitigation                                                                                                                    |
| ----------------------------------------------------------------------- | ----------- | ------ | ----------------------------------------------------------------------------------------------------------------------------- |
| Aider stdout format 변동 (`Main model:` 라벨 변경)                      | M           | M      | extractor nil 폴백 → resolvedModel 이 explicit ?? nil. UI 가 "감지 중…" 표시. fragile 하지만 silent-fail 안전                 |
| 모델 hot-swap 대신 evict 선택 — 사용자가 message history 잃을까 우려    | L           | M      | evict 는 ChatViewModel 만 evict, 디스크 messages (CLI 의 jsonl) 는 보존. 다음 ensureSession 시 적절히 복원 (이미 v0.4.x 동작) |
| Discussion.resume 매트릭스 확장이 기존 testAllInvalidTransitions 깨뜨림 | H           | L      | 별도 method (`resume(addingTurns:)`) 로 분리 — `transition(to:)` 매트릭스 보존. 기존 테스트 무영향                            |
| swapDispatcher 가 advanceLoop 진행 중일 때 race                         | M           | H      | actor-isolated method, advanceTask 가 active 면 cancel + await 후 swap                                                        |
| UI 의 "턴 추가" 다이얼로그가 maxTurns Int 입력 검증 누락                | L           | L      | Stepper 사용 (1-50 range 강제)                                                                                                |

---

## 🔙 Rollback Strategy

각 phase 가 독립적이고 backward-compat:

- **Phase 1**: AiderAdapter override 제거 → default impl (빈 배열 / nil) 으로 폴백. UI 변화 없음 (header 만 "감지 중…").
- **Phase 2**: FolderSettingsSheet 의 안내 + 버튼 제거. ChatSessionStore.evict 콜백은 옵션이라 그대로 둬도 무영향.
- **Phase 3**: Discussion.resume + swapDispatcher 제거. DiscussionStore.resume 제거. 옛 view-only 복원으로 되돌아감.
- **Phase 4**: UI 만 hide. underlying API (Phase 3) 는 미사용 dead code 로 남거나 같이 제거.

각 phase 별 commit 분리 → `git revert <commit-sha>` 가 가장 깔끔한 rollback.

---

## 📈 Progress Tracking

| Phase                               | Status | Started | Completed | Tests Added | Commit |
| ----------------------------------- | ------ | ------- | --------- | ----------- | ------ |
| Phase 1 — Aider 모델 보고           | ⏳     | —       | —         | —           | —      |
| Phase 2 — 모델 변경 안내            | ⏳     | —       | —         | —           | —      |
| Phase 3 — Resume engine             | ⏳     | —       | —         | —           | —      |
| Phase 4 — Resume UI                 | ⏳     | —       | —         | —           | —      |
| v0.6.0 wrap-up (version bump + DMG) | ⏳     | —       | —         | —           | —      |

---

## 📝 Notes & Learnings

### Decisions Log

- **2026-04-27** — Audit 에서 식별한 14개 후보 중 "마무리 + 토론 resume" 묶음 사용자 선택. UX 강화 / 배포 준비 / 토론 시스템 완성 은 별도 plan.

### Phase 별 Learnings (작업 후 채움)

- Phase 1: _(작업 후 기록)_
- Phase 2: _(작업 후 기록)_
- Phase 3: _(작업 후 기록)_
- Phase 4: _(작업 후 기록)_

### Open Questions / Future Work (이 plan 범위 외)

- Multi-window 지원 (D14)
- LLMModerator 활성화 (D12) — 별도 plan
- 사이드바 정렬/필터 + 메모 검색 (B6/B7) — UX 강화 묶음
- DMG 코드사이닝 + Sparkle appcast (C10/C11) — 배포 준비 묶음
