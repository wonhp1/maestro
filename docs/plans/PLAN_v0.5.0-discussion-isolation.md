# Implementation Plan: v0.5.0 — 토론 격리 + 영구 메모 layer

**Status**: 🔄 In Progress
**Started**: 2026-04-27
**Last Updated**: 2026-04-27
**Estimated Completion**: 2026-04-28
**Total estimate**: 11h (5 phase + 사전 fix)

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

Maestro 의 토론 (Discussion) 이 현재 자식 폴더의 메인 claude session 을 공유 → 토론 발언이 자식의 일반 채팅 컨텍스트를 오염시키고 있다. control-kim 프로젝트의 토론 design 을 참고해:

1. 토론마다 참가자별 **새 ephemeral subSession** 생성 (자식 메인 세션 격리)
2. 사회자 (control) 가 토론 종료 시 **결론 자동 요약**
3. 사용자가 결론을 **수정 가능** (textarea + "다시 요약" 버튼)
4. 사용자가 공유 대상 자식을 **명시적 선택** + 공유 시 자식 메인 세션에 typing
5. **옵션 C — 영구 메모 layer**: 토론 단위 단일 .md 파일 + frontmatter 의 `sharedWith` 로 자식 매핑 + ClaudeAdapter 호출 시 활성 메모를 systemPrompt 에 자동 append (정정/삭제 가능 + 토큰 효율 + BYOA 철학 유지)

### Success Criteria

- [ ] 토론 시작 시 참가자 모두 **새 sessionId 생성** (folders.json 의 메인 sessionId 와 다름)
- [ ] 자식 폴더 직접 채팅 → 토론과 무관한 컨텍스트 유지
- [ ] 토론 종료 시 control 이 결론 자동 생성 + 사용자 textarea 편집 가능
- [ ] 사용자가 공유 대상 chip 선택 후 "공유" → 선택한 자식의 메인 세션에 메시지 한 turn 추가
- [ ] 영구 메모 파일 (`~/Library/Application Support/Maestro/discussion-memos/<id>.md`) 가 frontmatter `sharedWith` 로 자식 매핑
- [ ] 자식 claude 호출 시 자기 folderId 가 sharedWith 에 있는 모든 메모를 systemPrompt 로 자동 append
- [ ] 메모 파일 수정/삭제 시 다음 호출부터 즉시 반영
- [ ] 폴더 이름 hardcode 0개 (어떤 도메인 (개발팀/게임팀 등) 폴더든 동일 작동)
- [ ] 사용자 프로젝트 파일 (CLAUDE.md, ROLE.md, .git, etc.) 변경 0건

### Architecture Decisions

| 결정                                                                            | 대안                                 | 선택 이유                                             |
| ------------------------------------------------------------------------------- | ------------------------------------ | ----------------------------------------------------- |
| 토론 ephemeral session 발급 (control-kim 동일)                                  | 자식 메인 session 공유               | 컨텍스트 오염 방지 + 토큰 효율                        |
| 메모 = 토론별 단일 파일                                                         | 자식별 파일 N 개                     | 결론 정정 시 1 곳만 수정, 중복 X                      |
| 메모 frontmatter `sharedWith: [folder-id]`                                      | 별도 index.json                      | 메모 자체에 매핑 — 단일 source of truth               |
| 메모 = 사용자 polder 의 CLAUDE.md 가 아닌 별도 파일                             | CLAUDE.md 자동 추가                  | BYOA — 사용자 폴더 안 건드림                          |
| ClaudeAdapter `appendSystemPromptProvider` 시그니처 변경 (folderPath -> String) | 새 ClaudeAdapter instance per folder | 단일 adapter 재사용, 메모 layer 간단                  |
| 공유 = 자식 메인 ChatViewModel.send 호출                                        | DispatchService.dispatch             | UI sync 자연스러움 (자식 chat 에 user turn 으로 보임) |

---

## 📅 Phase Breakdown

### Phase 0: 사전 — displayName fix commit + push + CI (15min)

**Goal**: 미커밋 displayName fix (이미 빌드 + 검증 완료) 의 commit + push + CI 통과 확인.

**Tasks**:

- [ ] 0.1 git status 확인 (5 파일 변경 예상)
- [ ] 0.2 commit message 작성 + push
- [ ] 0.3 CI 결과 monitor + PASS 확인

**Quality Gate**:

- [ ] `gh run list --limit 1` → success
- [ ] /Applications/Maestro.app 이 latest 빌드와 동기화

---

### Phase 1: Discussion 모델 + 영속 형식 확장 (2h)

**Goal**: `Discussion` struct 에 `subSessions`, `conclusion`, `sharedWith`, `sharedAt` 필드 추가. 옛 형식 영속 데이터 마이그레이션 (필드 nil 으로 디코딩).

**Test Strategy**: 단위 — JSON encode/decode round-trip + 옛 형식 backward-compat (subSessions 없는 옛 jsonl 디코딩 시 빈 dict).

**Tasks (TDD)**:

- [ ] **RED 1.1** `DiscussionTests.testDecodeWithoutSubSessions` — 옛 형식 디코딩 시 subSessions 빈 dict
- [ ] **RED 1.2** `DiscussionTests.testRoundtripPreservesSubSessions` — subSessions 채워넣고 encode→decode round-trip
- [ ] **RED 1.3** `DiscussionTests.testRoundtripPreservesConclusionAndShare` — conclusion + sharedWith + sharedAt round-trip
- [ ] **GREEN 1.4** Discussion struct 필드 추가 (`subSessions: [AgentID: SessionID]`, `conclusion: String?`, `sharedWith: [AgentID]?`, `sharedAt: Date?`)
- [ ] **GREEN 1.5** Codable manual init(from:) — 옛 형식 fallback
- [ ] **GREEN 1.6** mutating helpers: `setSubSession(for:)`, `setConclusion(_:)`, `recordShare(targets:at:)`
- [ ] **REFACTOR 1.7** DiscussionStore.save 가 새 필드 영속

**Coverage Target**: 100% (Discussion + DiscussionStore 단위 테스트 — 신규 / 기존 모두)

**Quality Gate**:

- [ ] swift build
- [ ] swift test (전체 + 신규 3 테스트 PASS)
- [ ] swiftlint --strict 0 violations
- [ ] folders.json 같은 다른 영속 데이터 영향 X

**Dependencies**: 없음 (Phase 0 만 commit 끝나면 시작 가능)

**Rollback**: `git revert <phase1-commit>` — 옛 Discussion 데이터는 fallback 으로 그대로 작동

---

### Phase 2: 토론 dispatch 격리 — DiscussionTurnDispatcher (2.5h)

**Goal**: 토론에서만 사용되는 `DiscussionTurnDispatcher` 도입. ClaudeAdapter 직접 호출 with ephemeral subSessionId. 자식의 메인 ChatViewModel + sessionId 와 분리.

**Test Strategy**: 통합 — Stub adapter 로 dispatch 호출 시 어떤 sessionId 사용하는지 검증. 토론 끝나도 자식 메인 session 변경 X.

**Tasks (TDD)**:

- [ ] **RED 2.1** `DiscussionTurnDispatcherTests.testUsesSubSessionId` — Discussion.subSessions[speaker] 가 ClaudeAdapter.createSession 의 preferredSessionId 로 전달
- [ ] **RED 2.2** `DiscussionTurnDispatcherTests.testDoesNotMutateMainSession` — folder.sessionId 가 토론 dispatch 후에도 동일
- [ ] **RED 2.3** `DiscussionEngineIsolationTests.testStartGeneratesSubSessions` — start() 시 모든 참가자 subSessions 채워짐
- [ ] **GREEN 2.4** `DiscussionTurnDispatcher` 구현 (DiscussionDispatching 프로토콜 따름, ClaudeAdapter resolver 받음)
- [ ] **GREEN 2.5** DiscussionEngine.start 시 `for participant in participants { discussion.subSessions[participant] = SessionID.new() }`
- [ ] **GREEN 2.6** ControlTowerEnvironment+Dispatch 가 DispatchServiceTurnDispatcher 대신 DiscussionTurnDispatcher wiring
- [ ] **REFACTOR 2.7** 옛 DispatchServiceTurnDispatcher deprecate (제거는 phase 4 후)

**Coverage Target**: 단위 ≥80% — DiscussionTurnDispatcher / DiscussionEngine.start 신규 path

**Quality Gate**:

- [ ] swift build + 795 + 신규 테스트 PASS
- [ ] swiftlint --strict 0
- [ ] **GUI scenario**: 토론 시작 → cfo 발언 → JSONL 확인 (ephemeral session jsonl 새로 생성, folders.json 의 cfo sessionId 변동 X)

**Dependencies**: Phase 1

**Rollback**: revert + 옛 DispatchServiceTurnDispatcher 복귀

---

### Phase 3: 결론 자동 요약 + 사용자 편집 UI (2h)

**Goal**: 토론 종료 시 control 사회자가 결론 8-12줄 요약. DiscussionDetailView 에 textarea (편집 가능) + "✨ 다시 요약" 버튼.

**Test Strategy**: 단위 — summarizeConclusion 이 control adapter 호출 + 결과 Discussion.conclusion 에 set. UI 는 snapshot 보다는 functional (button click → mock summarize 호출).

**Tasks (TDD)**:

- [ ] **RED 3.1** `DiscussionEngineSummarizeTests.testSummarizeUpdatesConclusion` — control adapter mock 응답 받아 Discussion.conclusion set
- [ ] **RED 3.2** `DiscussionEngineSummarizeTests.testSummarizeRequiresAtLeastOneTurn` — 빈 토론은 summarize skip
- [ ] **GREEN 3.3** DiscussionEngine.summarizeConclusion(id:) — control 의 ephemeral sessionId 로 dispatch (build prompt: "아래 토론을 8-12줄 결론...")
- [ ] **GREEN 3.4** DiscussionViewModel.summarize() — engine 호출 + lastError handling
- [ ] **GREEN 3.5** DiscussionDetailView 에 결론 영역 (textarea + 다시 요약 버튼)
- [ ] **GREEN 3.6** 토론 status .completed 또는 .aborted 시 자동 summarize 1회 호출 (control-kim 의 awaiting_conclusion 단계 대응)
- [ ] **REFACTOR 3.7** UI 컴포넌트 file_length 검토

**Coverage Target**: ≥75% (UI 부분은 mock 위주)

**Quality Gate**:

- [ ] build + test + lint
- [ ] **GUI**: 토론 진행 → 종료 → DetailView 결론 영역에 자동 요약 표시 + textarea 편집 가능 확인 + "다시 요약" 동작

**Dependencies**: Phase 2 (control dispatch 가 작동 중이어야 summarize 호출 가능)

**Rollback**: revert — 결론 영역만 빠지고 토론 자체는 정상

---

### Phase 4: 공유 흐름 — 자식 메인 세션 typing (2h)

**Goal**: 사용자가 chip 으로 공유 대상 자식 선택 후 "공유" 버튼 → 각 대상 자식의 ChatViewModel.send 또는 DispatchService 로 메시지 한 turn 주입.

**Test Strategy**: 단위 — share() 가 targets 마다 dispatch 호출. 통합 — share 후 Discussion.sharedWith / sharedAt 영속.

**Tasks (TDD)**:

- [ ] **RED 4.1** `DiscussionEngineShareTests.testShareDispatchesToEachTarget` — targets [cfo, cmo] 면 두 dispatch 호출 됐는지 verify
- [ ] **RED 4.2** `DiscussionEngineShareTests.testShareRecordsSharedWith` — Discussion.sharedWith == targets, sharedAt == now
- [ ] **RED 4.3** `DiscussionEngineShareTests.testShareSkipsIfNoConclusion` — conclusion nil 이면 skip + error
- [ ] **GREEN 4.4** DiscussionEngine.share(targets:) — 각 자식의 메인 session 으로 dispatchService.dispatch 호출 with prefix+conclusion+suffix
  - prefix: `[토론 #<id> 결론 공유]\n주제: <topic>\n\n`
  - suffix: `\n\n앞으로 이 맥락을 기억해주세요.`
- [ ] **GREEN 4.5** DiscussionViewModel.share(targets:) — engine 호출
- [ ] **GREEN 4.6** DiscussionDetailView 에 참가자 chip (toggle) + "공유" 버튼 + 공유 후 결과 메시지
- [ ] **REFACTOR 4.7** 옛 DispatchServiceTurnDispatcher 제거 (phase 2 deprecate 마무리)

**Coverage Target**: ≥80% (share path)

**Quality Gate**:

- [ ] build + test + lint
- [ ] **GUI**: 토론 종료 → 결론 자동 요약 → chip 으로 cfo+cmo 선택 → 공유 → cfo/cmo 폴더 들어가면 "[토론 #... 결론 공유]" turn 표시 + 자식 응답 확인

**Dependencies**: Phase 3

**Rollback**: revert — 공유 버튼만 빠지고 토론 자체는 정상

---

### Phase 5: 영구 메모 layer (옵션 C) (3h)

**Goal**: 토론별 영구 메모 파일 + 자식 호출 시 자동 systemPrompt append + 메모 편집/삭제 UI.

**Test Strategy**: 단위 — AgentMemoStore 의 read/write/delete + frontmatter parse. 통합 — ClaudeAdapter 가 호출 시 적절한 메모만 systemPrompt 에 포함.

**Tasks (TDD)**:

- [ ] **RED 5.1** `AgentMemoStoreTests.testWriteAndReadMemo` — 메모 파일 생성 + 읽기
- [ ] **RED 5.2** `AgentMemoStoreTests.testFrontmatterParsing` — sharedWith / topic / timestamps 파싱
- [ ] **RED 5.3** `AgentMemoStoreTests.testActiveMemosForFolder` — folderId 기준 sharedWith 포함된 메모만 반환
- [ ] **RED 5.4** `AgentMemoStoreTests.testDeleteRemovesFile` — 삭제 후 active 에서 제외
- [ ] **GREEN 5.5** AppSupportPaths.discussionMemosDir 추가 + ensureAllDirectoriesExist 등록
- [ ] **GREEN 5.6** `AgentMemoStore` actor (CRUD + active filter) — frontmatter YAML-lite parsing (간단한 key:value 헤더, 본문은 markdown)
- [ ] **GREEN 5.7** ClaudeAdapter.appendSystemPromptProvider 시그니처 확장 (folderPath 받게) — 또는 별도 `appendSystemPromptResolver: (URL) async -> String?`
- [ ] **GREEN 5.8** ClaudeAdapter buildArguments 가 folderPath 기반 메모 lookup → systemPrompt 에 append (기존 control 동적 prompt 와 합침)
- [ ] **GREEN 5.9** DiscussionEngine.share 에 옵션 — "메모로 영구 저장" 토글 ON 시 AgentMemoStore.write 호출
- [ ] **GREEN 5.10** DiscussionDetailView 에 메모 토글 + 자식 폴더 우클릭 메뉴 또는 Settings 에 "메모 보기/편집" 화면
- [ ] **REFACTOR 5.11** UI 컴포넌트 + AgentMemoStore file_length 검토

**Coverage Target**: ≥80% (AgentMemoStore + ClaudeAdapter 통합)

**Quality Gate**:

- [ ] build + test + lint
- [ ] **GUI scenario 1**: 토론 결론 공유 + "메모로 저장" ON → discussion-memos/<id>.md 파일 생성 확인
- [ ] **GUI scenario 2**: 자식 (cfo) 한테 새 dispatch → cfo claude 가 메모 내용 알고 답변 (예: "토론 결론에 따르면...")
- [ ] **GUI scenario 3**: 메모 파일 사용자가 수정 → 다음 cfo dispatch 에서 수정된 내용 반영
- [ ] **GUI scenario 4**: 메모 sharedWith 에서 cfo 제거 → cfo dispatch 시 메모 안 보임 (cmo 는 그대로 봄)

**Dependencies**: Phase 1, 2, 3, 4 모두

**Rollback**: revert — 메모 layer 만 빠지고 토론/공유 자체는 정상

---

## ⚠️ Risk Assessment

| Risk                                                                               | Probability | Impact | Mitigation                                                        |
| ---------------------------------------------------------------------------------- | ----------- | ------ | ----------------------------------------------------------------- |
| Discussion 영속 형식 변경 → 옛 토론 데이터 손상                                    | M           | M      | Decoder 옛 형식 fallback (Phase 1 RED 1.1 테스트)                 |
| ClaudeAdapter `appendSystemPromptProvider` per-call 동적 변경 어려움               | M           | H      | 시그니처를 `(URL) async -> String?` 으로 변경 (Phase 5 GREEN 5.7) |
| 토론 ephemeral session 생성 시 race condition                                      | L           | M      | actor 격리 + sessionId 발급 시 main actor 보장                    |
| 메모 layer UI feature creep                                                        | M           | M      | Phase 5 시간 cap (3h), 추가 기능은 별도 라운드                    |
| 자식 PTY 직접 typing (control-kim 패턴) 가 SwiftUI / Maestro 의 dispatch 와 어긋남 | L           | M      | dispatch 경유 (control-kim 은 PTY, Maestro 는 dispatch — 더 안전) |
| Discussion / DispatchService 의 thread isolation 변경 → 기존 테스트 깨짐           | M           | M      | RED 단계에서 미리 잡고 GREEN 으로 fix                             |
| 메모 systemPrompt 누적 → 토큰 폭증                                                 | L           | L      | UI 에 "메모 비우기" + 항목 삭제 제공 + 사용자 책임 영역           |

---

## 🔄 Rollback Strategy

각 Phase 가 1 commit 으로 isolated. 문제 시 `git revert <commit-sha>` 로 단일 phase 만 되돌림.

특수 케이스:

- **Phase 1 데이터 손상**: `~/Library/Application Support/Maestro/threads` 의 백업본으로 복구. 옛 형식 fallback decoder 가 있어서 데이터 손실은 거의 없음.
- **Phase 5 메모 파일 손상**: `~/Library/Application Support/Maestro/discussion-memos/` 폴더 삭제하면 reset 됨 (자식 메인 session 영향 X).

---

## 📊 Progress Tracking

| Phase | Status | 시작 | 종료 | Commit |
| ----- | ------ | ---- | ---- | ------ |
| 0     | ⏳     |      |      |        |
| 1     | ⏳     |      |      |        |
| 2     | ⏳     |      |      |        |
| 3     | ⏳     |      |      |        |
| 4     | ⏳     |      |      |        |
| 5     | ⏳     |      |      |        |

상태: ⏳ 대기 / 🔄 진행 중 / ✅ 완료 / ❌ 실패

---

## 📝 Notes & Learnings

각 phase 완료 시 여기에 기록:

- 예상 vs 실제 시간
- 변경 시 어려움
- 새로 발견한 issue
- 다음 phase 에 영향
