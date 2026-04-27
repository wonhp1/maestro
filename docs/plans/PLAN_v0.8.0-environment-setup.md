# Implementation Plan: v0.8.0 — 온보딩 환경 자동 설치

**Status**: ⏳ Pending
**Started**: 2026-04-28
**Last Updated**: 2026-04-28
**Estimated Completion**: 2026-04-28 (당일, 약 3.5h)

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

v0.7.0 슬래시 UX 완성됐으나, 새 사용자 (Mac 만 있는 백지 상태) 가 Maestro 받아 즉시 사용하려면 본인이 Node.js / Claude Code CLI 등을 따로 설치해야 함. 비기술 사용자에게 진입 장벽.

v0.8.0 은 Maestro 안에서 누락된 도구를 **자동 검사 + 설치** 하는 온보딩 통합. 사용자가 DMG 받아서 더블클릭 → 온보딩에서 "환경 자동 설치" 버튼 한 번 → Node + Claude 자동 설치 + 브라우저 OAuth → 사용 가능.

### Success Criteria

- [ ] 첫 실행 시 EnvironmentChecker 가 모든 도구 (Node, Claude, git, python, Aider, claude-auth) 자동 검사
- [ ] 누락 시 "환경 자동 설치" 버튼 → progress sheet → Node + Claude 자동 설치
- [ ] 이미 설치된 도구는 skip (idempotent)
- [ ] git 누락은 ⚠️ 안내 (Aider 선택 시 외부 링크), 진행 막지 않음
- [ ] sudo 비밀번호 dialog 는 Node.js 설치 시 1회 (macOS 표준)
- [ ] OAuth 브라우저 띄움 (`claude` 실행 → 사용자 로그인 1회)
- [ ] vendor picker (폴더 추가) 에서도 Aider 선택 시 동일 흐름
- [ ] 모든 기존 889+ 테스트 통과 + 신규 테스트 추가
- [ ] swift build / swiftlint clean

### User Impact

- **백지 사용자**: DMG + Maestro 더블클릭 → 자동 환경 설정 → 즉시 사용 (이전엔 본인이 Homebrew + Node + Claude 따로 설치)
- **이미 설치된 사용자 (개발자)**: detect 자동 ✓, 설치 안 fired, 즉시 다음 단계
- **부분 설치된 사용자**: 누락된 것만 install (예: Node 있음 → Claude 만 install)

---

## 🏗️ Architecture Decisions

| Decision                                                                      | Rationale                                                                                               | Trade-offs                                                                    |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Node.js 직접 .pkg 설치 (Homebrew/CLT skip)                                    | ~50MB / 2-3분 (vs CLT+Homebrew ~2GB / 15-25분). 우리 use case 에 git/make/gcc 불필요                    | Node 업그레이드 시 사용자가 새 .pkg 받아야 (brew 의 자동 update X)            |
| git 은 자동 설치 X — 링크만                                                   | 개발자는 어차피 git 보유. 비개발자는 보통 Aider 안 씀. git installer 인프라 추가 회피 (시간 ↓)          | Aider 사용자가 git 없으면 외부 다운로드 단계 추가 (수동)                      |
| `EnvironmentChecker` (신규) — `CLIDetector` 위 wrapper                        | CLIDetector 가 이미 PATH lookup + version 추출. checker 는 도구별 status struct + 어댑터 dependency map | 신규 추상 1개 추가 — but 검사 로직 한 곳에 응집                               |
| `EnvironmentInstaller` (신규) — `AdapterInstaller` 와 분리                    | AdapterInstaller 는 npm/pip 만. Node .pkg 는 sudo + installer CLI 라 다른 메커니즘. 분리해 책임 명확    | 두 installer 존재 — 호출자가 어느 거 쓸지 알아야                              |
| sudo dialog = AppleScript `do shell script ... with administrator privileges` | macOS 표준. Touch ID 가능. Maestro 가 키체인 비번 직접 다루지 않음 (보안 ↑)                             | NSAppleScript 동기 호출 — main thread 에서 사용 시 spinner UI 필요            |
| Idempotent — 매 install step 시작 전 checker 재호출                           | 사용자가 외부에서 부분 설치한 case 안전. 부주의로 한 번 더 클릭해도 무해                                | 검사 비용 (수 ms) 매 step 발생 — 무시 가능                                    |
| Node.js 버전 cap = v18+ (Claude Code 최소 요구)                               | Claude Code 의 engines.node 가 18+. 옛 버전 ⚠️ → 자동 업그레이드 권유                                   | 사용자가 옛 Node 의존 다른 프로젝트 있으면 충돌 가능 — `nvm` 사용 권장 (안내) |
| OnboardingView 의 detectAgents 단계 교체                                      | 기존 단계가 Claude/Aider 만 detect — 환경 도구 (Node, git, python) 미포함. 통합으로 첫 사용자 흐름 일관 | 기존 detectAgents 코드 deprecate (legacy)                                     |

---

## 🗺️ Phase Breakdown

### Phase 1: EnvironmentChecker (검사 인프라)

**Goal**: 모든 환경 도구의 존재/버전을 한 번 호출로 받는 pure Swift checker. ProcessExecuting 으로 테스트 가능.

**Estimated Time**: 1시간
**Status**: ⏳ Pending

**Test Strategy**: 단위 테스트 + StubExecutor (각 명령 출력 시뮬레이션). UI 없음 — 100% 테스트 커버리지 가능.

#### Tasks

**🔴 RED**

- [ ] **Test 1.1**: `EnvironmentCheckerTests` (12-15 cases)
  - `checkNode()` — `which node` 성공 + `--version` 파싱 → `.installed("v22.x")`
  - `checkNode()` — `which` 실패 → `.notInstalled`
  - `checkNode()` — version v14 → `.outdated(current: "v14", required: "v18")`
  - `checkClaude()` — 설치됨 + 버전 추출
  - `checkClaude()` — 미설치
  - `checkGit()` — 단순 있음/없음
  - `checkPython3()` — 버전 추출 (Aider 호환 — 3.10+)
  - `checkAider()` — pip 사용자 path 포함 (`~/Library/Python/X.Y/bin/aider`)
  - `checkClaudeAuth()` — `~/.claude/credentials.json` 존재 여부
  - `checkAll()` — 통합 호출, 모든 도구 status 한 번에
- [ ] **Test 1.2**: `EnvironmentStatusTests` — struct 정의 검증 (Codable, Equatable)

**🟢 GREEN**

- [ ] **Task 1.3**: `EnvironmentStatus` struct (Sources/MaestroCore/EnvironmentStatus.swift)
  ```swift
  public enum ToolStatus: Sendable, Equatable, Codable {
      case installed(version: String?)
      case outdated(current: String, required: String)
      case notInstalled
  }
  public struct EnvironmentStatus: Sendable, Equatable {
      public let node: ToolStatus
      public let claude: ToolStatus
      public let git: ToolStatus
      public let python3: ToolStatus
      public let aider: ToolStatus
      public let claudeAuth: ToolStatus  // 사용자 로그인 여부
  }
  ```
- [ ] **Task 1.4**: `EnvironmentChecker` (Sources/MaestroCore/EnvironmentChecker.swift)
  - `init(executor:locator:)` — ProcessExecuting / ExecutableLocating 주입
  - `checkAll() async -> EnvironmentStatus` — 병렬 검사 (TaskGroup)
  - private 함수 per tool — 각자 path lookup + 버전 명령
- [ ] **Task 1.5**: 어댑터 → 필요 도구 mapping
  ```swift
  public enum AdapterRequirement {
      static let claude: [Tool] = [.node, .claude, .claudeAuth]
      static let aider: [Tool] = [.git, .python3, .aider]
  }
  ```

**🔵 REFACTOR**

- [ ] **Task 1.6**: 버전 비교 helper (semver-lite — `v22.11.0 >= v18` 같은)
- [ ] **Task 1.7**: claudeAuth 검사 robust — `~/.claude/credentials.json` + 파일 size 0 이면 missing 처리

#### Quality Gate ✋

- [ ] `swift build` green
- [ ] 889+ tests pass (+신규 ~15)
- [ ] swiftlint 0 violation
- [ ] **Coverage**: EnvironmentChecker 90%+, struct 100%
- [ ] 어댑터 별 dependency 표시 정확

#### Dependencies / Rollback

- 의존: 기존 `CLIDetector`, `ProcessExecuting`, `PATHExecutableLocator` (재사용)
- Rollback: 신규 파일 삭제 — 기존 코드 영향 없음

---

### Phase 2: EnvironmentInstaller (자동 설치 actor)

**Goal**: Node.js .pkg 자동 설치 + Claude/Aider npm/pip install + progress streaming.

**Estimated Time**: 1시간
**Status**: ⏳ Pending

**Test Strategy**: 핵심 logic (URL 빌더, 명령 빌더, progress 파싱) 단위 테스트. NSTask 자체는 통합 테스트 — 시간 cost 로 manual smoke 위주.

#### Tasks

**🔴 RED**

- [ ] **Test 2.1**: `EnvironmentInstallerTests`
  - `nodePackageURL(for: arm64)` — universal pkg URL 빌드
  - `nodePackageURL(for: x86_64)` — 동일 URL (universal2)
  - `installCommandLine(node:)` — `installer -pkg <path> -target /`
  - `installCommandLine(claude:)` — `npm install -g @anthropic-ai/claude-code`
  - `installCommandLine(aider:)` — `pip3 install --user aider-chat`
  - progress 파싱 (npm 의 download bytes / installer phase)
- [ ] **Test 2.2**: `AppleScriptSudoTests` — sudo 명령 escape (single quote, double quote 안전)

**🟢 GREEN**

- [ ] **Task 2.3**: `EnvironmentInstaller` actor (Sources/MaestroCore/EnvironmentInstaller.swift)
  ```swift
  public actor EnvironmentInstaller {
      public func installNode(progress: @Sendable (InstallProgress) -> Void) async throws
      public func installClaude(progress: ...) async throws
      public func installAider(progress: ...) async throws
  }
  public enum InstallProgress: Sendable {
      case downloading(bytes: Int64, total: Int64?)
      case running(phase: String)
      case complete
  }
  ```
- [ ] **Task 2.4**: Node.js .pkg 다운로드 + 설치
  - 다운로드 URL: `https://nodejs.org/dist/v22.11.0/node-v22.11.0.pkg`
  - URLSession (download task) + progress
  - 설치: AppleScript `do shell script "installer -pkg ..." with administrator privileges`
  - 결과 검증: `which node` 후 path 반환
- [ ] **Task 2.5**: Claude / Aider — 기존 `AdapterInstaller` 재사용 (delegation)
- [ ] **Task 2.6**: progress callback — closure 호출

**🔵 REFACTOR**

- [ ] **Task 2.7**: 다운로드 retry (network blip 대비 1회 재시도)
- [ ] **Task 2.8**: 임시 .pkg 파일 cleanup (defer 로 안전)

#### Quality Gate ✋

- [ ] `swift build` green
- [ ] 신규 tests (~10) pass
- [ ] swiftlint clean
- [ ] **Manual smoke**: 로컬에서 `installer -pkg` 명령 정상 동작 (기존 Node 백업 후 .pkg 재설치)
- [ ] AppleScript sudo dialog 정상 표시 (Touch ID 작동 확인)

#### Dependencies / Rollback

- 의존: Phase 1 EnvironmentChecker (idempotent check), 기존 AdapterInstaller, URLSession
- Rollback: 신규 파일 삭제

---

### Phase 3: OnboardingView 환경 자동 설치 통합

**Goal**: 첫 실행 시 EnvironmentChecker 호출 → 누락 도구 list + 자동 설치 sheet + git 외부 링크 fallback.

**Estimated Time**: 1시간
**Status**: ⏳ Pending

**Test Strategy**: ViewModel 단위 테스트 (state machine: scanning → installing → complete). UI 는 manual smoke.

#### Tasks

**🔴 RED**

- [ ] **Test 3.1**: `EnvironmentSetupViewModelTests`
  - 상태 전이: `idle → scanning → result(status) → installing → complete`
  - `requiredTools()` — 어댑터 무관 default (Node + Claude)
  - 누락 있을 때만 install 가능
  - install 진행 중 cancel 시 옛 상태 복원

**🟢 GREEN**

- [ ] **Task 3.2**: `EnvironmentSetupViewModel` (Sources/Maestro/Onboarding/EnvironmentSetupViewModel.swift)
  - `@Observable @MainActor`
  - state machine + EnvironmentChecker / Installer 주입
  - 매 install step 시작 전 재검사 (idempotent)
- [ ] **Task 3.3**: `EnvironmentSetupSheet` view
  - 검사 결과 list (✓/⚠️/✗ + 도구 이름 + 버전)
  - "환경 자동 설치" 버튼 — 누락 있을 때만
  - progress sheet during install (progress bar + 현재 단계)
  - git 누락 시 "git 다운로드 페이지" 버튼 → `NSWorkspace.shared.open(URL)`
  - "다시 검사" 버튼
- [ ] **Task 3.4**: `OnboardingView` 의 detectAgents 단계 교체
  - 기존 단계: Claude / Aider detect만
  - 신규: `EnvironmentSetupSheet` embed → 모든 환경 도구 검사 + 자동 설치
  - 완료 시 다음 단계 (firstFolder) 로
- [ ] **Task 3.5**: claude OAuth — `claude` 실행 후 NSWorkspace 가 OAuth URL 자동 띄움. Maestro 는 "로그인 완료 시 다시 검사" 안내.

**🔵 REFACTOR**

- [ ] **Task 3.6**: progress sheet UI 분리 (`InstallProgressView` view 추출)
- [ ] **Task 3.7**: i18n — 메시지 한국어/영어 (Maestro 기존 패턴 따름)

#### Quality Gate ✋

- [ ] `swift build` green
- [ ] tests pass
- [ ] swiftlint clean
- [ ] **Manual smoke** (white-box):
  - `~/Library/Application Support/Maestro` 백업 → Maestro 재실행 → 온보딩 시작
  - 검사 결과 list 정확
  - "자동 설치" 클릭 → progress 표시
  - sudo dialog → 비번 → Node 설치 완료
  - npm Claude 설치 완료
  - "다음 단계" 진행 가능
  - 데이터 복원 후 정상 운영 상태 확인

#### Dependencies / Rollback

- 의존: Phase 1, 2
- Rollback: OnboardingView 의 detectAgents 옛 코드로 복귀 (commit 단위 revert)

---

### Phase 4: Vendor picker 통합 (Aider dependency check)

**Goal**: 폴더 추가 시 Aider 선택 → git + python + Aider 누락 검사 + install/link prompt.

**Estimated Time**: 0.5시간
**Status**: ⏳ Pending

**Test Strategy**: 기존 vendor picker 의 자동 설치 동작 확장. ViewModel 단위 테스트.

#### Tasks

**🔴 RED**

- [ ] **Test 4.1**: `VendorPickerSheetViewModelTests` (또는 기존 테스트 확장)
  - Aider 선택 + git 없음 → "git 링크" prompt
  - Aider 선택 + python3 v3.8 → "python 업그레이드 안내"
  - Aider 선택 + git/python OK + Aider 없음 → 자동 설치
  - Claude 선택 → 추가 검사 없음 (온보딩에서 처리)

**🟢 GREEN**

- [ ] **Task 4.2**: VendorPickerSheet 의 자동 설치 로직 확장
  - 어댑터 선택 시 EnvironmentChecker 의 어댑터별 dependency 호출
  - 누락된 도구 list 표시
  - git 누락 → 외부 링크 button (Maestro 자체 install 함수 없음)
  - python3 누락 → 안내 (macOS 기본 포함이라 희귀)
  - Aider 누락 → EnvironmentInstaller.installAider() 호출 (기존 AdapterInstaller 재사용)

#### Quality Gate ✋

- [ ] tests pass
- [ ] swiftlint clean
- [ ] **Manual smoke**: 폴더 추가 → Aider 선택 → git 없는 환경에서 링크 prompt 정상 → Aider 설치 정상

#### Dependencies / Rollback

- 의존: Phase 1, 2
- Rollback: 기존 자동 설치 로직 그대로 (이번 phase 는 wrapper 추가)

---

## ⚠️ Risk Assessment

| Risk                                                  | Probability | Impact               | Mitigation                                                   |
| ----------------------------------------------------- | ----------- | -------------------- | ------------------------------------------------------------ |
| Node.js .pkg URL 변경 (Anthropic 또는 Node 사이트)    | Low         | High (다운로드 실패) | 다운로드 실패 시 명확한 에러 + 사용자에게 수동 다운로드 안내 |
| AppleScript sudo dialog 가 Maestro 가 sandbox 라 차단 | Low         | High                 | 현재 Maestro 는 sandbox 미사용 (entitlements 없음) — 검증됨  |
| `claude` OAuth 가 브라우저 안 띄움                    | Low         | Medium               | NSWorkspace 가 fallback — 사용자에게 URL 복사                |
| Apple Silicon vs Intel 분기 누락                      | Low         | Medium               | Node.js .pkg universal2 — 한 파일로 양쪽                     |
| 신규 macOS 버전에서 installer CLI 동작 변경           | Low         | Low                  | macOS 14+ 표준 도구 — 안정적                                 |
| 사용자가 옛 Node (v14) 위에 v22 설치 — 충돌           | Medium      | Low                  | .pkg 가 PATH 우선순위 자동 처리 (`/usr/local/bin/node` 갱신) |

---

## 🛠️ Rollback Strategy

Phase 별 단일 commit. 문제 시:

- Phase 4 revert → 기존 vendor picker 자동 설치만 사용
- Phase 3 revert → 기존 detectAgents 단계 복귀 (사용자가 본인이 install 안내 받음)
- Phase 2 revert → installer 기능 dead code, checker 만 동작
- Phase 1 revert → 모든 기능 무효 (기존 코드 영향 없음)

각 phase 독립.

---

## 📊 Progress Tracking

- [ ] Phase 1: EnvironmentChecker
- [ ] Phase 2: EnvironmentInstaller
- [ ] Phase 3: OnboardingView 통합
- [ ] Phase 4: Vendor picker 통합
- [ ] 전체 wrap-up: appVersion 0.7.0 → 0.8.0 + DMG

---

## 📝 Notes & Learnings

(각 phase 완료 시 추가)

---

## 🔬 Per-Phase Review Protocol

각 phase commit 전:

1. **Self review** — diff 한 번 통째 읽기
2. **/simplify** 리뷰 — 단순화 가능 항목
3. **/team** 4-에이전트 병렬 리뷰 (concurrency / API design / UX / edge case)
4. **must-fix 반영** — HIGH/MEDIUM 즉시 fix
5. **defer 항목 기록** — Notes 섹션
6. **commit + push** — single commit per phase
7. **CI watch** — green 까지 확인

---

## 🔗 Related Files

- `Sources/MaestroCore/CLIDetector.swift` — PATH lookup + version 추출 (재사용)
- `Sources/MaestroCore/AdapterInstaller.swift` — npm/pip install (재사용)
- `Sources/MaestroCore/ProcessExecuting.swift` — protocol
- `Sources/MaestroCore/EnvironmentChecker.swift` — **신규 (Phase 1)**
- `Sources/MaestroCore/EnvironmentStatus.swift` — **신규 (Phase 1)**
- `Sources/MaestroCore/EnvironmentInstaller.swift` — **신규 (Phase 2)**
- `Sources/Maestro/Onboarding/OnboardingView.swift` — Phase 3 에서 detectAgents 단계 교체
- `Sources/Maestro/Onboarding/EnvironmentSetupSheet.swift` — **신규 (Phase 3)**
- `Sources/Maestro/Onboarding/EnvironmentSetupViewModel.swift` — **신규 (Phase 3)**
- `Sources/Maestro/Folders/VendorPickerSheet.swift` — Phase 4 에서 dependency check 확장
- `docs/qa-reports/scenarios/S02-folder-add.md` — 기존 자동 설치 reference
