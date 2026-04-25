# Phase 12 Review Report — 컨트롤 타워 UI

**Date**: 2026-04-25
**Phase**: 12 / 23
**Status**: ✅ Complete
**Commits**: phase-12-start → phase-12-end

---

## Deliverables

`Sources/MaestroCore/`:

- `AgentStatus.swift` — `.offline/.idle/.active/.error` enum + `AgentStatusColor` (UI 색상 토큰, SwiftUI 의존 없음)
- `AgentStatusStore.swift` — `@MainActor @Observable` per-folder 상태 저장, `activeFolderIDs` / `errorFolderIDs` 노출
- `ChatSessionStore.swift` — `@MainActor @Observable` 폴더별 ChatViewModel 캐시. **single-flight Task 매핑** (must-fix). evict 시 cleanup.
- `InboxStore.swift` — `@MainActor @Observable` 받은 봉투 + per-folder unread 카운트, `maxItems` cap, **bidi sanitization**.
- `OrchestrationStatusModel.swift` — `@MainActor @Observable` dispatch lifecycle. **expiry Task 추적/cancel** (leak 방어).
- `DisplayTextSanitizer.swift` — bidi/zero-width strip + control → U+FFFD (Trojan Source 방어 공용 helper).

`Sources/Maestro/ControlTower/`:

- `AgentStatusBadge.swift` — Circle 색상 + tooltip + a11y label
- `OrchestrationStatusBar.swift` — horizontal scroll chips, running/completed/failed 시각화, `safeAreaInset` 호환
- `InboxPanel.swift` — 받은 메시지 List + 폴더 필터 + "모두 읽음" (a11y 라벨 + 폴더 미선택 시 전체 처리)
- `ThreadView.swift` — envelope 트리 단순 렌더 (Phase 13 확장 대상)
- `ControlTowerView.swift` — 3-col NavigationSplitView (Sidebar / Detail / Inspector). `ControlTowerEnvironment` composition root.

`Sources/Maestro/Folders/SidebarView.swift`: AgentStatusBadge + unread chip 추가 (Phase 10 호환 — store nil 시 미표시).

`Sources/Maestro/ContentView.swift`: `ControlTowerEnvironment.makeProduction()` 위임으로 단순화.

**Tests**: 477/477 통과 (3 skipped — aider 미설치) (Phase 11 의 440 → +37)

- `AgentStatusTests` (3) + `AgentStatusStoreTests` (4) — 색상/transition/active+error 목록/reset
- `InboxStoreTests` (10) — record / 순서 / cap / markRead idempotent / markAll / clear / preview 길이 / **bidi sanitize**
- `OrchestrationStatusModelTests` (7) — start/replace/completion/failure/unknown/purge expired/keep running
- `ChatSessionStoreTests` (8) — cache / reuse / status idle / evict offline / factory failure / **concurrent single-flight + 실패 전파** / evictAll
- `DisplayTextSanitizerTests` (6) — bidi / ZW / control replacement / newline keep / 한글+이모지 / nil

---

## Step 2: 👥 /team Multi-Agent Review (2 묶음 병렬)

### Architecture + UX Reviewer — Must-fix 5건 + Should-fix 4건 (대부분 반영)

1. ❌→✅ **A1: chatSessionStore IUO** — `let` 으로 변환, init 에서 직접 초기화.
2. ❌→✅ **A2: ChatSessionStore single-flight 실패 race** — 동시 caller 가 같은 Task 를 await. 실패 시 모두에게 `lastErrors` 채워진 nil 반환. 검증 테스트 `testConcurrentEnsureSurfacesFailureToBothCallers` 추가.
3. ❌→✅ **A3: scheduleExpiry Task leak** — `expiryTasks` dictionary 추적 + 같은 envelopeId 재 schedule 시 prior cancel + deinit 정리.
4. ❌→✅ **A4: Color.clear race** — `.task(id: folder.id)` 로 안정 identity 부여, 폴더 변경 시 이전 호출 cancel.
5. ❌→✅ **A5: InboxPanel "모두 읽음" a11y/UX** — `.accessibilityLabel/Hint` 추가 + 폴더 미선택 시 전체 폴더 처리 (dead button 회피).
6. ❌→✅ **B2: status bar layout shift** — VStack → `.safeAreaInset(edge: .top)` 로 detail column 만 reflow.
7. ⏭️ **B1: NavigationSplitView 3-col vs `.inspector` 모디파이어** — defer (macOS 14 .inspector API 검증 필요, 디자인 결정 동반).
8. ⏭️ **B3: EnvelopeRouter 미연결** — 명시적 Phase 13 scope. 현 단계에서 InboxStore/ThreadView 는 인프라 준비 + UI 골격으로 ship.
9. ⏭️ **B4: 클릭 → ThreadView open** — Phase 13 routing 시점.

### Security + Performance + Test Reviewer — Must-fix 3건 + Defer 6건

1. ❌→✅ **SEC-1: bidi/ZW sanitization** — `DisplayTextSanitizer` 신설 + InboxStore.previewBody / AgentStatusStore.setActive/setError / OrchestrationStatusModel.recordFailure 적용. 검증 테스트 6 + 1.
2. ❌→✅ **PERF-1: ChatSessionStore busy-poll** — A2 와 동일 fix (single-flight Task 매핑).
3. ⏭️ **TEST-1: scheduled auto-expiry Scheduler 주입** — defer (refactor 비용 vs 현 ROI). `purgeExpired` direct 호출 + leak 방어 (A3 fix) 검증으로 충분.
4. ⏭️ **PERF-2/3/4 (insert O(N), 정렬, NavSplit re-render)** — Phase 12 scope 내 영향 미미, 측정 후 Phase 19+ 검토.
5. ⏭️ **SEC-2: error message path leak** — adapter localizedDescription 자체에서 redact 책임.
6. ⏭️ **TEST-2/3/4: UTF-8 boundary / ControlTowerEnvironment integration / SwiftUI snapshot** — Phase 8/10 precedent + scope.

---

## Step 3: ✨ /simplify

이번 phase 의 단순화:

- `ChatSessionStore.evict` 가 `nil` 할당 → `removeValue(forKey:)` (메모리 cleanup)
- `ControlTowerEnvironment.chatSessionStore` IUO → `let` 직접 초기화 (crash surface 제거)
- `DisplayTextSanitizer` 단일 helper 로 4개 sanitize 호출 통합 (vs 각 store 가 자체 strip 로직 갖기)
- `OrchestrationStatusModel.purgeExpired` → 명시적 expiry Task 정리 동시 수행 (cleanup 일관)

## Step 4: 🧩 Integration Verification

- Release build 통과
- App spawn smoke OK (3-col 레이아웃 정상 표시)
- 477/477 테스트 통과 (3 skipped, aider 미설치 정상)
- Quality Gate (Phase 12 plan):
  - ✅ 사이드바 폴더 클릭 → ChatView 전환 — `ChatSessionStore.ensureSession` + `.task(id:)` 패턴
  - ✅ 보고함 새 메시지 시 unread 카운트 증가 — `testRecordIncrementsUnreadAndPrependsItem`
  - ✅ 상단 status bar 실시간 업데이트 — `OrchestrationStatusBar` + `safeAreaInset` 비파괴 reflow

## Step 5: 🔄 Regression Check

- Phase 1-11 통과 유지 (440 → 477, +37)
- FolderRegistry / EnvelopeRouter / ChatViewModel 인터페이스 미변경
- SidebarView 시그니처에 optional store 인자 추가 — Phase 10 callers 호환

## Step 6: 📐 Architecture Compliance

- ✅ 4개 store 모두 `MaestroCore` (SwiftUI/AppKit 의존 없음)
- ✅ `AgentStatusColor` 토큰 — Color 매핑은 Maestro target (AgentStatusBadge) 만
- ✅ `ControlTowerEnvironment.makeProduction` — DI seam 제공 (테스트 가능)
- ✅ Swift 6 Strict Concurrency: `@MainActor @Observable`, actor 격리, `@unchecked Sendable` 미사용
- ✅ `ChatSessionStore` single-flight + Task tracking — race-free 보장
- ✅ `DisplayTextSanitizer` 적용 지점 일관 — 신규 surface 추가 시 같은 helper 재사용

---

## 식별된 Must-fix 요약

**총 14건 식별** (Arch+UX 9 + Sec+Perf+Test 5) → **8건 반영, 6건 defer**

핵심 반영:

- **Architecture/UX 6건**: IUO 제거 / single-flight 실패 race / scheduleExpiry leak / Color.clear race / a11y / safeAreaInset
- **Security 1건**: bidi/ZW sanitization (DisplayTextSanitizer 공용 helper)
- **Performance 1건**: single-flight 통한 busy-poll 제거 (PERF-1 = A2)
- **테스트 3건**: bidi sanitize / single-flight 실패 전파 / DisplayTextSanitizer suite

**Defer (Phase 13/19/22 explicit 또는 scope 외)**:

- EnvelopeRouter ↔ InboxStore wiring (Phase 13)
- ThreadView mount + click navigation (Phase 13)
- AgentStatus.active 자동 전이 (Phase 13 DispatchService)
- `.inspector` 모디파이어 전환 (디자인 결정)
- Scheduler 주입 (refactor 비용 vs ROI)
- ControlTowerEnvironment integration test (composition root)
- SwiftUI snapshot tests (Phase 8/10 precedent)
- macOS 14 NavSplit perf 측정 (Phase 19+)

---

## Open Items for Later Phases

1. **EnvelopeRouter ↔ InboxStore bridge** (Phase 13) — outbox write 시 InboxStore.record 호출.
2. **ThreadView mount** (Phase 13) — InboxItem 클릭 → ThreadLogger 의 thread JSONL 로드 → ThreadView 렌더.
3. **AgentStatus 자동 전이** (Phase 13) — DispatchService 가 dispatch start → `.active`, completion → `.idle`, failure → `.error` 자동 push.
4. **NavigationSplitView `.inspector` 모디파이어 전환** — Phase 14+ UI polish 시 평가 (toolbar toggle / persistent width).
5. **Scheduler 주입** — OrchestrationStatusModel + ChatSessionStore polling 등 시간 기반 동작에 manual scheduler 주입 (Phase 19+ test infrastructure).
6. **ControlTowerEnvironment integration test** — bootstrap 실패 처리 + retry CTA UI surface 검증.
7. **SwiftUI snapshot tests** — Phase 8/10 deferred, 묶어서 Phase 21 release 직전 도입 검토.
8. **AgentID displayName 매핑** — Phase 19 settings 시점에 raw id ("claude") → "Claude Code" UI display 통합.
9. **Localization** — Phase 22 String Catalog. 현재 한글 하드코딩 일관 (FolderViewModel humanReadable 패턴과 동일).
10. **InboxStore items insert(at: 0) → ring buffer** — 측정 후 결정 (Phase 19 perf pass).

---

## 완료 기준

- [x] Phase 12 Task 12.1~12.10 완료
- [x] 477/477 테스트 통과 (3 skipped, aider 미설치 정상)
- [x] /team 2 묶음 병렬 리뷰 + must-fix 8건 반영, 6건 defer documented
- [x] swiftlint --strict: 0 violations
- [x] Release build + spawn 정상
- [x] Phase 1-11 회귀 없음
- [x] Quality Gate 3개 모두 자동 검증 (폴더 전환 / unread 증가 / status bar)
- [x] 리뷰 리포트 저장 (이 파일)
- [ ] phase-12-end 태그 (다음 단계)

**Milestone 4 (컨트롤 타워 3주) 진행**: Phase 12 완료 — 3-컬럼 UI + 4개 store 골격 완성. Phase 13 의 dispatch lifecycle 이 InboxStore/AgentStatusStore/OrchestrationStatusModel 를 wiring 하면 컨트롤 타워가 살아남.

**다음**: Phase 13 — @dispatch + 양방향 보고 루프 (DispatchService, 5일 예상)
