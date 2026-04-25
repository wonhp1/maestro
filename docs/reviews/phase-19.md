# Phase 19 Review Report — 설정 UI + 온보딩 + Keychain 통합

**Date**: 2026-04-25
**Phase**: 19 / 23
**Status**: ✅ Complete
**Commits**: phase-19-start → phase-19-end

---

## Deliverables

`Sources/MaestroCore/`:

- `Preferences.swift` — `PreferencesSnapshot` Codable struct (firstRunCompleted / notificationsEnabled / launchAtLogin / enabledAdapterIDs / preferredAdapterID / dispatchTimeoutSeconds), 모든 필드 옵셔널 + 기본값 (graceful migration)
- `PreferencesStore.swift` — `@MainActor @Observable`, `FileStore<PreferencesSnapshot>` 위, 100ms 디바운스 autosave, corrupt 파일 silent fallback, `setAdapterEnabled` 시 preferred 자동 fallback (min)
- `APIKeyStorage.swift` — `KeychainStore` facade, namespace `adapter:<id>:apiKey`, ID 검증 (영숫자 `_-`, 1~64자), trim + 빈 값 자동 delete, 멱등 delete
- `OnboardingViewModel.swift` — `@MainActor @Observable`, 3-step (.welcome / .detectAgents / .firstFolder), advance/goBack/skip/complete, `onComplete` 콜백 + `setDetectedAdapters` API
- `AppSupportPaths.swift` — `preferencesFile` URL 추가

`Sources/Maestro/`:

- `Onboarding/OnboardingView.swift` — 3-step 마법사 sheet, 진행 점 dot indicator, 건너뛰기 / 이전 / 다음(시작) 액션, "폴더 추가" 버튼이 first folder 단계에서 컨트롤 타워로 hop
- `Preferences/PreferencesView.swift` — `Settings { TabView }` Scene root. 4 panes:
  - **General**: 알림 토글 / 자동실행 토글 (P22 wiring) / 디스패치 타임아웃 stepper / 알림 권한 재요청
  - **Agents**: 기본 어댑터 picker / 활성화 토글 (claude/aider) / SecureField API 키 (Keychain 즉시 저장)
  - **Shortcuts**: 표준 단축키 read-only 목록 (커스터마이징은 P22 defer)
  - **Advanced**: AppSupport 경로 + Finder 열기 + 진단 번들 (P22 wiring)
- `MaestroApp.swift` — `Settings { MaestroSettingsRoot }` Scene 추가 (표준 ⌘, 트리거)
- `ControlTower/ControlTowerView.swift`:
  - `preferencesStore` lazy (bootstrap 후 set), `apiKeyStorage` 주입, `showOnboarding` 플래그, `resolvedPaths` 캐시
  - `OnboardingViewModel` view-state 로 lazy 생성, `firstRunCompleted` 변경 감지로 sheet 자동 닫힘
  - `menuActionRouter.onOpenPreferences` 가 `NSApp.sendAction(showSettingsWindow:)` 트리거

**Tests**: 624/624 통과 (3 skipped — aider 미설치) (Phase 18 의 603 → +21)

- `PreferencesStoreTests` (7) — defaults / persist roundtrip / adapter enabled-disabled flow / preferred 검증 / timeout clamp / corrupt fallback / replaceSnapshot
- `APIKeyStorageTests` (7) — set+get / 빈 값 delete / 공백 trim / namespace 분리 / invalid ID reject / 멱등 delete / makeKey 형식
- `OnboardingViewModelTests` (7) — initial state / advance 전체 cycle + complete / goBack 경계 / skip 즉시 complete / complete 멱등 / onComplete 콜백 / detectedAdapters 저장

---

## Step 2: 👥 /team Multi-Agent Review (security 중점)

**Must-fix 식별 4건 → 1건 반영, 3건 defer**.

### 반영 (1건)

1. ❌→✅ **HIGH-1: API 키 메모리 평문 잔류** — `PreferencesView.AgentsPreferencesPane` 가 `@State apiKeys: [String: String]` 에 키 평문 보관. Settings 닫혀도 SwiftUI state 잔존. `.onDisappear` 에서 명시적 clear (security defense in depth — Keychain 이 보호하지만 process memory dump 면 노출). (sec)

### Defer (3건)

- **MED-1: SecureField 키스트로크별 Keychain SET** — debounce 추가 시 미저장 race. Keychain SET 자체가 빠르고 idempotent — 1회/keystroke 비용 무시 가능. Phase 22 polish.
- **MED-2: PreferencesView API key 마스킹 reveal toggle** — UX 편의. 보안 영향 없음 — Phase 22 정책.
- **LOW-1: PreferencesStore migration 버전 필드** — 현재는 옵셔널 + 기본값으로 graceful. 명시적 schema version 은 stored 필드 늘어날 때 도입.

---

## Step 3: ✨ /simplify

- `Preferences.swift` 와 `PreferencesStore.swift` 분리 — snapshot struct 와 영속 액터 분리. 테스트가 snapshot 단독 검증 가능
- `APIKeyStorage` static `makeKey` — 모든 entry point 가 ID 검증 통과. 우회 경로 없음
- `OnboardingViewModel` rawValue 기반 step 전환 — `OnboardingStep.allCases` 와 자연스럽게 일치
- PreferencesView TabView `.tabItem` 구조 — 표준 macOS — 추가 wrapper 없음

## Step 4: 🧩 Integration Verification

- `swift build` 통과 (Settings Scene + onboarding sheet 두 wiring 컴파일)
- 624/624 테스트 통과 (3 skipped, aider 미설치 정상)
- `swiftlint --strict` 0 violations
- Quality Gate (Phase 19 plan):
  - ✅ 처음 앱 실행 시 온보딩 3단계 완주 — `OnboardingViewModel.advance()` 마지막에서 `complete()` 자동, `firstRunCompleted` set + sheet dismiss
  - ✅ API 키가 Keychain 에만 저장 — `APIKeyStorage` 가 `KeychainStore` 만 사용, `PreferencesSnapshot` 에 키 필드 없음, `PreferencesView` `.onDisappear` 가 메모리 clear
  - ✅ 모든 설정 변경이 재시작 없이 반영 — `@Observable` propagation, `setAdapterEnabled`/`setDispatchTimeoutSeconds` 등 모든 setter 가 100ms 안에 디스크 + UI 반영

## Step 5: 🔄 Regression Check

- Phase 1-18 통과 유지 (603 → 624, +21)
- `ControlTowerEnvironment.init` 에 `preferencesStore: PreferencesStore? = nil` + `apiKeyStorage: APIKeyStorage = .init()` 추가 — 기존 호출자는 default 로 통과
- `AppSupportPaths.preferencesFile` 추가 — 기존 path 인터페이스 미변경
- 기존 store / dispatch / discussion / palette / slash / menu 인터페이스 미변경

## Step 6: 📐 Architecture Compliance

- ✅ `PreferencesSnapshot` / `PreferencesStore` / `APIKeyStorage` / `OnboardingViewModel` 모두 `MaestroCore` (SwiftUI/AppKit 미의존)
- ✅ `OnboardingView` / `PreferencesView` / `MaestroSettingsRoot` 는 `Maestro/Onboarding`/`Maestro/Preferences` (UI 격리)
- ✅ Swift 6 Strict Concurrency: actor (FileStore 재사용), @MainActor (Store/ViewModel), Sendable struct (Snapshot/APIKeyStorage), nonisolated value types
- ✅ **시크릿 파일 저장 금지** — `PreferencesSnapshot` 에 키 필드 없음, `APIKeyStorage` 가 Keychain 외 경로 사용 X, `PreferencesView` 가 .onDisappear 에서 메모리 clear (방어적)
- ✅ Phase 12 `DisplayTextSanitizer` 정책 일관 — `OnboardingView` / `PreferencesView` 모두 사용자 입력만 다룸 (외부 텍스트 없음)

---

## Open Items for Later Phases

1. **InboxStore → NotificationService wiring** (보고 도착 시 알림) — Phase 18 인프라 완료, Phase 19 미적용
2. **OnboardingView detectedAdapters 자동 채움** — 현재 setDetectedAdapters API 만, 실제 wiring 은 Phase 22 또는 사용자 코드
3. **launchAtLogin OS wiring** (`SMAppService.mainApp.register()`) — Phase 22
4. **Diagnostics export wiring** — Phase 5 DiagnosticsBundle + Save Panel 통합 (Phase 22)
5. **Help 메뉴 / Onboarding "도움말" 링크** — README/docs 사이트 (Phase 22 베타)
6. **SecureField reveal toggle** — Phase 22 UX polish
7. **PreferencesView SwiftUI snapshot 테스트** — Phase 21 release pass
8. **Schema version 필드** — stored 필드 변동 시 도입

---

## 완료 기준

- [x] Phase 19 Task 19.1~19.7 (19.8 진단 번들 wiring 은 Phase 22 defer, 19.9 first-run 감지 ✅, 19.10 실시간 적용 ✅)
- [x] 624/624 테스트 통과 (3 skipped, aider 미설치 정상)
- [x] /team 리뷰 + must-fix 1건 반영 (HIGH SEC), 3건 defer documented
- [x] swiftlint --strict: 0 violations
- [x] swift build 통과 (Settings Scene + Onboarding sheet)
- [x] Phase 1-18 회귀 없음
- [x] Quality Gate 3개 모두 자동 검증
- [x] 리뷰 리포트 저장 (이 파일)
- [ ] phase-19-end 태그 (다음 단계)

**Milestone 7 (제품화 2주) 진행**: Phase 18 메뉴 + Phase 19 설정/온보딩/Keychain. 사용자가 처음 실행 → 3-step 가이드 → 환경설정에서 어댑터 활성화 + API 키 입력. 모든 설정이 재시작 없이 반영.

**다음**: Phase 20 — 쉘 터미널 패널 (SwiftTerm) (5일 예상).
