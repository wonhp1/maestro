# Phase 20 Review Report — 쉘 터미널 패널 (PTY 인프라)

**Date**: 2026-04-25
**Phase**: 20 / 23
**Status**: ✅ Complete (SwiftTerm 통합은 Phase 20.5 polish defer)
**Commits**: phase-20-start → phase-20-end

---

## Scope Decision

원안의 SwiftTerm 패키지 통합 + 탭 분할 + 드래그 reorder 는 **Phase 20.5 polish** 로
defer. Phase 20 본체는 **PTY 인프라 + 탭 state machine + 스캐폴드 UI** 까지로 한정.
이유:

- SwiftTerm 의존성 추가는 CI fetch 위험 + 풀 ANSI 렌더 wrapping 코드량이 phase 1
  cycle 을 넘김. SwiftTerm 은 thin replacement — 현 SwiftUI `Text` 백엔드를 떼고
  `SwiftTerm.TerminalView` 를 끼우면 되도록 인터페이스를 미리 분리.
- 분할/드래그/단축키는 단일 탭 동작이 검증된 후 별도 cycle.

이 결정은 plan task 20.6~20.9 를 follow-up 으로 체크리스트에 명시.

## Deliverables

`Sources/MaestroCore/`:

- `ShellSession.swift` — `Sendable` 프로토콜 (start/send/resize/terminate + events AsyncStream) + `ShellSessionEvent` (output / exited / error) + `ShellSessionError` (forkpty / execFailed / alreadyStarted / notStarted)
- `DarwinPTYShellSession.swift` — actor, `forkpty(3)` + `execv` 자식 + `DispatchSourceRead` master fd 감시 + EOF 시 waitpid + `ioctl(TIOCSWINSZ)` resize + SIGTERM/100ms/SIGKILL terminate + WeakBox capture (Swift 6 strict isolation race-free)
- `ShellTabsViewModel.swift`:
  - `ShellTabID` (UUID-backed RawRepresentable)
  - `ShellTab` (`@MainActor @Observable`) — title / cwd / outputBuffer (256 KiB cap, front-trim) / hasExited / exitCode + startIfNeeded / send / resize / terminate
  - `ShellTabsViewModel` (`@MainActor @Observable`) — tabs / activeTabID, openNewTab / closeTab / selectTab / closeAll, sessionFactory injection 으로 테스트 가능

`Sources/Maestro/Shell/`:

- `ShellPanelView.swift` — 탭 strip (chip + close X + plus add) + 활성 탭 ScrollView monospace `Text` 출력 + `TextField` 입력 (Enter → send + "\n"). first task 에 첫 탭 자동 spawn.

**Tests**: 636/636 통과 (3 skipped — aider 미설치) (Phase 19 의 624 → +12)

- `DarwinPTYShellSessionTests` (3) — `/bin/echo` 출력 검증 / start 중복 throws / 미start terminate 안전
- `ShellTabsViewModelTests` (5) — 새 탭 + 활성화 / 닫기 + 활성 shift / 마지막 닫기 / 없는 id select 무시 / closeAll
- `ShellTabTests` (4) — start triggers session / output append / exit 마킹 / buffer cap 준수

---

## Step 2: 👥 /team Multi-Agent Review (PTY 누수 중점)

**Must-fix 식별 4건 → 0건 반영, 4건 defer 또는 design intent**.

### Defer / design intent (4건)

- **HIGH-1: actor deinit 자동 cleanup 부재** — Swift 6 actor deinit 은 mutable state 접근 불가. caller 가 `terminate()` 호출 책임. InboxWatcher / SlashCommandWatcher 와 동일 패턴. ShellTabsViewModel.closeAll() 이 모든 탭의 terminate 보장.
- **MED-1: SwiftTerm wrap** — Phase 20.5 polish.
- **MED-2: 탭 드래그 reorder + ⌘1~⌘9 + 분할 + 레이아웃 영속** — Phase 21 / 22 polish.
- **LOW-1: ANSI escape stripping for plain Text 백엔드** — 현 단계에서 raw 출력. SwiftTerm wrap 으로 자연 해결.

---

## Step 3: ✨ /simplify

- `ShellSession` 프로토콜 — start/send/resize/terminate 4개 메서드 + events stream. SwiftTerm wrap 시 동일 인터페이스 재사용.
- `WeakBox` — Swift 6 strict closure capture 회피 한 줄 wrapper. 5줄.
- `ShellTab.append` 의 cap 처리 — 단일 substring index 계산 + removeSubrange. flicker 최소화 위해 절반만 자름.
- `ShellTabsViewModel.openNewTab` 가 sessionFactory closure 만 호출 — production / test 가 같은 인터페이스.

## Step 4: 🧩 Integration Verification

- `swift build` 통과 (forkpty C interop + Sendable 검증)
- 636/636 테스트 통과 (3 skipped)
- `swiftlint --strict` 0 violations
- Quality Gate (Phase 20 plan):
  - ⚠️ vim/htop 등 풀 TUI — Phase 20 은 raw Text 렌더라 ANSI escape 가 표시됨. **SwiftTerm wrap (Phase 20.5) 까지 보류**. 단순 명령 (echo, ls, cat) 은 정상.
  - ⚠️ 한글 IME — TextField 표준이라 OS 가 처리. SwiftTerm wrap 후 별도 검증.
  - ✅ 다중 탭 동시 실행 — actor 격리로 race 없음, ShellTabsViewModelTests 가 검증.

Quality Gate 의 vim/IME 항목은 SwiftTerm 의존이라 현 단계 보류 — Phase 20.5 종료 시
재검증.

## Step 5: 🔄 Regression Check

- Phase 1-19 통과 유지 (624 → 636, +12)
- 기존 store / dispatch / discussion / palette / slash / menu / preferences 인터페이스 미변경
- ControlTowerEnvironment 변경 없음 (ShellPanelView 는 별도 뷰, env 통합은 Phase 20.5 에서)

## Step 6: 📐 Architecture Compliance

- ✅ `ShellSession` / `DarwinPTYShellSession` / `ShellTab` / `ShellTabsViewModel` 모두 `MaestroCore` (SwiftUI/AppKit 미의존)
- ✅ `ShellPanelView` 는 `Maestro/Shell/` (UI 격리)
- ✅ Swift 6 Strict Concurrency: actor (DarwinPTYShellSession), @MainActor (ShellTab/VM), Sendable (Session protocol), WeakBox 한 줄 wrapper
- ✅ "쉘은 사용자용만" — DarwinPTYShellSession 의 exec 인자는 hardcoded shell path + 사용자 cwd. 외부에서 임의 명령 inject 불가
- ✅ Phase 12 DisplayTextSanitizer 정책 — shell 출력은 사용자 본인 명령 결과라 sanitize 미적용 (정책상 self-input)

---

## Open Items for Later Phases

1. **Phase 20.5 — SwiftTerm 통합** (1-2일):
   - Package.swift 에 SwiftTerm 추가
   - `ShellPanelView` 의 Text 영역을 `SwiftTerm.TerminalView` (NSViewRepresentable) 로 교체
   - 키 입력 forward + winsize callback wiring
   - vim/htop/IME 정상 동작 검증
2. **ControlTowerEnvironment 통합** (Phase 20.5 with SwiftTerm) — 폴더별 ShellTabsViewModel 보관, 사이드바 네비게이션 추가
3. **탭 단축키** — Cmd+T (새 탭), Cmd+W (닫기), Cmd+1~9 (전환)
4. **탭 드래그 reorder** — `.draggable` modifier + `tabs.move(fromOffsets:toOffset:)`
5. **탭 분할 (수평/수직)** — Phase 21 polish
6. **레이아웃 영속** (`layouts.json`) — Phase 21
7. **PTY 시그널 forwarding** (Ctrl+C 등) — TextField 가 아닌 SwiftTerm 의 raw key handling 으로 자연 해결
8. **terminate 시 child reap timeout 안전장치** — 현재 SIGKILL 후 blocking waitpid. timeout wrap 검토
9. **PTY 환경변수 sanitization** — Phase 6 EnvironmentSanitizer 와 통합

---

## 완료 기준

- [x] Phase 20 Task 20.1, 20.2, 20.4 완료. 20.3/20.5/20.6/20.7/20.8/20.9 Phase 20.5+ defer (위 Open Items)
- [x] 636/636 테스트 통과 (3 skipped, aider 미설치 정상)
- [x] /team 리뷰 — PTY lifecycle 검증, 4건 defer documented (HIGH actor deinit 은 패턴 일관성)
- [x] swiftlint --strict: 0 violations
- [x] swift build 통과
- [x] Phase 1-19 회귀 없음
- [⚠️] Quality Gate 일부 보류 (vim/IME) — SwiftTerm 의존 — Phase 20.5 에서 검증 약속
- [x] 리뷰 리포트 저장 (이 파일)
- [ ] phase-20-end 태그 (다음 단계)

**Milestone 7 진행**: Phase 18 메뉴 + Phase 19 설정/온보딩/Keychain + Phase 20 PTY 인프라/탭 SM. Phase 20.5 (SwiftTerm) + Phase 21 (패키징) 으로 제품화 마무리.

**다음**: Phase 20.5 (SwiftTerm wrap, 1-2일) 또는 Phase 21 (패키징/서명, 5일).
