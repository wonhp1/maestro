# Changelog

모든 사용자 가시 변경. 버전 형식 [SemVer](https://semver.org/spec/v2.0.0.html), 배포는
GitHub Actions release workflow 자동화 (코드 서명 + 노타리 + DMG).

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
