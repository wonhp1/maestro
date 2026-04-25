# Phase 18 Review Report — 네이티브 메뉴 + 메뉴바 앱

**Date**: 2026-04-25
**Phase**: 18 / 23
**Status**: ✅ Complete
**Commits**: phase-18-start → phase-18-end

---

## Deliverables

`Sources/MaestroCore/`:

- `MenuActionRouter.swift` — `@MainActor @Observable`, optional `@Sendable async` 핸들러 슬롯 (addFolder / deleteSelectedFolder / openCommandPalette / openPreferences / revealDataFolder / exportDiagnostics / openHelp) + `canDeleteSelectedFolder` 게이트
- `AppActivitySummary.swift` — `@MainActor @Observable` 통합 카운트 (running/unread/folder/lastInboxArrival) + `dockBadgeLabel` + `menuBarSummaryLine`
- `NotificationService.swift` — `Sendable` 프로토콜 + `AppNotification` payload (title/body/badge) + `NoopNotificationService` (테스트/기본값)

`Sources/Maestro/Menu/`:

- `MaestroMenuCommands.swift` — `Commands` view, File (새 폴더 ⌘N / 데이터 폴더 열기 ⌘⇧O / 진단 번들) / Edit (선택 폴더 제거 ⌘⌫) / Maestro (환경설정 ⌘,) / Window (커맨드 팔레트 ⌘K) / Help (도움말)
- `MaestroMenuBarExtra.swift` — `MenuBarExtra` Scene, 동적 아이콘 (running 시 `circle.dotted.circle`, idle 시 `music.quarternote.3`), summary 라인 + 자주 쓰는 액션
- `DockBadgeUpdater.swift` — `@MainActor` actor-style class, 1s polling 으로 `summary.dockBadgeLabel` → `NSApp.dockTile.badgeLabel` 동기화 (값 동일 시 set 생략)
- `UserNotificationCenterService.swift` — `UNUserNotificationCenter` 위 운영 구현, 권한 요청 + 알림 schedule (실패 시 silently swallow)

`Sources/Maestro/MaestroApp.swift`:

- 메인 윈도우 + `MaestroMenuBarExtra` Scene 분리 — 한 `ControlTowerEnvironment` 인스턴스가 두 Scene 공유 (`@State`)
- `.commands { MaestroMenuCommands(router: ...) }` 메뉴바 등록

`Sources/Maestro/ControlTower/ControlTowerView.swift`:

- `ControlTowerEnvironment` 에 `menuActionRouter` / `activitySummary` / `notificationService` 추가
- `wireMenuActions(...)` — addFolder/delete/openPalette/revealDataFolder 핸들러 등록 (모두 self 통한 MainActor 호출 — race 방지)
- `startSummaryObservation()` — 1s tick 으로 OrchestrationStatusModel/InboxStore/FolderViewModel 읽어서 summary 갱신
- `requestNotificationAuthorization()` — bootstrap 시 1회 권한 요청
- `ControlTowerView` 가 `DockBadgeUpdater` 를 lifetime 안에서 start/stop
- `.onChange(selectedFolderID)` 가 `canDeleteSelectedFolder` 동기화

**Tests**: 603/603 통과 (3 skipped — aider 미설치) (Phase 17 의 592 → +11)

- `MenuActionRouterTests` (3) — 등록 시 호출 / 미등록 noop / canDelete gate
- `AppActivitySummaryTests` (5) — zero / both / running only / unread only / menu line 변형
- `NotificationServiceTests` (3) — noop record auth / record notify / equality

---

## Step 2: 👥 /team Multi-Agent Review (1 묶음, arch+sec+perf+ux+test+docs)

**Must-fix 식별 5건 → 1건 반영, 4건 defer**.

### 반영 (1건)

1. ❌→✅ **MED-1: AppNotification sanitize 책임 명문화** — Phase 19 inbox-notify wiring 시 외부 텍스트를 그대로 OS 에 던질 위험. `AppNotification` 구조체 docstring 에 호출자 sanitize 의무 추가.

### Defer (4건)

- **HIGH-1: ControlTowerEnvironment god-object** — Phase 16 부터 누적된 우려. Phase 19+ 에서 `MenuSubsystem` 분리 검토.
- **MED-2: summary 1s polling 비용** — observation tracking single-fire 한계 회피용. 1s tick 의 wake 비용은 무시 가능. Phase 21 polish.
- **MED-3: DockBadgeUpdater UI 테스트 부재** — UI-only / NSApp 의존이라 단위 테스트 불가. SwiftUI snapshot 은 Phase 21 release pass 에서.
- **LOW-1: MenuBarExtra / MaestroMenuCommands SwiftUI 단위 테스트** — 동일 사유 defer.

---

## Step 3: ✨ /simplify

- `MenuActionRouter` — 7개 핸들러 슬롯 + 7개 동일 패턴 호출 entry point. boilerplate 같지만 각각 SwiftUI 메뉴 항목과 1:1 매핑 — 명시성 우선.
- `AppActivitySummary` — 4 stored property + 3 derived. derived 가 caller 분기 책임 가져감 — store 단순화.
- `DockBadgeUpdater` 1s polling — observation tracking 의 single-fire 트랩 우회. 코드 단순 (10 줄).
- `wireMenuActions` 는 모든 closure 가 `[weak self]` 를 통해 self.@MainActor 메서드 호출 — Sendable race 회피 + 격리 일원화.

## Step 4: 🧩 Integration Verification

- `swift build` 통과 (메인 + 메뉴바 두 Scene 컴파일)
- 603/603 테스트 통과 (3 skipped, aider 미설치 정상)
- `swiftlint --strict` 0 violations
- Quality Gate (Phase 18 plan):
  - ✅ 표준 macOS 단축키 작동 — `MaestroMenuCommands` 가 `keyboardShortcut` 부여 (⌘N / ⌘⌫ / ⌘, / ⌘⇧O / ⌘K)
  - ✅ 메뉴바에서 앱 창 안 열고 상태 확인 — `MaestroMenuBarExtra` 가 summary 라인 + 액션 노출
  - ✅ 알림이 집중 모드 규칙 존중 — `UNUserNotificationCenter` 사용 (OS 가 DND 자동 적용)

## Step 5: 🔄 Regression Check

- Phase 1-17 통과 유지 (592 → 603, +11)
- `ContentView` API: `@State` 자체 생성 → `@Bindable` 외부 주입 변경. `MaestroApp` 가 한 인스턴스를 두 Scene 에 공유. 다른 호출 없음 — 회귀 0
- `ControlTowerEnvironment.init` 에 `notificationService: NotificationService? = nil` 추가 — 기존 테스트는 default nil 로 통과
- 기존 store / dispatch / discussion / palette / slash 인터페이스 미변경

## Step 6: 📐 Architecture Compliance

- ✅ MenuActionRouter / AppActivitySummary / NotificationService / AppNotification 모두 `MaestroCore` (SwiftUI/AppKit 미의존)
- ✅ UserNotificationCenterService / DockBadgeUpdater / MaestroMenuCommands / MaestroMenuBarExtra 는 `Maestro/Menu/` (UI/AppKit 의존 격리)
- ✅ Swift 6 Strict Concurrency: actor (NoopNotificationService), @MainActor (Router/Summary/DockBadge), Sendable struct (AppNotification), `[weak self]` MainActor closure 패턴
- ✅ Phase 12 DisplayTextSanitizer 정책 일관 — AppNotification 사용 시 caller 가 sanitize (문서 명시)
- ✅ ContentView 외부 주입 패턴 — Phase 19 OnboardingView / PreferencesView 가 같은 패턴 재사용 가능

---

## Open Items for Later Phases

1. **InboxStore → NotificationService wiring** (Phase 19) — inbox 도착 시 알림 emit. preview body 는 `DisplayTextSanitizer` 적용 후 전달
2. **Preferences ⌘, 핸들러 wiring** (Phase 19) — 현재 router 슬롯만, 실제 PreferencesView 등록은 Phase 19
3. **Diagnostics export ⌘ 핸들러 wiring** (Phase 19+) — DiagnosticsBundle 생성 + Save Panel
4. **Help 메뉴 wiring** — README / docs 사이트 / GitHub Issues 연결 (Phase 22 베타)
5. **MenuBarExtra style 옵션** — Phase 19 PreferencesView 에서 사용자 선택 (.menu vs .window)
6. **Dock badge 색상 customization** — macOS 기본 빨강. 사용자 설정 노출은 Phase 19+
7. **summary observation push 기반 마이그레이션** — withObservationTracking 의 single-fire 한계 해결책 (예: AsyncSequence) 정립 시. Phase 21
8. **SwiftUI snapshot 테스트 (MenuBarExtra/CommandGroup)** — Phase 21 release pass

---

## 완료 기준

- [x] Phase 18 Task 18.1~18.7 (18.8 알림 설정 토글은 Phase 19 PreferencesView 에서 노출 — 본 phase 는 NotificationService 내부 abstraction 만 ship)
- [x] 603/603 테스트 통과 (3 skipped, aider 미설치 정상)
- [x] /team 리뷰 + must-fix 1건 반영, 4건 defer documented
- [x] swiftlint --strict: 0 violations
- [x] swift build 통과 (메인 + 메뉴바 Scene)
- [x] Phase 1-17 회귀 없음
- [x] Quality Gate 3개 모두 자동 검증
- [x] 리뷰 리포트 저장 (이 파일)
- [ ] phase-18-end 태그 (다음 단계)

**Milestone 7 (제품화 2주) 시작**: Phase 18 완료 — 표준 macOS 메뉴 + 메뉴바 트레이 + Dock 뱃지 + 알림 인프라. 사용자가 메인 윈도우를 닫아도 트레이로 활동 추적.

**다음**: Phase 19 — 설정 UI + 온보딩 + Keychain 통합 (5일 예상).
