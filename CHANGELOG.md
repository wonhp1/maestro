# Changelog

모든 사용자 가시 변경. 버전 형식 [SemVer](https://semver.org/spec/v2.0.0.html), 배포는
GitHub Actions release workflow 자동화 (코드 서명 + 노타리 + DMG).

## [0.11.0] — 2026-05-01

v0.10.0 final 리뷰 후속 — 사용자 가시 변경 없음, 코드 위생 / architecture
정리 위주. (i18n sweep 은 한국어 단일언어 환경에선 즉시 ROI 0 이라 글로벌
출시 결정 시점으로 미룸.)

### Added

- **`VendorPickerAuthCoordinator`** (`Sources/MaestroCore/`) — VendorPickerSheet
  의 인증/로그인 로직을 단위 테스트 가능 위치로 분리. `@MainActor @Observable`
  public class. EnvironmentChecker / ExecutableLocating / AuthPasteboard 3개
  의존성 주입.
- `AuthPasteboard` protocol + `SystemPasteboard` 기본 구현 — 클립보드 추상화로
  테스트에서 mock 가능.

### Changed

- `VendorPickerSheet`: 510 → 506줄. 인증 관련 모든 state/method 가 coordinator
  로 이동. `@State authCoordinator = VendorPickerAuthCoordinator()`. file_length
  swiftlint disable 제거.
- `InteractiveAuthHelper.OAuthSetup`: non-Sendable 의도를 주석 + auto-derived
  메커니즘으로 명시. Process/Pipe 가 non-Sendable 이므로 OAuthSetup 도 자동
  non-Sendable — Task 경계 캡처 시 컴파일러가 차단.
- `startLogin(for:)` 가 `@discardableResult Task<Void, Never>` 반환 — 테스트가
  sleep/yield 의존 없이 deterministic await 가능.

### Tests

- 1059 → 1066 (+7):
  - `VendorPickerAuthCoordinatorTests` 7개 — loadAuth, startLogin, cancel,
    cleanup 슬롯 검증, 클립보드 추상화

### Skipped (다음 사이클로)

- **i18n sweep**: 한국어 단일언어 환경에서 사용자 가시 변화 0, 영어/일본어
  확장 결정 시점에 일괄 처리가 효율적.

## [0.10.0] — 2026-05-01

v0.9 사이클의 4-agent 코드 리뷰 후속 — 사용자 가시 변경 없음, 코드 위생 / 회귀
가드 / 접근성 위주.

### Added

- `AdapterRouter` (AdapterSelector extension): 폴더 → 어댑터 라우팅 단위 테스트
  가능 위치. v0.9.6 critical 회귀 (codex/gemini → claude 잘못 라우팅) 의 단위
  회귀 가드 6개 추가.
- `OAuthCLISpec` 공개 struct + `login(spec:)` generic entry point — 미래 OAuth
  CLI 추가 시 spec 만 정의 (Cursor / Aider OAuth 등).
- VendorPickerSheet 접근성: 어댑터 행 4개 + 로그인 버튼 + 경고 아이콘에
  accessibilityLabel + traits + hint 부여 (VoiceOver / 색맹 사용자).

### Changed

- VendorPickerSheet: `loginInProgress: [String: Bool]` 외에 진행 중 Task 핸들을
  `loginTask: Task<Void, Never>?` 로 보관, sheet 닫힘 시 `.onDisappear` 에서 cancel.
  → 5분 동안 좀비 polling 프로세스 사라짐.
- `runOAuthSubprocess` 64줄 함수를 4개 stage 로 분리 (setup / inject stdin /
  poll / check exit). swiftlint disable 3건 제거.

### Tests

- 1050 → 1059 (+9):
  - `AdapterRouterTests` 6개 (라우팅 회귀 가드, 미래 어댑터 자동 반영, fallback)
  - `InteractiveAuthHelperTests`: cancellation + generic spec invalid path +
    happy path (success 분기 첫 커버리지)

### Refactored (코드 위생, 동작 변화 0)

- v0.9.6 hotfix 의 `enabled: ["claude", "aider", "codex", "gemini"]` 하드코딩을
  `selector.allCandidateIDs()` 로 단순화. 새 어댑터 추가 시 자동 반영.
- `AdapterSelector.allCandidateIDs()` 를 `nonisolated` 로 변경 — actor hop 제거
  (immutable `let candidates` 만 읽음).

## [0.9.8] — 2026-05-01

### Added

- `LoginResult.browserOpenFailed(url:)` — 브라우저 자동 오픈 실패 시 사용자에게
  즉시 알림 + 클립보드에 OAuth URL 자동 복사. 기존엔 silent 5분 대기 후
  타임아웃만 표시되던 문제 해결.
- 시나리오 doc `docs/qa-reports/scenarios/S17-inapp-oauth-login.md` — Codex / Gemini
  인앱 OAuth 흐름 + 에러 케이스 정리.

### Changed

- `AdapterSelector.allCandidateIDs()` 를 `nonisolated` 로 변경 — `candidates` 가
  immutable `let` 이라 actor hop 불필요. ChatFactory 의 이중 await 제거.
- `extractOAuthURL` 단일 패스 리팩터 + 매직 상수 명명 (`urlPattern`,
  `errorTailLength`, `oauthHostHints`).
- 에러 메시지에 CLI 이름 prefix (예: `codex exit 1: ...`) — 어떤 어댑터가 실패했는지
  명확히 구분.
- 타임아웃 메시지에 "기존 브라우저 탭은 닫고 다시 시도하세요" 추가 — stale tab
  안내 누락 회귀 방지.

## [0.9.7] — 2026-05-01

### Changed

- `AdapterSelector.allCandidateIDs()` API 추가. `ChatFactory` 가 enabled 셋을
  하드코딩하지 않고 등록된 모든 candidate 를 자동 사용하도록 리팩터 — 향후
  새 어댑터 추가 시 ChatFactory 업데이트 누락으로 인한 라우팅 회귀 (v0.9.6 같은)
  발생 불가능.

### Tests

- `AdapterSelectorTests`: `allCandidateIDs()` 단위 테스트 + select round-trip 통과
  검증 회귀 방지 테스트 2개 추가.

## [0.9.6] — 2026-04-30

### Fixed

- **Critical**: Codex / Gemini 어댑터로 폴더를 등록해도 메시지 전송 시 실제로는
  Claude CLI 가 호출되던 라우팅 회귀.
- 원인: `ControlTowerEnvironment+ChatFactory` 의 `selector.select(enabled:)`
  파라미터가 v0.5.1 부터 `["claude", "aider"]` 로 하드코딩 — v0.9.0 Phase 4 에서
  Codex / Gemini 어댑터 등록할 때 이 enabled 리스트 업데이트가 누락됨.
- 증상: ChatView 헤더에 "Claude Code" 가 잘못 표시, `~/.claude/projects/` 에
  codex 폴더의 jsonl 이 잘못 생성, codex/gemini 폴더가 항상 Claude 로 응답.

## [0.9.5] — 2026-04-30

### Fixed

- Gemini 인앱 OAuth 로그인 시 브라우저 안 열리던 문제. Gemini CLI 가 stdout 에
  URL 안 찍고 interactive prompt `[Y/n]:` 띄우는데 stdin 응답 없어서 멈춰있었음.
  `runOAuthSubprocess(initialStdin:)` 파라미터 추가, Gemini 호출에 `"Y\n"` 자동
  주입.

## [0.9.4] — 2026-04-30

### Fixed

- Codex 인앱 OAuth 로그인 시 브라우저 안 열리던 문제. subprocess stdout/stderr 를
  Pipe 로 캡처하면 CLI 자체 브라우저 오픈이 작동 안 해서, Maestro 가 출력에서
  OAuth URL 추출 + `NSWorkspace.shared.open(url)` 로 직접 호출.
- `extractOAuthURL` regex: auth.openai.com / accounts.google.com / "oauth"
  포함 URL 우선.

### Changed

- `InteractiveAuthHelper`: `runOAuthSubprocess` 공통 helper 추출 (Codex / Gemini
  공유). `OutputAccumulator` 로 thread-safe 출력 누적.

## [0.9.3] — 2026-04-30

### Added

- VendorPickerSheet 에 Gemini 인앱 OAuth 로그인 버튼. 사용자가 터미널 안 거치고
  Maestro 안에서 Google OAuth 흐름 진입 가능.

### Changed

- `InteractiveAuthHelper` 통합 helper 도입 (Codex + Gemini 공유 로직).

## [0.9.2] — 2026-04-30

### Added

- VendorPickerSheet 에 Codex 인앱 OAuth 로그인 버튼. 사용자가 `codex login`
  터미널 명령 직접 실행 안 하고 Maestro UI 에서 처리.

## [0.9.1] — 2026-04-30

### Fixed

- "환경 자동 설치" 버튼이 Claude Code 만 설치하고 Codex / Gemini 는 누락하던 문제.
  `EnvironmentSetupViewModel.installMissing()` 가 Node + Claude + Codex + Gemini
  모두 처리.

## [0.9.0] — 2026-04-30

### Added

- **OpenAI Codex CLI 어댑터** — `Sources/MaestroAdapters/CodexAdapter.swift`.
  ChatGPT Plus/Pro 구독으로 GPT-5 사용 가능 (구독 토큰 풀).
- **Google Gemini CLI 어댑터** — `Sources/MaestroAdapters/GeminiAdapter.swift`.
  무료 tier 일 1500 req + 1M context 지원.
- `EnvironmentChecker` / `EnvironmentInstaller` 에 Codex / Gemini 검사 + 설치 통합.
- `AdapterRequirement.codex` / `.gemini` 정의.
- `APIKeyStorage` 에 codex / gemini 네임스페이스.
- VendorPickerSheet, AdapterDetectionViewModel, EnvironmentSetupSheet 에
  Codex / Gemini 행 추가.
- 새 시나리오 docs: `docs/qa-reports/scenarios/S11-codex-folder-add.md`,
  `S12-gemini-folder-add.md`, `S13-multi-vendor-orchestration.md`.

### Changed

- 기존 ClaudeAdapter / AiderAdapter 패턴 그대로 재사용 — 회귀 없음.
