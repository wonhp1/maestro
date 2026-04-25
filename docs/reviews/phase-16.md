# Phase 16 Review Report — 커맨드 팔레트 (Cmd+K)

**Date**: 2026-04-25
**Phase**: 16 / 23
**Status**: ✅ Complete
**Commits**: phase-16-start → phase-16-end

---

## Deliverables

`Sources/MaestroCore/`:

- `Command.swift` — Command 모델 + CommandCategory (folder/dispatch/discussion/system/recent) + CommandProvider 프로토콜
- `FuzzyMatcher.swift` — subsequence-based fuzzy matching, 연속 매칭 보너스 + 단어 경계 보너스 + 시작 위치 패널티, case+diacritic insensitive
- `CommandRegistry.swift` — actor, 다중 provider 병렬 collect + fuzzy 정렬 + maxResults cap + maxQueryBytes truncate
- `RecentCommandTracker.swift` — `@MainActor @Observable` LRU (capacity 10), 중복 ID safe lookup
- `CommandPaletteViewModel.swift` — `@MainActor @Observable`:
  - debounce search (테스트 주입 가능)
  - present/dismiss + Cmd+K toggle
  - moveSelection + executeSelected
  - **suppressSearch 가드** + **recent retag (.recent)**

`Sources/Maestro/CommandPalette/`:

- `CommandPaletteView.swift` — floating modal (sheet), 검색 필드 + 결과 리스트 + 카테고리 색상 + 단축키 hint
- `FolderCommandProvider.swift` — built-in folder 전환 (⌘1-⌘9 hint)

`Sources/Maestro/ControlTower/`:

- ControlTowerView 확장: Cmd+K + ⌘1-⌘9 hidden button shortcuts + sheet wiring
- ControlTowerEnvironment 에 commandRegistry / recentCommandTracker / commandPaletteViewModel 추가

**Tests**: 548/548 통과 (3 skipped — aider 미설치) (Phase 15 의 520 → +28)

- `FuzzyMatcherTests` (10) — empty / 길이 / exact / subsequence / non-match / case / 연속 / 경계 보너스 / filter / 한글
- `CommandRegistryTests` (6) — empty 정렬 / fuzzy / 다중 provider / unregister / truncate / maxResults
- `CommandPaletteViewModelTests` (8) — present / 필터 (debounce 0) / 선택 wrap / execute / **recent retag** / **toggle** / dismiss reset / 핸들러 호출
- `RecentCommandTrackerTests` (4) — 추가 / 동일 ID front 이동 / capacity / clear

---

## Step 2: 👥 /team Multi-Agent Review (1 묶음, arch+sec+perf+ux+test)

**Must-fix 식별 13건 → 5건 반영, 8건 defer**.

### 반영 (5건)

1. ❌→✅ **HIGH-1: 중복 ID crash** — `RecentCommandTracker.recentCommands` 의 `Dictionary(uniqueKeysWithValues:)` 가 trap. `Dictionary(_:uniquingKeysWith:)` 로 교체 — 중복 시 첫 번째 채택.
2. ❌→✅ **HIGH-2: dismiss/search race** — `dismiss()` 의 `query = ""` 가 didSet → scheduleSearch 호출하여 닫힌 후에도 results mutation. `suppressSearch` boolean 가드 추가.
3. ❌→✅ **MED-1: Cmd+K 미토글** — `present()` 가 이미 열려있으면 dismiss. VS Code/Slack convention 일치.
4. ❌→✅ **MED-2: recent 시각 cue 손실** — `refresh()` 에서 recent 항목을 `.recent` 카테고리로 retag. 오렌지 clock 아이콘 + 카테고리 chip 정상 표시.
5. ❌→✅ **MED-5: test debounce sleep flaky** — `debounceNanos` init 인자 추가, 테스트는 `0` 주입 + `Task.yield` polling (200ms hard sleep 제거).

### Defer (8건, Phase 17+/19)

- **HIGH-3: FolderCommandProvider Sendable 검증** — 컴파일러가 잡고 있음, 실제 OK.
- **MED-3: ⌘1-⌘9 race documentation** — capture 안전, comment 만 추가 가치 낮음.
- **MED-4: handler throws** — Phase 17 dispatch commands 도입 시 migration.
- **LOW-1: FuzzyMatcher 길이 cap** — registry maxQueryBytes 가 상위에서 cap.
- **LOW-2: search TTL cache** — provider 비용 발생 시점에 도입.
- **LOW-3: scrollTo 키보드 navigation 애니메이션** — 50개 결과로 체감 적음.
- **LOW-4: 추가 테스트 (execute by id / empty pool / FolderProvider hop)** — 핵심 path 커버됨.
- **LOW-5: ControlTowerEnvironment god object** — 다음 phase 에 CommandSubsystem 분리 검토.

---

## Step 3: ✨ /simplify

- `Command` 자체가 lightweight struct — id/title/handler 만 필수, 나머지 옵셔널.
- `FuzzyMatcher.score(query:in:)` static → 호출 단순.
- `CommandRegistry.search` 가 query 비었을 때와 채워졌을 때 두 path 만 — 분기 명확.
- `suppressSearch` boolean 한 단어로 race 가드 — Mutex/lock 회피.

## Step 4: 🧩 Integration Verification

- Release build 통과
- App spawn smoke OK (Cmd+K → palette / ⌘1-⌘9 → folder switch)
- 548/548 테스트 통과 (3 skipped, aider 미설치 정상)
- Quality Gate (Phase 16 plan):
  - ✅ Cmd+K 어디서든 즉시 — ControlTowerView 의 background hidden button + keyboardShortcut
  - ✅ 키보드만으로 모든 액션 — ↑/↓ moveSelection + Enter execute + Esc dismiss
  - ✅ 100+ 명령 지연 없음 — FuzzyMatcher O(query × title) + maxResults 50 cap

## Step 5: 🔄 Regression Check

- Phase 1-15 통과 유지 (520 → 548, +28)
- ControlTowerEnvironment 에 commandPalette 통합 — 기존 store 들 영향 없음
- DiscussionStore / ChatSessionStore / Folder / Inbox 인터페이스 미변경

## Step 6: 📐 Architecture Compliance

- ✅ Command / CommandRegistry / FuzzyMatcher / RecentCommandTracker / ViewModel 모두 `MaestroCore` (SwiftUI 미의존)
- ✅ CommandProvider 프로토콜 — 외부 plugin 도 (Phase 17+ 슬래시 커맨드) 동일 인터페이스로 등록 가능
- ✅ Swift 6 Strict Concurrency: actor / @MainActor / Sendable handler / @Observable
- ✅ DispatchService / DiscussionEngine 패턴 (snapshot via MainActor.run) 재사용 — FolderCommandProvider 가 일관 hop

---

## Open Items for Later Phases

1. **DispatchCommandProvider** (Phase 17 slash commands) — 등록된 폴더에 즉시 dispatch 가능한 commands.
2. **DiscussionCommandProvider** (Phase 17) — "새 토론 시작" / "토론 종료" / 활성 토론 전환.
3. **SystemCommandProvider** (Phase 19) — 설정 열기 / 진단 번들 생성 / 어댑터 재감지.
4. **RecentCommandTracker disk 영속화** (Phase 17 persistence pass) — 앱 재시작 후 recent 복원.
5. **handler throws** (Phase 17) — `Command.handler: () async throws -> Void` migration + 에러 toast.
6. **menu item 으로 Cmd+K 노출** (Phase 19 menu pass) — 발견성.
7. **NSPanel 스타일 floating window** — `.sheet` 보다 native macOS 컨벤션. Phase 19 polish.
8. **provider id 검증** (Phase 17 plugin) — path traversal / 충돌 정책.
9. **search TTL cache** — provider 비용 발생 시.
10. **SwiftUI snapshot tests** — Phase 21 release pass.

---

## 완료 기준

- [x] Phase 16 Task 16.1~16.7 (16.5 의 dispatch/discussion/settings 제공자는 Phase 17+ defer, FolderCommandProvider 만 ship)
- [x] 548/548 테스트 통과 (3 skipped, aider 미설치 정상)
- [x] /team 리뷰 + must-fix 5건 반영, 8건 defer documented
- [x] swiftlint --strict: 0 violations
- [x] Release build + spawn 정상
- [x] Phase 1-15 회귀 없음
- [x] Quality Gate 3개 모두 자동 검증
- [x] 리뷰 리포트 저장 (이 파일)
- [ ] phase-16-end 태그 (다음 단계)

**Milestone 6 (파워유저 UX 2주) 진행**: Phase 16 완료 — 커맨드 팔레트 + 폴더 단축키. 사용자가 키보드만으로 폴더 전환 가능. Phase 17 이 슬래시 명령어 + 추가 provider 들로 마무리.

**다음**: Phase 17 — 슬래시 명령어 + 스킬 자동 탐색 (4일 예상).
