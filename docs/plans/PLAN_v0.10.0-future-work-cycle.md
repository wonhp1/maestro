# Implementation Plan: v0.10.0 — v0.9 사이클 후속 (회귀 가드 + 코드 위생 + a11y)

**Status**: ⏳ Pending
**Started**: 2026-05-01
**Last Updated**: 2026-05-01
**Estimated Completion**: 5-6시간 풀집중

---

**⚠️ CRITICAL INSTRUCTIONS**: 매 phase 완료 후:

1. ✅ 완료된 task checkbox 체크
2. 🧪 quality gate 검증 명령어 모두 실행
3. ⚠️ quality gate 모든 항목 pass 확인
4. 📅 "Last Updated" 갱신
5. 📝 Notes & Learnings 섹션에 학습 기록
6. 🔍 변경 파일에 `/simplify` + `/team` 4-agent 리뷰 → must-fix (HIGH 등급) 모두 반영
7. 💾 commit + push + CI green 확인
8. ➡️ 그 다음 phase 진행

⛔ **quality gate 실패 또는 must-fix 미반영 상태로 진행 금지**

---

## 📋 Overview

### Feature Description

v0.9 사이클 (v0.9.0 ~ v0.9.8) 에서 5건의 4-agent 코드 리뷰가 완료되었고, 그
결과 식별된 **HIGH/MED 후속 항목 5개** 를 정리하는 사이클. 새 사용자 가시
기능은 없으며, 코드 품질 / 회귀 가드 / 접근성을 개선.

### Success Criteria

- [ ] ChatFactory 라우팅 통합 테스트가 4개 어댑터 (claude/codex/gemini/aider) 모두 검증
- [ ] VendorPickerSheet 의 login Task 가 sheet 닫힘 시 즉시 cancel
- [ ] `runOAuthSubprocess` 가 3개 helper 로 분리되어 swiftlint disable 제거
- [ ] `OAuthCLISpec` 구조체 도입 → loginCodex/loginGemini 가 wrapper 만 됨
- [ ] VendorPickerSheet 의 주요 컨트롤에 accessibilityLabel + traits 부여
- [ ] CI green, 1050+ tests pass (각 phase 마다 새 테스트 추가)
- [ ] swiftlint clean (lint disable 1건 제거)
- [ ] 사용자 가시 동작 회귀 0 (Codex/Gemini/Claude smoke 재검증)

### User Impact

- **사용자 가시 변경 거의 없음** — 회귀 가드 + 코드 위생 위주.
- **VoiceOver 사용자**: vendor picker 가 음성으로 안내됨 (Phase 4)
- **개발자 (미래의 우리)**: 새 어댑터 추가 시 ChatFactory 누락 회귀 불가능 (Phase 1).
  새 OAuth CLI 추가가 1줄 spec (Phase 3-B).

### Architecture Decisions

| 결정                                                                | 이유                                |
| ------------------------------------------------------------------- | ----------------------------------- |
| ChatFactory 통합 테스트는 stub adapter 4개로 in-process             | 외부 CLI 의존성 0, 빠른 실행        |
| Task cancellation 은 `@State var loginTask: Task?` + `.onDisappear` | SwiftUI native 패턴, 추가 의존성 0  |
| `OAuthCLISpec` 은 struct (Sendable, value semantics)                | 두 CLI 가 내부 상태 공유 안 함      |
| a11y 는 SwiftUI `.accessibilityLabel(_:)` modifier                  | UIKit accessibility API 안 끌어들임 |

---

## 🗺️ Phase Breakdown

### Phase 1: ChatFactory 라우팅 통합 테스트 ⏳

**Goal**: v0.9.6 critical 회귀 (codex/gemini → claude 잘못 라우팅) 의 재발을
**ChatFactory 자체 단위에서** 차단.

**Test Strategy**:

- Test type: 통합 테스트 (`Tests/MaestroTests/ChatFactoryTests.swift` 또는
  `Tests/MaestroAdaptersTests/ChatFactoryRoutingTests.swift`)
- Coverage: 4개 어댑터 ID (claude/codex/gemini/aider) × 폴더당 1번 = 4개 케이스
- Scenario: stub adapter 4개 등록 → folder.adapterId = .codex 인 폴더 생성 →
  ChatFactory 실행 → 결과 ChatViewModel 의 어댑터 ID 가 "codex" 인지 검증

**Tasks**:

#### RED (테스트 먼저 작성)

- [ ] `Tests/MaestroAdaptersTests/ChatFactoryRoutingTests.swift` 신규
- [ ] StubAdapter 재사용 (이미 AdapterSelectorTests 에 있음 — extract 또는 복제)
- [ ] `testCodexFolderRoutesToCodexAdapter` — folder.adapterId="codex" → 어댑터 id "codex" assert
- [ ] `testClaudeFolderRoutesToClaudeAdapter` — 동일 패턴
- [ ] `testGeminiFolderRoutesToGeminiAdapter`
- [ ] `testAiderFolderRoutesToAiderAdapter`
- [ ] **(선택) testFutureAdapterRoutesAutomatically** — registry 에 새 어댑터 ID
      "newvendor" 추가 후 그 폴더로도 라우팅됨 (allCandidateIDs 자동 반영 검증)

#### GREEN (현재 코드가 통과해야 함)

- [ ] `swift test --filter ChatFactoryRouting` — 6개 모두 pass
- [ ] 만약 fail 한다면 코드 버그 — 디버깅 후 fix

#### REFACTOR

- [ ] StubAdapter 가 두 테스트 파일에서 중복이면 `Tests/Helpers/StubAdapter.swift` 로 추출
- [ ] 테스트 케이스를 parameterized 형태로 줄일 수 있으면 정리

**Quality Gate**:

- [ ] `swift build` clean
- [ ] `swift test --filter ChatFactoryRouting` 6/6 pass
- [ ] 풀 스위트 1056+ tests pass (1050 → +6)
- [ ] swiftlint clean
- [ ] 가짜 회귀 시뮬레이션 — `enabled: ["claude", "aider"]` 로 잠시 되돌리면 codex/gemini 테스트 fail 하는지 확인 후 원복

**Coverage Target**: 4개 어댑터 ID 라우팅 100%, 정상/우회 경로 둘 다.

**Dependencies**: 없음 (현재 v0.9.8 코드 그대로).

**Estimated Effort**: 1 시간

---

### Phase 2: VendorPickerSheet Task cancellation ⏳

**Goal**: 사용자가 로그인 진행 중 sheet 를 닫으면 백그라운드 polling
프로세스도 즉시 종료.

**현재 동작**: sheet 닫혀도 `Task { await performLogin(...) }` 가 5분 timeout
까지 살아있음. 5분 후 갑자기 NSWorkspace.open 또는 polling 결과가
`loginMessage` (이미 dealloc 된 view) 에 쓰려 시도.

**Test Strategy**:

- Test type: ViewModel 단위 테스트 (Swift 6 strict concurrency 에서 SwiftUI
  view 자체 unit test 어려움 — 로직을 ViewModel-like 헬퍼로 추출 후 테스트)
- 또는 InteractiveAuthHelper 의 cancellation 경로를 직접 검증 (이미 `.cancelled`
  반환 케이스 있음)

**Tasks**:

#### RED

- [ ] `InteractiveAuthHelperTests.testLoginCancelledByTaskCancellation` 추가:
      Task 시작 → 100ms 후 cancel → result == .cancelled 검증
- [ ] `Tests/MaestroTests/VendorPickerLoginTaskTests.swift` (옵션) — view 격리
      어려우면 helper 함수만 테스트

#### GREEN

- [ ] `VendorPickerSheet.swift` 수정:
  - `@State private var loginTasks: [String: Task<Void, Never>] = [:]`
  - `performLogin` 호출처를 `loginTasks[adapterId] = Task { await performLogin(...) }` 로 변경
  - `.onDisappear { loginTasks.values.forEach { $0.cancel() } }` 추가
  - `defer` 에서 task 핸들 cleanup (`loginTasks[adapterId] = nil`)

#### REFACTOR

- [ ] task dictionary 가 너무 작은 일이면 `@State private var activeLogin: (id: String, task: Task<Void, Never>)?` 로 단순화 (어댑터 1개씩만 동시 로그인)
- [ ] 명명 개선

**Quality Gate**:

- [ ] `swift test` 1057+ pass
- [ ] swiftlint clean
- [ ] 수동 검증: Maestro 실행 → 로그인 버튼 클릭 → 즉시 sheet 닫기 → 5분 동안 codex/gemini 좀비 프로세스 없음 (`pgrep` 으로 확인)
- [ ] 회귀 검증: 정상 로그인 흐름은 그대로 동작

**Dependencies**: Phase 1 완료 (테스트 패턴 재사용).

**Estimated Effort**: 30 분

---

### Phase 3: InteractiveAuthHelper 구조 정리 ⏳

**Goal**: 64-line `runOAuthSubprocess` 를 3개 stage 로 분리 + `OAuthCLISpec`
구조체 도입.

**Tasks**:

#### Phase 3-A: 함수 분리 (REFACTOR-only)

- [ ] `setupOAuthProcess(executable:arguments:initialStdin:) -> (Process, OutputAccumulator, Pipe?)` — 프로세스 + 파이프 + 핸들러 구성
- [ ] `injectInitialStdin(_:into:)` — Y\n 주입 헬퍼
- [ ] `pollForCompletion(process:accumulator:authCheck:pollInterval:timeout:) -> LoginResult` — polling 루프 + URL extraction + 종료 처리
- [ ] `runOAuthSubprocess` 가 위 3개 호출하는 ~10줄 오케스트레이터로 축소
- [ ] `// swiftlint:disable:next function_body_length cyclomatic_complexity function_parameter_count` 제거

#### Phase 3-B: OAuthCLISpec 도입

- [ ] `OAuthCLISpec` struct (Sendable):
  ```swift
  public struct OAuthCLISpec: Sendable {
      let executable: URL
      let arguments: [String]
      let initialStdin: String?
      let authCheck: @Sendable () async -> Bool
  }
  ```
- [ ] `static func login(spec:pollInterval:timeout:) async -> LoginResult` — spec 기반 단일 진입점
- [ ] `loginCodex` / `loginGemini` 를 spec 만 만들어 `login(spec:)` 부르는 wrapper 로 단순화

#### Tests

- [ ] 기존 InteractiveAuthHelperTests 모두 그대로 pass (10/10)
- [ ] (선택) `testLoginAcceptsArbitrarySpec` — 새 spec 으로 동일 동작 검증

**Quality Gate**:

- [ ] `swift build` clean
- [ ] `swift test --filter InteractiveAuthHelper` 10+ pass (기존 보존)
- [ ] swiftlint clean — **lint disable 1건 제거 확인** (가장 중요한 시그널)
- [ ] 컴파일된 함수 길이 모두 60줄 이하 (lint 자동 체크)
- [ ] 수동 검증: v0.9.8 실행 → Codex/Gemini 인앱 로그인 동작 그대로

**Dependencies**: Phase 2 완료.

**Estimated Effort**: 1.5 시간

---

### Phase 4: VendorPickerSheet 접근성(a11y) 라벨 ⏳

**Goal**: VoiceOver 사용자 + 색맹 사용자도 vendor picker 사용 가능.

**대상 컨트롤** (`VendorPickerSheet.swift`):

- 라디오 버튼 (Aider/Claude/Codex/Gemini 4개)
- 설치 상태 아이콘 (✓ v1.2.3 / ✗ 미설치)
- 인증 상태 아이콘 (주황 경고)
- "Maestro 로 로그인" 버튼 (loading state)
- "다시 검사" 버튼
- "취소" / "추가" 버튼

**Tasks**:

- [ ] 각 라디오 행에 `.accessibilityLabel("어댑터: <이름>, <설치상태>, <인증상태>")`
- [ ] `.accessibilityAddTraits(.isSelected)` 선택된 행에 부여
- [ ] 설치/인증 아이콘에 `.accessibilityLabel("설치됨, v1.2.3")` 또는 `"미설치"`
- [ ] 로그인 버튼 진행 중 `.accessibilityLabel("로그인 진행 중")` + `.accessibilityHint("브라우저에서 인증을 완료해주세요")`
- [ ] 에러 메시지 행에 `.accessibilityRole(.staticText)` (자동이긴 함) + readable label

#### Tests (manual + snapshot if available)

- [ ] 수동: VoiceOver (cmd+F5) 켜고 vendor picker 탐색 — 모든 컨트롤 음성 안내 확인
- [ ] swift test 풀 스위트 회귀 0
- [ ] (선택) Accessibility Inspector 로 라벨 확인

**Quality Gate**:

- [ ] swift build clean
- [ ] 풀 스위트 pass (a11y 변경은 테스트 깨지면 안 됨)
- [ ] swiftlint clean
- [ ] 수동 VoiceOver 검증 통과 — 적어도 모든 라디오 버튼 + 로그인 버튼이 의미 있게 읽힘

**Dependencies**: Phase 3 완료.

**Estimated Effort**: 1.5 시간

---

### Phase 5: 통합 검증 + Release ⏳

**Goal**: 4개 phase 변경 통합 후 회귀 0 확인 + v0.10.0 release.

**Tasks**:

- [ ] `swift build` clean
- [ ] `swift test` 풀 스위트 pass
- [ ] `swiftlint lint --quiet` clean (Phase 3 의 lint disable 제거 후)
- [ ] **수동 smoke** (computer-use):
  - [ ] Codex 폴더 추가 + 메시지 전송 → 응답 도착
  - [ ] Gemini 폴더 추가 + 메시지 전송 → 응답 도착
  - [ ] Claude 폴더 추가 + 메시지 전송 → 응답 도착
  - [ ] 인앱 OAuth 흐름 (Codex/Gemini 둘 다) — 브라우저 자동 오픈
  - [ ] sheet 닫기 cancellation — 좀비 프로세스 0
- [ ] CHANGELOG v0.10.0 항목
- [ ] appVersion bump 0.9.8 → 0.10.0
- [ ] git tag v0.10.0 + push → GitHub Actions release
- [ ] DMG 다운로드 + /Applications 설치
- [ ] /tmp 백업 정리

**Quality Gate (출시 전)**:

- [ ] CI green
- [ ] DMG 생성 + 코드서명 + 노타리 통과
- [ ] 설치 후 첫 실행 정상

**Dependencies**: Phase 1-4 완료.

**Estimated Effort**: 1 시간

---

## ⚠️ Risk Assessment

| 위험                                                                                       | 확률 | 영향 | 대응                                                              |
| ------------------------------------------------------------------------------------------ | ---- | ---- | ----------------------------------------------------------------- |
| Phase 1 통합 테스트가 ChatFactory 의 isolation 제약 (MainActor closure) 때문에 작성 어려움 | 중   | 중   | 헬퍼로 closure body 추출하여 테스트 가능하게 만듦                 |
| Phase 2 Task cancellation 이 SwiftUI lifecycle 과 race                                     | 중   | 중   | `defer` 로 cleanup + `Task.isCancelled` 체크 추가                 |
| Phase 3 함수 분리 시 cancellation 경로 깨짐                                                | 낮   | 높   | 기존 10개 InteractiveAuthHelperTests 가 회귀 가드                 |
| Phase 4 a11y 변경이 SwiftUI 레이아웃 미세 변경                                             | 낮   | 낮   | 시각 테스트 — Maestro 실행 후 picker 외관 확인                    |
| Phase 3-B `OAuthCLISpec` 의 `authCheck` 클로저가 `EnvironmentChecker` 캡처 → Sendable 위반 | 중   | 중   | spec.authCheck 를 `@Sendable () async -> Bool` 명시, capture 검증 |

---

## 🔄 Rollback Strategy

각 phase 별 독립 commit. 문제 시 `git revert <sha>` 로 원복.

| Phase | Rollback 방법                                                                         |
| ----- | ------------------------------------------------------------------------------------- |
| 1     | 테스트 파일 1개 추가만 — 삭제하면 끝                                                  |
| 2     | VendorPickerSheet.swift 의 Task 변경 revert                                           |
| 3     | InteractiveAuthHelper.swift refactor commit revert (기능 동일하므로 의도된 회귀 없음) |
| 4     | a11y modifier 들 제거 (시각 변화 0)                                                   |
| 5     | release 후 문제 시 v0.9.8 DMG 재배포                                                  |

전체 사이클 rollback: `git reset --hard v0.9.8` (단 push 한 후엔 `git revert` 권장).

---

## 📝 Notes & Learnings

(빈 섹션 — 각 phase 완료 후 채워나감)

---

## 진행 상태

- [ ] Phase 1: ChatFactory 통합 테스트
- [ ] Phase 2: Task cancellation
- [ ] Phase 3: InteractiveAuthHelper 정리 (3-A 함수 분리, 3-B OAuthCLISpec)
- [ ] Phase 4: a11y 라벨
- [ ] Phase 5: 통합 검증 + Release v0.10.0

**현재 phase**: Phase 1 시작 대기
