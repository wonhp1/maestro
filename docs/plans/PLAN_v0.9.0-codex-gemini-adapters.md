# Implementation Plan: v0.9.0 — OpenAI Codex CLI + Google Gemini CLI Adapters

**Status**: ⏳ Pending
**Started**: 2026-04-29
**Last Updated**: 2026-04-29
**Estimated Completion**: 5-7일 풀집중 (또는 2주 점진적)

---

**⚠️ CRITICAL INSTRUCTIONS**: 매 phase 완료 후:

1. ✅ 완료된 task checkbox 체크
2. 🧪 quality gate 검증 명령어 모두 실행
3. ⚠️ quality gate 모든 항목 pass 확인
4. 📅 "Last Updated" 갱신
5. 📝 Notes & Learnings 섹션에 학습 기록
6. 🔍 `/simplify` + `/team` 4-agent 리뷰 → must-fix (HIGH 등급) 모두 반영
7. 💾 commit + push + CI green 확인
8. ➡️ 그 다음 phase 진행

⛔ **quality gate 실패 또는 must-fix 미반영 상태로 진행 금지**

---

## 📋 Overview

### Feature Description

v0.8.0 으로 환경 자동 설치 (Node/Claude/Aider) + 온보딩 sheet 완성. 현재 Maestro 어댑터는 **ClaudeAdapter + AiderAdapter** 두 개. v0.9.0 에서는 **CodexAdapter (OpenAI)** + **GeminiAdapter (Google)** 추가하여 ChatGPT Plus/Pro 구독자 + Gemini AI Pro 구독자도 본인 구독으로 Maestro 안에서 1급 시민으로 사용.

### Success Criteria

- [ ] CodexAdapter 가 ClaudeAdapter 와 동등한 기능 (sendMessage, streamMessage, listSlashCommands, capturedSlashCommands, availableModels, resolvedModel)
- [ ] GeminiAdapter 동일
- [ ] 두 CLI 모두 자동 설치 (npm 글로벌)
- [ ] 두 CLI 모두 OAuth (구독 토큰) + API key fallback 지원
- [ ] VendorPickerSheet 에서 "Codex (OpenAI)", "Gemini (Google)" 선택 가능
- [ ] EnvironmentSetupSheet 에서 누락 시 검사 결과 + 자동 설치 가능
- [ ] 멀티 vendor orchestration: control → codex → gemini → claude dispatch chain 동작
- [ ] 기존 Claude/Aider 어댑터 회귀 X
- [ ] CI green, 1000+ tests pass, swiftlint clean

### User Impact

- **ChatGPT Plus/Pro 구독자** ($20~$200/월): 본인 구독으로 Maestro 안에서 GPT-5 / o1 사용
- **Gemini AI Pro 구독자** ($20/월): 1M context + 빠른 응답
- **무료 사용자**: Gemini 무료 tier (일 1,500 req) 로 Maestro 시작
- **Multi-vendor 사용자**: 같은 폴더를 여러 어댑터로 dispatch → 응답 비교
- **Claude lock-in 회피**: Maestro 가 진정한 멀티 vendor orchestrator 로 포지셔닝

---

## 🏗️ Architecture Decisions

| Decision                                       | Rationale                                                                                                           | Trade-offs                                                                     |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| **CLI subprocess 패턴 유지** (직접 API 호출 X) | Claude Code 처럼 각 vendor 의 1st party CLI 활용 → 구독 토큰 풀 사용 가능, OAuth 흐름 위임, 모델 업데이트 자동 추종 | CLI 가 메이저 업데이트로 깨지면 어댑터 수정 필요 (Claude Code v1→v2 전례 있음) |
| **각 CLI 당 독립 어댑터** (Codex, Gemini 별개) | ClaudeAdapter 패턴 따라 actor 로 격리, 각 CLI 의 quirk 별도 처리                                                    | "Generic CLI Adapter" 추상화보다 코드량 많지만 안정성 ↑                        |
| **Codex 먼저 → Gemini 순차**                   | Codex 어댑터 완성 후 Gemini 가 패턴 재사용 → 30% 빠름                                                               | 두 CLI protocol 차이 발견 시점 약간 늦어짐                                     |
| **Full parity (Claude 어댑터와 동등)**         | slash 명령 / 모델 선택 / capture 모두 지원 → 사용자에게 동등한 경험 제공                                            | 어댑터 1개당 ~1.5일 소요 (vs minimal MVP 0.5일)                                |
| **Phase 0 R&D Spike 한번에 4h**                | 양쪽 CLI 의 protocol 동시 파악 → 패턴 비교 가능                                                                     | spike 동안 다른 진행 X                                                         |
| **OAuth 우선, API key fallback**               | 구독 사용자 친화적, API key 는 헤비 유저용                                                                          | OAuth 흐름 검증 필요 (Spike phase 핵심 과제)                                   |
| **Aider 의 OutputParser 패턴 차용** (필요 시)  | Codex/Gemini 가 plain text 출력하면 휴리스틱 파싱 필요                                                              | NDJSON 출력 가능하면 더 안정적 — Spike 결과 후 결정                            |
| **APIKeyStorage 네임스페이스 그대로**          | `adapter:codex:apiKey`, `adapter:gemini:apiKey` 자동 지원                                                           | 추가 시크릿 (refresh token 등) 필요하면 facade 메서드 추가                     |
| **Dependency Banner 일반화**                   | aiderDependencyBanner → 공용 컴포넌트 (3개 어댑터 공유)                                                             | 즉시 일반화 vs 3번째 어댑터 등장 시 일반화 — 본 plan 은 즉시                   |

---

## 📦 Dependencies

### Required Before Starting

- [x] v0.8.0 완료 (EnvironmentChecker / EnvironmentInstaller / EnvironmentSetupSheet 인프라)
- [x] ClaudeAdapter / AiderAdapter 동작 (reference 구현)
- [x] AdapterRegistry (string-key 기반, 자동 호환)
- [x] APIKeyStorage (Keychain, namespace 자동 지원)
- [x] Sparkle 자동 업데이트 (v0.9.0 release 후 사용자에게 push)

### External Dependencies

- Node.js v18+ (사용자 시스템, EnvironmentInstaller 가 자동 설치)
- `@openai/codex` — npm 글로벌 (정확한 패키지명 Spike phase 에서 검증)
- `@google/gemini-cli` — npm 글로벌 (정확한 패키지명 Spike phase 에서 검증)
- macOS 14+ (기존 동일)

---

## 🧪 Test Strategy

### Testing Approach

**TDD Principle**: 각 phase 마다 RED (실패하는 테스트 먼저) → GREEN (최소 구현) → REFACTOR (정리)

### Test Pyramid for v0.9.0

| Test Type                                                | Coverage Target                     | Purpose                                                           |
| -------------------------------------------------------- | ----------------------------------- | ----------------------------------------------------------------- |
| **Unit Tests** (MaestroAdaptersTests / MaestroCoreTests) | ≥80%                                | Adapter logic, parser, profile, environment check/install         |
| **Integration Tests**                                    | dispatch / streaming critical paths | Mock subprocess 로 CodexAdapter / GeminiAdapter 의 end-to-end     |
| **Manual Smoke Tests** (Phase 10)                        | 4 시나리오                          | 실제 CLI 설치 + 폴더 추가 + dispatch + multi-vendor orchestration |

### Test File Organization

```
Tests/
├── MaestroCoreTests/
│   ├── EnvironmentCheckerTests.swift    (확장 — codex/gemini check 추가)
│   ├── EnvironmentInstallerTests.swift  (확장 — codex/gemini install 추가)
│   ├── EnvironmentSetupViewModelTests.swift (확장)
│   ├── APIKeyStorageTests.swift         (확장 — openai/gemini namespace)
│   └── AdapterDetectionViewModelTests.swift (확장)
└── MaestroAdaptersTests/
    ├── CodexAdapterTests.swift          (NEW)
    ├── CodexProfileTests.swift          (NEW)
    ├── CodexOutputParserTests.swift     (NEW, optional)
    ├── GeminiAdapterTests.swift         (NEW)
    ├── GeminiProfileTests.swift         (NEW)
    └── GeminiOutputParserTests.swift    (NEW, optional)
```

### Coverage Requirements by Phase

- **Phase 0 (Spike)**: 테스트 X — R&D
- **Phase 1 (Env infra)**: ≥80% — checker/installer 확장
- **Phase 2A-D (Codex)**: ≥80% — 어댑터 비즈니스 로직
- **Phase 3A-C (Gemini)**: ≥80% — 어댑터 비즈니스 로직
- **Phase 4-9**: 통합/UI, 핵심 path 테스트
- **Phase 10 (Verification)**: manual smoke + 회귀 검증

### Test Naming Convention

```swift
// XCTest 기준
final class CodexAdapterTests: XCTestCase {
    func testDispatchSendsCorrectArgumentsToSubprocess() { }
    func testStreamingParsesNDJSONLines() { }
    func testCancelTerminatesProcess() { }
    func testOAuthMissingReturnsHelpfulError() { }
}
```

---

## 🚀 Implementation Phases

### Phase 0: R&D Spike (Pre-Phase)

**Goal**: Codex/Gemini CLI 의 실제 protocol, 인증 흐름, 출력 format, session 개념 파악 → spike doc 작성. 이게 안 되면 어댑터 작성 불가.

**Estimated Time**: 4 hours

**Status**: ⏳ Pending

#### Tasks

**🔬 Investigation Tasks (RED 패턴 X — R&D)**

- [ ] **Task 0.1**: Codex CLI 실제 설치 + 정확한 npm 패키지명 확정
  - 시도: `npm search codex`, `npm view @openai/codex`, OpenAI 공식 GitHub 확인
  - 명령: `npm install -g <패키지명>` 후 `codex --version` 확인
  - 예상 시간: 15분

- [ ] **Task 0.2**: Codex CLI 의 명령 옵션 분석
  - `codex --help`, `codex chat --help`, `codex exec --help` (있다면) 출력 캡처
  - 비대화형 모드 (`--print` / `-p` / `chat --no-tty` 등) 존재 여부
  - session ID 기반 재개 (`--session-id`, `--resume`) 옵션
  - 출력 format 옵션 (`--output-format json`, `--ndjson` 등)
  - 모델 선택 (`--model`)
  - 예상 시간: 30분

- [ ] **Task 0.3**: Codex 의 stdout format 분석
  - 비대화형 모드로 간단한 prompt 실행 → stdout 캡처
  - JSON / NDJSON / SSE / plain text 중 무엇인지
  - 응답 메시지 / tool_use / tool_result 가 어떻게 표현되는지
  - error 가 어떻게 표현되는지
  - 예상 시간: 30분

- [ ] **Task 0.4**: Codex OAuth 흐름 분석
  - `codex auth login` 또는 동등 명령 존재 여부
  - 인증 정보 저장 위치 (Keychain / `~/.codex/credentials.json` / 환경변수)
  - ChatGPT Plus 계정으로 OAuth 가능한지 (구독 토큰 풀 활용 검증)
  - API key fallback 흐름 (`OPENAI_API_KEY` 환경변수)
  - 예상 시간: 30분

- [ ] **Task 0.5**: Gemini CLI 동일 분석 (Task 0.1-0.4 반복)
  - `@google/gemini-cli` 패키지명 확정
  - `gemini --help` / `gemini chat --help`
  - 비대화형 모드 / session 재개 / output format / 모델 선택
  - OAuth (`gemini auth login`) + Google 계정 연동
  - API key fallback (`GEMINI_API_KEY`)
  - 예상 시간: 1.5시간

- [ ] **Task 0.6**: Spike doc 작성 (`docs/spikes/v0.9.0-codex-gemini-protocol.md`)
  - 두 CLI 의 protocol 비교표
  - ClaudeAdapter 와의 차이점 (NDJSON 여부, session 개념, slash 명령 등)
  - 어댑터 구현 시 고려사항 (parser 패턴 선택, OAuth UI 흐름)
  - 발견된 quirk / 제약사항 (e.g., "Codex CLI 가 stream 모드에서 SSE 형식 사용")
  - 각 어댑터 phase 의 시간 재추정
  - 예상 시간: 30분

#### Quality Gate ✋

**⚠️ STOP: Phase 1 진행 전 모든 항목 완료**

- [ ] Codex CLI 실제 설치 + 동작 확인
- [ ] Gemini CLI 실제 설치 + 동작 확인
- [ ] 두 CLI 의 비대화형 prompt 실행 + stdout format 캡처 (실제 데이터)
- [ ] 두 CLI 의 OAuth 흐름 검증 (실제 ChatGPT/Google 계정으로 로그인 테스트)
- [ ] Spike doc 작성 완료 (모든 발견 기록)
- [ ] Phase 2C / 3C 의 시간 재추정 (NDJSON 이면 그대로, plain text 면 +2h 씩)

**Validation Commands**:

```bash
which codex && codex --version
which gemini && gemini --version
codex chat -p "say hello in one word" --output-format json 2>&1 | head -50
gemini chat -p "say hello" --output-format json 2>&1 | head -50
ls docs/spikes/v0.9.0-codex-gemini-protocol.md
```

**Notes**: 만약 Codex 또는 Gemini CLI 가 아직 출시 안 됐거나 기능이 부족하면 (e.g., 비대화형 모드 없음), plan 전체 재검토 필요. Spike 결과를 사용자와 공유하고 진행 여부 결정.

---

### Phase 1: EnvironmentChecker / EnvironmentInstaller 확장

**Goal**: v0.8.0 의 환경 인프라 확장 — Codex/Gemini 검사 + 자동 설치 함수 + Status struct 확장

**Estimated Time**: 2 hours

**Status**: ⏳ Pending

#### Tasks

**🔴 RED: Write Failing Tests First**

- [ ] **Test 1.1**: EnvironmentCheckerTests 확장 — codex/gemini check
  - File: `Tests/MaestroCoreTests/EnvironmentCheckerTests.swift`
  - 추가 tests (5~7개):
    - `testCheckCodexMissingReturnsNotInstalled`
    - `testCheckCodexInstalledExtractsVersion`
    - `testCheckCodexAuthOAuthPath`
    - `testCheckCodexAuthAPIKeyFallback`
    - `testCheckGemini*` (동일 패턴)
  - Expected: FAIL (메서드 존재 X)

- [ ] **Test 1.2**: EnvironmentInstallerTests 확장 — installCodex/installGemini
  - File: `Tests/MaestroCoreTests/EnvironmentInstallerTests.swift`
  - 추가 tests:
    - `testInstallCodexFailurePropagatesAsInstallFailed`
    - `testInstallCodexSuccessPropagates`
    - `testInstallGemini*` (동일)
  - Expected: FAIL (메서드 존재 X)

**🟢 GREEN: Implement to Make Tests Pass**

- [ ] **Task 1.3**: `EnvironmentStatus` struct 확장
  - File: `Sources/MaestroCore/EnvironmentStatus.swift`
  - 필드 추가: `codex`, `gemini`, `codexAuth`, `geminiAuth: ToolStatus`
  - 계산 속성: `codexReady`, `geminiReady`
  - `AdapterRequirement.codex = [.node, .codex, .codexAuth]`
  - `AdapterRequirement.gemini = [.node, .gemini, .geminiAuth]`
  - `Tool` enum case 추가: `.codex`, `.gemini`, `.codexAuth`, `.geminiAuth`

- [ ] **Task 1.4**: `EnvironmentChecker` 확장
  - File: `Sources/MaestroCore/EnvironmentChecker.swift`
  - `checkCodex() async -> ToolStatus` — `codex --version` parsing
  - `checkGemini() async -> ToolStatus` — `gemini --version` parsing
  - `checkCodexAuth() async -> ToolStatus` — Spike 결과 기반 (config 파일 또는 환경변수)
  - `checkGeminiAuth() async -> ToolStatus` — 동일
  - `checkAll()` 에서 async let 으로 병렬 실행

- [ ] **Task 1.5**: `EnvironmentInstaller` 확장
  - File: `Sources/MaestroCore/EnvironmentInstaller.swift`
  - `installCodex(progress:) async throws` — `npm install -g <패키지명>` (AdapterInstaller 위임)
  - `installGemini(progress:) async throws` — 동일
  - 기존 closure DI 패턴 그대로 (`adapterInstall: AdapterInstallFunc`)

**🔵 REFACTOR: Clean Up Code**

- [ ] **Task 1.6**: 중복 제거 + 일반화
  - `checkVersionedAt(executable:args:minimumVersion:)` helper 가 codex/gemini 도 cover 하는지 확인
  - 필요 시 `checkAuth(at:)` 헬퍼 추출

#### Quality Gate ✋

- [ ] **TDD**: tests 먼저 작성 + 실패 → GREEN 통과
- [ ] **Build**: `swift build` clean
- [ ] **Tests**: `swift test` 100% pass (929 + 새 tests)
- [ ] **Lint**: `swiftlint lint` clean
- [ ] **Coverage**: 새 메서드 ≥80%
- [ ] **/simplify**: 변경된 4개 파일에 simplify skill 호출 → 권고 적용
- [ ] **/team 4-agent 리뷰**: A/B/C/D 관점 → HIGH must-fix 모두 반영
- [ ] **Commit + push + CI green**

**Validation Commands**:

```bash
cd /Users/gimgyeong-won/Desktop/kax/maestro
swift build 2>&1 | tail -5
swift test --filter EnvironmentChecker 2>&1 | tail -10
swift test --filter EnvironmentInstaller 2>&1 | tail -10
swiftlint lint Sources/MaestroCore/Environment*.swift 2>&1
```

---

### Phase 2A: CodexProfile + CodexAdapter Skeleton + detect

**Goal**: Codex 어댑터의 뼈대 — Profile 정의 + actor 클래스 + detect 메서드만. CodexAdapter 가 AdapterRegistry 에 등록되어 "감지됨" 표시까지.

**Estimated Time**: 2 hours

**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 2A.1**: `CodexProfileTests`
  - File: `Tests/MaestroAdaptersTests/CodexProfileTests.swift`
  - tests: `testAdapterIDIsCodex`, `testDisplayNameIsCodexOpenAI`, `testVersionRegexExtracts`, `testMakeProfileWithExecutable`
  - Expected: FAIL

- [ ] **Test 2A.2**: `CodexAdapterTests` — detect 부분
  - File: `Tests/MaestroAdaptersTests/CodexAdapterTests.swift`
  - tests: `testDetectReturnsInstalledWhenCLIPresent`, `testDetectReturnsNotInstalledWhenAbsent`, `testDetectCachesResult`
  - Expected: FAIL

**🟢 GREEN**

- [ ] **Task 2A.3**: `CodexProfile.swift`
  - File: `Sources/MaestroAdapters/CodexProfile.swift`
  - `enum CodexProfile`: `adapterID = "codex"`, `displayName = "Codex (OpenAI)"`, `executableName = "codex"`, `versionRegex`
  - `makeProfile(executable:) -> AgentProfile`
  - ClaudeProfile.swift 패턴 그대로

- [ ] **Task 2A.4**: `CodexAdapter.swift` skeleton
  - File: `Sources/MaestroAdapters/CodexAdapter.swift`
  - `public actor CodexAdapter: AgentAdapter`
  - 정적: `id, displayName, iconName`
  - 인스턴스: `id, displayName, iconName` 접근자
  - 의존성 주입: `executor, streamer, detector, sanitizer`
  - `init(...) throws`
  - `detect()` 구현 (cached + detector.detect())
  - 나머지 protocol 메서드는 `fatalError("not yet")` 또는 빈 구현

#### Quality Gate ✋

- [ ] TDD compliance, build, tests, lint, coverage, /simplify, /team
- [ ] CodexAdapter 가 AdapterRegistry 에 등록되면 detect 만으로도 감지됨 표시 (Phase 4 까지 미루지 말고 임시 등록 후 검증)

**Validation Commands**:

```bash
swift test --filter CodexProfile
swift test --filter "CodexAdapterTests/testDetect"
```

---

### Phase 2B: Codex Session Lifecycle + sendMessage (비스트리밍)

**Goal**: Codex 어댑터의 세션 생성/파기 + 비스트리밍 메시지 전송 (응답 받기). 한 번의 prompt → 한 번의 응답.

**Estimated Time**: 3 hours

**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 2B.1**: createSession / destroySession
  - tests: `testCreateSessionReturnsValidSession`, `testCreateSessionResolvesSymlink`, `testCreateSessionWithPreferredID`, `testDestroySessionRemovesFromMemory`
  - Mock executor 로 검증

- [ ] **Test 2B.2**: sendMessage (비스트리밍)
  - tests: `testSendMessageBuildsCorrectArguments`, `testSendMessageParsesResponse`, `testSendMessageHandlesError`, `testSendMessageRecordsModel`
  - Mock executor: stub stdout (Spike 에서 캡처한 실제 format 사용)

**🟢 GREEN**

- [ ] **Task 2B.3**: Session 관리 구현
  - `createSession(folderPath:)`, `createSession(folderPath:preferredSessionId:modelId:)`
  - `destroySession(_:)`
  - 내부 state: `sessions: [SessionID: Session]`, `initializedSessions: Set<SessionID>`

- [ ] **Task 2B.4**: sendMessage 구현
  - `resolveExecutable()` — detect → executablePath
  - `buildArguments(prompt:session:)` — Spike 결과 기반 argv 구성
  - `executor.run(...)` — 16MiB stdout cap
  - `CodexJSONResult.decode()` 또는 `CodexOutputParser.parse()` (Spike 결과 따라)
  - 응답 → `MessageEnvelope.report(...)`

- [ ] **Task 2B.5**: CodexJSONResult / CodexOutputParser (Spike 결정)
  - 만약 Codex 가 NDJSON 출력: `Sources/MaestroAdapters/CodexJSONResult.swift`
  - 만약 plain text: `Sources/MaestroAdapters/CodexOutputParser.swift` (AiderOutputParser 패턴)

**🔵 REFACTOR**

- [ ] **Task 2B.6**: 에러 처리 일관성 검토
  - `sendMessage` 의 에러 path 가 사용자 친화적인지
  - exit code / stderr 메시지 wrapping

#### Quality Gate ✋

- [ ] TDD, build, tests, lint, coverage ≥80%
- [ ] /simplify + /team
- [ ] Manual: 실제 Codex 설치된 환경에서 mock 없이 createSession + sendMessage 1회 성공

---

### Phase 2C: Codex Streaming + Output Parsing

**Goal**: Codex 어댑터의 스트리밍 응답 — 실시간 chunk 단위로 UI 에 흘러가도록. 가장 복잡한 phase.

**Estimated Time**: 4 hours (Spike 결과로 ±2h 변동)

**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 2C.1**: streamMessage 단위 테스트
  - tests: `testStreamingEmitsChunks`, `testStreamingParsesToolUse`, `testStreamingHandlesErrorMidstream`, `testStreamingRespectsStdoutCap`
  - Mock streamer 로 라인 단위 emission 검증

- [ ] **Test 2C.2**: CodexStreamParser (있다면)
  - tests: `testParseAssistantMessage`, `testParseToolUseEvent`, `testParseToolResult`, `testParseError`, `testParseModelExtraction`

**🟢 GREEN**

- [ ] **Task 2C.3**: `streamMessage(_:in:)` + `driveStream(...)`
  - nonisolated wrapper + actor 내부 driveStream
  - `streamer.stream(...)` (Spike 결과 기반 stream-json or SSE 처리)
  - 라인 파싱 → AgentEvent 변환 → AsyncThrowingStream emit
  - 모델 capture: `lastSeenModelBySession[session.id] = model`
  - Slash 명령 capture (있다면): `anySessionSlashCommands = cmds`
  - stderr 1KB snippet 수집
  - 종료 코드 처리

- [ ] **Task 2C.4**: `CodexStreamParser.swift` (NDJSON 인 경우)
  - File: `Sources/MaestroAdapters/CodexStreamParser.swift`
  - `parse(line:) -> ParsedChunk?` — assistant message / tool_use / tool_result / model / error
  - `extractModel(from:line:) -> String?`
  - `extractSlashCommands(from:line:) -> [String]?`

  또는 `CodexOutputParser.swift` (plain text, AiderOutputParser 패턴):
  - `extractAssistantResponse(from:lines:) -> String`
  - `detectKnownError(in:) -> String?`
  - `isHeaderOrFooter(_:) -> Bool`

**🔵 REFACTOR**

- [ ] **Task 2C.5**: 16MiB stdout cap + 1MiB scan window 검증
- [ ] **Task 2C.6**: 백프레셔 / cancellation 처리 일관성

#### Quality Gate ✋

- [ ] TDD, build, tests, lint, coverage ≥80%
- [ ] **Stress test**: 대용량 응답 (10K 토큰) 스트리밍 시 메모리 누수 X (Instruments 검증)
- [ ] **Cancellation**: stream 중간에 cancel → process 정리 + AsyncThrowingStream finish
- [ ] /simplify + /team
- [ ] Manual: 실제 Codex 로 long prompt 스트리밍 확인

---

### Phase 2D: Codex Slash Commands + Models + Final Polish

**Goal**: listSlashCommands, capturedSlashCommands, availableModels, resolvedModel — Claude 와 동등 기능 마무리.

**Estimated Time**: 2 hours

**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 2D.1**: slash 명령 + 모델
  - tests: `testListSlashCommandsReturnsBuiltins`, `testCapturedSlashCommandsAfterStream`, `testAvailableModelsReturnsKnownList`, `testResolvedModelPriority` (lastSeen > session.modelId > nil)

**🟢 GREEN**

- [ ] **Task 2D.2**: `listSlashCommands(in:)` 구현
  - Codex 의 builtin slash 명령 (Spike 결과: `/help`, `/model`, `/clear` 등)
  - 사용자 정의 명령 (있다면: `~/.codex/commands/` 같은 위치)

- [ ] **Task 2D.3**: `capturedSlashCommands()` 구현
  - `anySessionSlashCommands` actor state 반환

- [ ] **Task 2D.4**: `availableModels()` 구현
  - 알려진 모델 ID 리스트 (Spike 결과: `gpt-5`, `o1-preview`, `gpt-4o` 등)

- [ ] **Task 2D.5**: `resolvedModel(for:)` 구현
  - lastSeen > session.modelId > nil 우선순위

- [ ] **Task 2D.6**: `CodexSlashCommands.swift` (필요 시)
  - File: `Sources/MaestroAdapters/CodexSlashCommands.swift`
  - 정적 builtin 리스트 + 사용자 정의 scan 함수

**🔵 REFACTOR**

- [ ] **Task 2D.7**: CodexAdapter 전체 코드 리뷰 (line count, naming, doc comments)
- [ ] **Task 2D.8**: ClaudeAdapter 와 추출 가능한 helper 식별 (DRY)

#### Quality Gate ✋

- [ ] TDD, build, tests, lint, coverage ≥80%
- [ ] **/simplify**: CodexAdapter 전체에 대해 호출 → 권고 적용
- [ ] **/team 4-agent**: HIGH must-fix 모두 반영
- [ ] Manual: 실제 Codex 로 슬래시 명령 popover 표시 확인

---

### Phase 3A: GeminiProfile + Adapter Skeleton + detect

**Goal**: CodexAdapter (Phase 2A) 패턴 그대로 GeminiAdapter 시작.

**Estimated Time**: 2 hours

**Status**: ⏳ Pending

#### Tasks

- [ ] **Test 3A.1-2**: GeminiProfileTests, GeminiAdapterTests (detect)
- [ ] **Task 3A.3**: `GeminiProfile.swift`
- [ ] **Task 3A.4**: `GeminiAdapter.swift` skeleton

#### Quality Gate ✋

- [ ] Phase 2A quality gate 와 동일 + Codex 와 차이점 spike 에 기록

---

### Phase 3B: Gemini Session + sendMessage

**Goal**: GeminiAdapter 의 세션 + 비스트리밍 메시지

**Estimated Time**: 3 hours

**Status**: ⏳ Pending

#### Tasks

- [ ] **Test 3B.1-2**: createSession, sendMessage tests
- [ ] **Task 3B.3-5**: Session, sendMessage 구현 + Parser (Spike 결과)

#### Quality Gate ✋

- [ ] Phase 2B 와 동일 + Manual: 실제 Gemini 로 createSession + sendMessage 1회

---

### Phase 3C: Gemini Streaming + Slash + Models + Polish

**Goal**: GeminiAdapter 마무리 — Phase 2C + 2D 통합 (3시간)

**Estimated Time**: 3 hours

**Status**: ⏳ Pending

#### Tasks

- [ ] **Test 3C.1-2**: streamMessage, slash, models tests
- [ ] **Task 3C.3-5**: streaming + parser + slash + models 구현
- [ ] **Task 3C.6**: GeminiAdapter 전체 리뷰

#### Quality Gate ✋

- [ ] Phase 2C + 2D quality gate 통합
- [ ] **/simplify + /team**: GeminiAdapter 전체 + Codex 와 공통 추출 가능 helper 식별

---

### Phase 4: Adapter 등록 + AdapterDetectionViewModel 확장

**Goal**: 두 어댑터를 ControlTowerEnvironment 에 등록 + detection ViewModel 에 추가

**Estimated Time**: 1 hour

**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 4.1**: AdapterDetectionViewModelTests 확장
  - tests: `testCodexAndGeminiInSortedAdapterIDs`, `testCodexDisplayNameAndDescription`, `testGeminiHasFreeBadge`

**🟢 GREEN**

- [ ] **Task 4.2**: `ControlTowerEnvironment.swift` 수정
  - `collectAdapterCandidates()` 에 Codex/Gemini 추가:
    ```swift
    if let codex = try? CodexAdapter() { map[CodexAdapter.id] = codex }
    if let gemini = try? GeminiAdapter() { map[GeminiAdapter.id] = gemini }
    ```

- [ ] **Task 4.3**: `AdapterDetectionViewModel` 확장
  - sortedAdapterIDs 에 "codex", "gemini" 추가
  - displayName, description, installationHint, recommendationBadge 정의
  - Gemini 에 "무료 tier 1500/일" 같은 badge

#### Quality Gate ✋

- [ ] TDD, build, tests, lint
- [ ] /simplify + /team
- [ ] Manual: 폴더 추가 sheet 에 Codex / Gemini 행 보임 확인

---

### Phase 5: VendorPicker UI + Dependency Banner 일반화

**Goal**: VendorPickerSheet 의 aiderDependencyBanner → 공용 컴포넌트 (3개 어댑터 공유)

**Estimated Time**: 2 hours

**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 5.1**: 일반화된 banner ViewModel tests
  - `AdapterDependencyCheckerTests` (NEW)
  - tests: aider/codex/gemini 별 의존성 검사 결과

**🟢 GREEN**

- [ ] **Task 5.2**: `AdapterDependencyChecker.swift` (NEW, MaestroCore)
  - `checkDependencies(for adapterID: String) async -> [Tool: ToolStatus]`
  - 어댑터별 requirement 사용 (`AdapterRequirement.aider/codex/gemini`)

- [ ] **Task 5.3**: `VendorPickerSheet.swift` 의 banner 일반화
  - `aiderDependencyBanner` → `adapterDependencyBanner(for: adapterID)`
  - 3개 어댑터 모두 같은 컴포넌트 사용
  - canConfirm 도 일반화

**🔵 REFACTOR**

- [ ] **Task 5.4**: 기존 aider 흐름 회귀 X 검증

#### Quality Gate ✋

- [ ] TDD, build, tests, lint
- [ ] /simplify + /team — 일반화 코드의 정합성 집중 리뷰
- [ ] Manual: aider/codex/gemini 각각 의존성 누락 시 banner 표시 확인

---

### Phase 6: APIKeyStorage 확장 + Auth UI

**Goal**: openai / gemini API key 저장 (Keychain) + OAuth 로그인 안내 UI

**Estimated Time**: 2 hours

**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 6.1**: APIKeyStorageTests 확장
  - tests: `testStoreAndRetrieveOpenAIKey`, `testStoreAndRetrieveGeminiKey`, `testKeyNamespaceIsolation`

**🟢 GREEN**

- [ ] **Task 6.2**: `APIKeyStorage` 확장 (네임스페이스 자동 지원이라 코드 변경 거의 X)
  - 검증만 — `key(for: "codex")`, `key(for: "gemini")` 동작 확인

- [ ] **Task 6.3**: 어댑터 인증 검사
  - CodexAdapter / GeminiAdapter 의 sendMessage 시 인증 검사:
    - OAuth credentials 존재 OR API key 존재 → OK
    - 둘 다 없음 → 사용자 친화적 에러 메시지

- [ ] **Task 6.4**: Auth UI (Settings 또는 Onboarding)
  - "API Key 입력" 텍스트 필드 (선택)
  - "터미널에서 `codex auth login` 실행해주세요" 안내 (OAuth 권장)
  - 인증 성공 시 자동 갱신

**🔵 REFACTOR**

- [ ] **Task 6.5**: ClaudeAdapter 의 인증 패턴과 일관성 확인

#### Quality Gate ✋

- [ ] TDD, build, tests, lint
- [ ] /simplify + /team
- [ ] Manual: API key 입력 후 어댑터 dispatch 성공 / 인증 누락 시 안내 확인

---

### Phase 7: Slash Command Popover 통합

**Goal**: AdapterSlashCommandSource 가 codex/gemini 도 cover → v0.7.0 의 popover 흐름과 통합

**Estimated Time**: 2 hours

**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 7.1**: AdapterSlashCommandSource 확장 tests

**🟢 GREEN**

- [ ] **Task 7.2**: `AdapterSlashCommandSource.swift` 검증/확장
  - 이미 `capturedSlashCommands()` protocol 호출만 의존 → CodexAdapter / GeminiAdapter 가 이 메서드 구현하면 자동 통합
  - 검증: source 가 두 어댑터 모두 등록하는지

- [ ] **Task 7.3**: `ControlTowerEnvironment+Bootstrap.swift` 확인
  - `AdapterSlashCommandSource(adapter:)` 가 Codex/Gemini 인스턴스도 받는지

#### Quality Gate ✋

- [ ] TDD, build, tests, lint
- [ ] /simplify + /team
- [ ] Manual: chat composer 에서 `/` 입력 시 codex/gemini 의 builtin 명령 popover 에 표시

---

### Phase 8: Onboarding 환경 설정 통합

**Goal**: EnvironmentSetupSheet 에 Codex/Gemini statusRow + installMissing 일반화

**Estimated Time**: 2 hours

**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 8.1**: EnvironmentSetupViewModelTests 확장
  - tests: `testInstallMissingInstallsAllRequestedAdapters`, `testInstallMissingHandlesPartialFailure`

**🟢 GREEN**

- [ ] **Task 8.2**: `EnvironmentSetupSheet.swift` 확장
  - `statusRow(label: "Codex (OpenAI)", status: status.codex)`
  - `statusRow(label: "Codex 로그인", status: status.codexAuth)`
  - 동일하게 Gemini

- [ ] **Task 8.3**: `EnvironmentSetupViewModel.installMissing` 일반화
  - `installMissing(adapters: Set<String>)` — Set 으로 받아서 순차 설치
  - 또는 `installMissing(includeCodex: Bool, includeGemini: Bool, includeAider: Bool)` 호환 유지

**🔵 REFACTOR**

- [ ] **Task 8.4**: 기존 Claude 자동 설치 흐름 회귀 X 검증

#### Quality Gate ✋

- [ ] TDD, build, tests, lint
- [ ] /simplify + /team
- [ ] Manual: 온보딩 sheet 에서 Codex/Gemini 누락 → 자동 설치 → 모두 ✅ 흐름

---

### Phase 9: Documentation + QA Scenarios

**Goal**: 사용자 가이드 + QA 시나리오 작성

**Estimated Time**: 1 hour

**Status**: ⏳ Pending

#### Tasks

- [ ] **Task 9.1**: `docs/PACKAGING.md` 업데이트
  - Codex / Gemini CLI 설정 안내 (선택사항 어댑터)
  - 인증 흐름 (OAuth / API key)

- [ ] **Task 9.2**: `docs/qa-reports/scenarios/S11-codex-folder-add.md`
  - 시나리오: Codex 어댑터로 폴더 추가 + 첫 메시지

- [ ] **Task 9.3**: `docs/qa-reports/scenarios/S12-gemini-folder-add.md`
  - 시나리오: Gemini 어댑터로 폴더 추가 + 1M context 활용 예시

- [ ] **Task 9.4**: `docs/qa-reports/scenarios/S13-multi-vendor-orchestration.md`
  - 시나리오: control → codex → gemini → claude dispatch chain

- [ ] **Task 9.5**: `README.md` 업데이트 (있다면)
  - 지원 어댑터 리스트 갱신

#### Quality Gate ✋

- [ ] 문서가 실제 동작과 일치
- [ ] 새 시나리오 모두 manual 로 1회 검증
- [ ] Commit + push

---

### Phase 10: 통합 검증 (Verification Phase)

**Goal**: 실제로 동작하는지 end-to-end 검증 + v0.9.0 release

**Estimated Time**: 3 hours

**Status**: ⏳ Pending

#### Tasks

**10.1. 자동 검증 (CI 단계)**

- [ ] **Task 10.1.1**: 전체 빌드 + 테스트 실행

  ```bash
  swift build 2>&1 | tail -5
  swift test 2>&1 | tail -10  # 1000+ tests 예상
  swiftlint lint 2>&1 | grep -v "warning: Found"
  ```

- [ ] **Task 10.1.2**: CI green 확인 (push 후 GitHub Actions)

**10.2. Fresh User 시뮬레이션 (v0.8.0 패턴 재사용)**

- [ ] **Task 10.2.1**: Maestro 데이터 백업 + 이동

  ```bash
  BACKUP=/tmp/maestro-v090-test-$(date +%Y%m%d-%H%M%S)
  mkdir -p "$BACKUP"
  mv ~/Library/Application\ Support/Maestro "$BACKUP/Maestro.appdata"
  mv ~/Library/Preferences/Maestro.plist "$BACKUP/" 2>/dev/null
  mv ~/Library/Preferences/com.gimgyeongwon.maestro.plist "$BACKUP/" 2>/dev/null
  killall cfprefsd
  ```

- [ ] **Task 10.2.2**: codex / gemini binary 임시 가리기 (fresh 시뮬레이션)
  - `which codex && mv $(which codex) "$BACKUP/codex.binary"`
  - 동일하게 gemini

- [ ] **Task 10.2.3**: 새 DMG 설치 → 첫 실행
  - 검증 항목 (체크리스트):
    - [ ] 온보딩 sheet 가 Codex / Gemini 도 누락 표시 (Anthropic 로그인 + Codex + Codex 로그인 + Gemini + Gemini 로그인 모두)
    - [ ] "환경 자동 설치" 버튼 클릭 → 두 CLI 모두 설치 (npm install -g)
    - [ ] 설치 후 자동 재검사 → ✅
    - [ ] OAuth 안내 표시 (`codex auth login`, `gemini auth login`)
    - [ ] 폴더 추가 → vendor picker 에 Codex / Gemini 행 보임
    - [ ] Aider/Codex/Gemini 각각 의존성 banner 정상

**10.3. 실제 사용자 시나리오 (manual smoke test)**

- [ ] **시나리오 1**: Codex 어댑터로 새 폴더 추가 + 간단한 Swift 코드 작성 요청
  - "Hello world Swift class 만들어줘" → 응답 수신 확인
  - 결과: docs/qa-reports/scenarios/S11 에 기록

- [ ] **시나리오 2**: Gemini 어댑터로 동일 작업 + 1M context 활용
  - 큰 파일 (수천 줄) 분석 요청 → 응답 확인
  - 결과: S12 에 기록

- [ ] **시나리오 3**: 3개 어댑터 동시 띄우고 같은 질문 → 응답 비교
  - control → @codex / @gemini / @claude 라우팅 테스트
  - 결과: S13 에 기록

- [ ] **시나리오 4**: 슬래시 명령 popover 정상 동작
  - codex 폴더에서 `/` 입력 → codex builtin 명령 popover
  - gemini 폴더에서 `/` 입력 → gemini builtin 명령 popover

**10.4. 회귀 검증**

- [ ] **Task 10.4.1**: 기존 Claude 어댑터 동작 검증
  - 폴더 추가 → Claude 선택 → 메시지 전송 → 응답 확인

- [ ] **Task 10.4.2**: 기존 Aider 어댑터 동작 검증 (의존성 banner 일반화 회귀 X)
  - 폴더 추가 → Aider 선택 → git/python 의존성 banner 표시
  - 자동 설치 동작

- [ ] **Task 10.4.3**: 기존 v0.8.0 온보딩 흐름 정상

- [ ] **Task 10.4.4**: 기존 v0.7.0 슬래시 명령 popover 정상

**10.5. 성능 / 리소스 검증**

- [ ] **Task 10.5.1**: 3개 어댑터 동시 띄울 때 CPU / 메모리 측정
  - Activity Monitor 또는 `top -pid <pid>` 로 모니터링
  - 60분 idle 후 좀비 프로세스 X 확인 (`ps aux | grep -E "codex|gemini|claude"`)

- [ ] **Task 10.5.2**: PTY 프로세스 leak 검증
  - 폴더 5개 추가 + 각 어댑터로 dispatch + 1시간 idle → ptyPool 자동 정리 동작

**10.6. 출시 준비**

- [ ] **Task 10.6.1**: appVersion 0.8.0 → 0.9.0 bump
  - File: `Sources/MaestroCore/MaestroConfig.swift`
  - `public static let appVersion: String = "0.9.0"`

- [ ] **Task 10.6.2**: DMG 로컬 빌드

  ```bash
  scripts/build-app.sh
  scripts/build-dmg.sh
  ls build/Maestro-0.9.0.dmg
  ```

- [ ] **Task 10.6.3**: v0.9.0 git tag + push

  ```bash
  git tag -a v0.9.0 -m "v0.9.0 — Codex + Gemini 어댑터 추가"
  git push origin v0.9.0
  ```

- [ ] **Task 10.6.4**: GitHub Actions release 워크플로 trigger 확인
  - codesign + notarize + DMG + GitHub Release 자동 생성
  - `gh run watch <id>`

- [ ] **Task 10.6.5**: GitHub Release 페이지 검증
  - https://github.com/wonhp1/maestro/releases/tag/v0.9.0
  - DMG asset 첨부 확인
  - Release notes 자동 생성 확인

- [ ] **Task 10.6.6**: 백업 복원 + 정리
  - 시뮬레이션 백업에서 원상복구 (codex/gemini binary 위치 등)

#### Quality Gate ✋

**전체 종합 quality gate**:

- [ ] **자동 검증 모두 통과**: build clean, 1000+ tests pass, lint clean, CI green
- [ ] **Fresh user 시뮬레이션 4단계 모두 통과**: 온보딩 → 자동 설치 → vendor picker → dispatch
- [ ] **4 시나리오 모두 manual smoke 통과** + 결과 docs/qa-reports/ 에 기록
- [ ] **회귀 검증 4항목 모두 통과**: Claude/Aider/v0.8.0 온보딩/v0.7.0 popover
- [ ] **성능 검증 통과**: 메모리 누수 X, PTY leak X
- [ ] **출시 6단계 모두 완료**: version bump → DMG → tag → release workflow → GitHub Release → 백업 복원

---

## ⚠️ Risk Assessment

| Risk                                                        | Probability | Impact   | Mitigation Strategy                                                             |
| ----------------------------------------------------------- | ----------- | -------- | ------------------------------------------------------------------------------- |
| **Codex CLI 의 npm 패키지명이 예상과 다름**                 | Medium      | High     | Phase 0 Spike 에서 첫 30분 안에 확정. 안 되면 plan 재검토                       |
| **Codex/Gemini CLI 가 비대화형 모드 미지원**                | Low         | Critical | Spike 에서 검증. 미지원이면 plan 폐기 또는 PTY 인터랙션 개발 (큰 작업)          |
| **OAuth 가 ChatGPT Plus/Gemini Pro 구독 토큰을 인정 안 함** | Medium      | Medium   | API key fallback 으로 대응. 사용자 안내 명확히                                  |
| **Codex/Gemini 의 stream protocol 이 SSE / 기타**           | Medium      | Medium   | Aider 의 plain text 파서 패턴 차용. Phase 2C 에 +2h                             |
| **CLI 가 자주 breaking 업데이트**                           | Medium      | High     | 어댑터 코드에 protocol version 가드 + 사용자에게 호환 버전 안내                 |
| **Codex/Gemini 의 tool_use format 이 Claude 와 다름**       | High        | Medium   | 어댑터 별 변환 layer. AgentEvent 표현으로 통일                                  |
| **3개 어댑터 동시 띄울 때 메모리/CPU 폭증**                 | Low         | Medium   | Phase 10.5 에서 검증. ptyPool 의 idle 정리 로직 활용                            |
| **Spike 결과가 minimum viable 미달**                        | Low         | Critical | Spike 결과를 사용자와 공유 → plan 폐기 vs 진행 결정                             |
| **/simplify 또는 /team 리뷰가 큰 리팩터링 요구**            | Medium      | Medium   | Phase 별 시간 ±50% 변동 가능성 인지. 우선순위 HIGH 만 적용                      |
| **v0.8.0 와 충돌 (회귀)**                                   | Low         | High     | Phase 10.4 회귀 검증. 매 phase 마다 기존 tests 도 같이 실행                     |
| **CI macOS-15 runner 가 Codex/Gemini CLI 설치 못함**        | Medium      | Low      | adapter unit tests 는 mock subprocess 라 무관. integration smoke 는 manual 단계 |

---

## 🔄 Rollback Strategy

### Phase 0 (Spike) 실패

- spike doc 만 commit, 어댑터 작업 시작 X
- 사용자와 논의 후 plan 폐기 또는 minimal MVP 로 축소

### Phase 1-3 (Adapter implementation) 실패

- 해당 phase 까지의 commit revert
- `git revert <commit>` 또는 새 branch 에서 작업한 경우 branch 폐기

### Phase 4-8 (UI/등록) 실패

- 어댑터는 살리되 UI 등록만 제거 → 어댑터 코드는 보존
- 다음 release 에서 UI 만 다시 시도 가능

### Phase 9-10 (문서/검증) 실패

- 검증 실패 항목 별로 fix → 재검증
- 출시 단계 (10.6) 에서 실패 시 GitHub Release 만 draft 로 두고 fix 후 publish

### v0.9.0 release 후 critical 버그 발견

- Sparkle 자동 업데이트로 v0.9.1 hot fix push
- 또는 GitHub Release 의 v0.9.0 을 "withdrawn" 표시하고 v0.8.x 로 사용자 안내

---

## 📊 Progress Tracking

### Completion Status

- **Phase 0 (Spike)**: ⏳ 0%
- **Phase 1 (Env infra)**: ⏳ 0%
- **Phase 2A (Codex skeleton)**: ⏳ 0%
- **Phase 2B (Codex session+sendMessage)**: ⏳ 0%
- **Phase 2C (Codex streaming)**: ⏳ 0%
- **Phase 2D (Codex slash+models)**: ⏳ 0%
- **Phase 3A (Gemini skeleton)**: ⏳ 0%
- **Phase 3B (Gemini session+sendMessage)**: ⏳ 0%
- **Phase 3C (Gemini streaming+slash+models)**: ⏳ 0%
- **Phase 4 (Adapter 등록)**: ⏳ 0%
- **Phase 5 (VendorPicker UI)**: ⏳ 0%
- **Phase 6 (APIKeyStorage + Auth UI)**: ⏳ 0%
- **Phase 7 (Slash command 통합)**: ⏳ 0%
- **Phase 8 (Onboarding 통합)**: ⏳ 0%
- **Phase 9 (Documentation)**: ⏳ 0%
- **Phase 10 (Verification + Release)**: ⏳ 0%

**Overall Progress**: 0%

### Time Tracking

| Phase                   | Estimated | Actual | Variance |
| ----------------------- | --------- | ------ | -------- |
| Phase 0 (Spike)         | 4h        | -      | -        |
| Phase 1                 | 2h        | -      | -        |
| Phase 2A                | 2h        | -      | -        |
| Phase 2B                | 3h        | -      | -        |
| Phase 2C                | 4h        | -      | -        |
| Phase 2D                | 2h        | -      | -        |
| Phase 3A                | 2h        | -      | -        |
| Phase 3B                | 3h        | -      | -        |
| Phase 3C                | 3h        | -      | -        |
| Phase 4                 | 1h        | -      | -        |
| Phase 5                 | 2h        | -      | -        |
| Phase 6                 | 2h        | -      | -        |
| Phase 7                 | 2h        | -      | -        |
| Phase 8                 | 2h        | -      | -        |
| Phase 9                 | 1h        | -      | -        |
| Phase 10 (Verification) | 3h        | -      | -        |
| **Total**               | **38h**   | -      | -        |

---

## 📝 Notes & Learnings

### Implementation Notes

(매 phase 완료 시 학습한 것 기록)

### Blockers Encountered

(겪은 문제와 해결 기록)

### Improvements for Future Plans

(다음 plan 에 반영할 개선사항)

---

## 📚 References

### Architecture 분석 (이 plan 의 기반)

- ClaudeAdapter: `Sources/MaestroAdapters/ClaudeAdapter.swift` (365줄, actor)
- AiderAdapter: `Sources/MaestroAdapters/AiderAdapter.swift` (text 파싱 패턴)
- AgentAdapter protocol: `Sources/MaestroCore/AgentAdapter.swift`
- v0.8.0 plan: `docs/plans/PLAN_v0.8.0-environment-setup.md`

### 외부 자료

- OpenAI Codex CLI (Spike phase 에서 공식 GitHub URL 확정)
- Google Gemini CLI (Spike phase 에서 공식 GitHub URL 확정)
- Anthropic Claude Code: https://github.com/anthropics/claude-code (reference)

---

## ✅ Final Checklist

**v0.9.0 release 전 모든 항목 통과**:

- [ ] Phase 0 spike doc 작성 완료
- [ ] Phase 1-3 모든 어댑터 코드 + tests 완료
- [ ] Phase 4-8 통합 모두 완료
- [ ] Phase 9 문서 + QA 시나리오 작성
- [ ] Phase 10 자동 + manual + 회귀 + 성능 검증 모두 통과
- [ ] /simplify + /team 리뷰 모두 must-fix 반영
- [ ] swift build clean, 1000+ tests pass, swiftlint clean
- [ ] CI green
- [ ] Fresh user 시뮬레이션 4단계 통과
- [ ] 4 manual smoke 시나리오 통과 + docs 기록
- [ ] 기존 Claude/Aider/v0.8.0/v0.7.0 회귀 X
- [ ] DMG 로컬 빌드 성공
- [ ] v0.9.0 git tag + GitHub Actions release 워크플로 통과
- [ ] codesign + notarize + GitHub Release 페이지 게시 완료
- [ ] Sparkle appcast.xml 갱신 (자동 업데이트 push)

---

**Plan Status**: ⏳ Pending
**Next Action**: Phase 0 (R&D Spike) 시작 — Codex/Gemini CLI 실설치 + protocol 분석
**Blocked By**: 사용자 plan 승인
