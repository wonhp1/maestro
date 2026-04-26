# S18 — 메뉴바 트레이

**상태**: ✅ PASS (코드 레벨)
**검증 방식**: Source review
**대상**: `Sources/Maestro/Menu/MaestroMenuBarExtra.swift`, `Sources/MaestroCore/AppActivitySummary.swift`

---

## SwiftUI Scene 구성

`MaestroMenuBarExtra.swift:7-23` — `MenuBarExtra("Maestro", systemImage: iconName)` Scene.

- 아이콘 동적 분기:
  - `summary.runningDispatchCount > 0` → `circle.dotted.circle`
  - else → `music.quarternote.3`
- 스타일: `.menu` (popup menu, 별도 popover 아님)

## 메뉴 컨텐츠 (`:25-50`)

순서대로:

1. **요약 라인** — `Text(summary.menuBarSummaryLine)` (예: "에이전트 3 · 진행 1 · 미확인 2")
2. Divider
3. "새 폴더 추가…" → `router.addFolder()`
4. "커맨드 팔레트 열기" → `router.openCommandPalette()`
5. "데이터 폴더 열기" → `router.revealDataFolder()`
6. Divider
7. "환경설정…" (⌘,) → `router.openPreferences()`
8. Divider
9. "Maestro 종료" (⌘Q) → `NSApp.terminate(nil)`

## AppActivitySummary 통합

`AppActivitySummary.swift`:

- `runningDispatchCount` (`:17`) — orchestration 진행중 개수
- `unreadInboxCount` (`:18`) — 미확인 inbox 개수
- `folderCount` (`:19`) — 등록 폴더 수
- `lastInboxArrival` (`:20`) — 최근 도착 시각

`menuBarSummaryLine` (`:31-37`):

- 항상 "에이전트 N" 포함
- `runningDispatchCount > 0` 시 "진행 N" append
- `unreadInboxCount > 0` 시 "미확인 N" append
- 구분자 `·`

`hasAnyActivity` (`:39-41`) — 트레이/Dock 뱃지 결정 boolean.

`@MainActor @Observable` 이라 SwiftUI 가 변경 자동 반영.

---

## Verdict

- ✅ 메뉴바 아이콘 등록 (`MenuBarExtra`)
- ✅ 동적 SF Symbol (running 중이면 다른 아이콘)
- ✅ 요약 stats line + 5개 액션 + Quit
- ✅ AppActivitySummary observable 통합 — runtime 변경 즉시 반영
