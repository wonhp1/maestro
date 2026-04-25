# Phase 4 Review Report — AgentAdapter 프로토콜 + CLI 감지

**Date**: 2026-04-25
**Phase**: 4 / 23
**Status**: ✅ Complete
**Commits**: phase-4-start → phase-4-end

---

## Deliverables

`Sources/MaestroCore/` (Phase 4 신규):

- `AgentAdapter.swift` — 모든 AI 코딩 에이전트의 공통 프로토콜 (BYOA 핵심 추상화)
  - 정적 메타: `id` / `displayName` / `iconName`
  - 인스턴스 dispatch: `id` / `displayName` / `iconName` (witness 테이블 진입)
  - 라이프사이클: `detect` / `createSession` / `destroySession`
  - 메시지: `sendMessage` (필수) / `streamMessage` (default) / `listSlashCommands` (default)
  - `AdapterError` (notInstalled / sessionCreationFailed / unknownSession / processFailed / unsupported)
- `AdapterDetection.swift` — `isInstalled` / `version` / `executablePath` / `detectedAt`
- `ResponseChunk.swift` — 스트리밍 청크 (text / **thinking** / toolUse / toolResult / **error** / completion)
- `SlashCommand.swift` — 명령 메타 (name / description / category / **arguments**)
- `AdapterRegistry.swift` — actor, register/unregister/find + `detectAll()` 병렬
- `CLIDetector.swift` — 어댑터 프로파일 기반 자동 감지 (locator + executor 주입)
- `ExecutableLocating.swift` — `PATHExecutableLocator` 기본 구현 (PATH 분할 + 절대경로 직통)
- `ProcessExecuting.swift` — `DefaultProcessExecutor`: 동시 drain + SIGKILL 에스컬레이션 + cancellation

`Sources/MaestroAdapters/`:

- `MockAdapter.swift` — actor, 테스트/UI 프리뷰 전용. echo 응답 + 커스텀 responder.
- `MaestroAdapters.swift` — 모듈 식별자 (scaffold)

**Tests**: 183/183 통과 (121 → +62)

- AdapterDetectionTests (3)
- AgentAdapterProtocolTests (5) — default impl 검증
- AdapterRegistryTests (10) — register/unregister/detectAll 병렬성 wall-clock 검증
- ResponseChunkTests (4) — 모든 Kind exhaustive
- SlashCommandTests (3)
- CLIDetectorTests (19) — 스텁 5건 + extractVersion 4건 + PATH locator 7건 + ReDoS truncate 1건 + E2E 1건 + executor-throws 1건
- DefaultProcessExecutorTests (6) — /bin/echo, /bin/sh, /bin/sleep 으로 OS 경계 검증 (normal / non-zero / launch fail / timeout / 256 KiB pipe drain / cancel)
- MockAdapterTests (12) — 메타데이터 / 세션 / 메시지 / streaming / 슬래시 / Registry 연동

---

## Step 2: 👥 /team Multi-Agent Review (4명 병렬)

### Architecture Reviewer — **Must-fix 3건, 모두 반영**

1. ❌→✅ DefaultProcessExecutor 는 wait → drain 순서로 pipe buffer (~64 KiB) 포화 시 deadlock → **동시 drain (async let stdoutTask/stderrTask)** 으로 재구성
2. ❌→✅ Registry `replacingExisting` 기본 `true` 가 silent replacement footgun → **기본 `false`** 로 flip, 명시적 교체만 허용
3. ❌→✅ default `streamMessage` 가 `MessageEnvelope.body` 만 `.text` 로 평탄화하여 toolUse/toolResult 손실 → **doc warning 강화** + Phase 7 어댑터는 반드시 override 명시

### Security Reviewer — **Must-fix 4건, 모두 반영**

1. ❌→✅ Pipe buffer deadlock (Architecture #1 과 동일) → 동시 drain
2. ❌→✅ SIGTERM-only timeout → SIGTERM 후 `gracePeriod` 안에 미종료 시 **SIGKILL 에스컬레이션** + `await exitNotifier.wait()` 로 reap
3. ❌→✅ Task cancellation 누수 → **`withTaskCancellationHandler`** 로 onCancel 에서 SIGTERM + 비동기 SIGKILL 백업
4. ❌→✅ ReDoS via versionRegex on 2 MiB output → regex 입력을 **첫 16 KiB 로 truncate**

추가:

- ❌→✅ Pipe FD leak on launch failure → `try? close()` 명시
- ❌→✅ MockAdapter 의 가짜 executablePath → `nil` 반환

### Test Quality Reviewer — **Must-fix 3건, 모두 반영**

1. ❌→✅ DefaultProcessExecutor 0 테스트 → **6 OS-level 테스트** (정상/비정상 exit/launch fail/timeout/256 KiB drain/cancel)
2. ❌→✅ CLIDetector E2E (real locator + real executor + real binary) 부재 → `/bin/echo` 으로 **E2E 테스트** 추가
3. ❌→✅ AdapterRegistry.detectAll 진짜 병렬성 미검증 → SlowAdapter 5개로 **wall-clock 200ms < x < 600ms** 단언

추가:

- PATH 엣지 케이스 (`::/bin::/usr/bin:`, 빈 string, 디렉토리 shadowing) 3 테스트 추가
- MockAdapter.streamMessage default impl 테스트 추가

### Performance Reviewer — **Must-fix 2건, 모두 반영**

1. ❌→✅ Pipe drain 후 wait → deadlock (Arch/Sec와 동일)
2. ❌→✅ SIGTERM-only timeout → SIGKILL escalation
3. (보너스) `DispatchQueue.global().async + waitUntilExit` 패턴 → `terminationHandler + ExitNotifier` 콜백 패턴으로 **thread 절약**

---

## Step 3: ✨ /simplify

- CLIDetector 의 `clock` 주입 (test-only, 미사용) 제거 — 5 lines
- CLIDetector instance `extractVersion` 래퍼 (정적 메서드 단순 위임) 제거 — 5 lines
- 기각: pathOverride (테스트 5+ 의존), gracePeriod 노출 (테스트 사용), Kind/arguments 확장 (의도적 future-proof, 리뷰에서도 인정)

## Step 4: 🧩 Integration Verification

- App 정상 실행 (release 빌드, 2초 spawn → kill)
- 183/183 테스트 통과 (temp dir + /bin/\* 실행파일)

## Step 5: 🔄 Regression Check

- Phase 1 (9) + Phase 2 (79) + Phase 3 (33) 통과 유지
- 합계 121 → 183 (+62)

## Step 6: 📐 Architecture Compliance

- ✅ 레이어 경계: MaestroCore → no MaestroAdapters import; MaestroAdapters → MaestroCore (단방향). CLIDetector/ProcessExecuting/ExecutableLocating 은 generic 유틸이므로 **Core 로 이동** (Architecture #4 SHOULD-FIX 반영)
- ✅ Swift 6 Strict Concurrency: 모든 신규 타입 `Sendable`. `@unchecked Sendable` 은 `OneShot`/`ExitNotifier` 2건만 (NSLock 직렬화).
- ✅ Non-Goals: 어댑터 구현체는 Phase 7+ 로 미룸. PTY/cloud sync 없음.
- ✅ AgentAdapter 프로토콜은 Claude (interactive PTY-style) / Aider (one-shot stdio) / Cursor 모두에 fit — 종이 설계 검증. `streamMessage` 가 텍스트-only fallback 을 제공하면서도 구조화된 청크 발행을 강제할 수 있음.

---

## 놓치지 않은 Must-fix 요약

**총 13건 식별 → 13건 전부 반영** (보너스 4건 포함):

- **보안/내구성**: pipe drain deadlock, SIGKILL escalation, cancellation hook, ReDoS truncate, FD close on fail, MockAdapter null path
- **API 안전**: Registry 기본 reject duplicate, streamMessage doc warning
- **확장성**: ResponseChunk +.thinking/.error, SlashCommand +arguments
- **레이어**: CLIDetector/ProcessExecuting/ExecutableLocating → Core 이동
- **테스트**: 6 OS-level executor 테스트, E2E CLIDetector, Registry 병렬성 wall-clock

---

## Open Items for Later Phases

1. **Production 어댑터 구현** — Phase 7 ClaudeAdapter (PTY-style streaming), Phase 9 AiderAdapter (one-shot stdio). 둘 다 `streamMessage` override 필요.
2. **Detection 캐시** — Architecture SHOULD-FIX #5: `detectAll(maxAge:)` 오버로드. UI 가 Phase 18 에 health-panel 매 렌더마다 부르지 않도록.
3. **PATH hijack hardening** — Security S2: world-writable PATH 컴포넌트 경고. Phase 21 entitlement 검토 시 함께.
4. **Symlink TOCTOU** — Security S3 / N3: `URL.resolvingSymlinksInPath()` + 단일 stat. 현실 위협은 낮음.
5. **CompletionReason enum** — Architecture NIT #12: `ResponseChunk.completion(reason: String)` 의 reason 을 `endTurn/maxTokens/stopSequence/error/cancelled` enum 으로. Phase 7 에서 LLM stop reason 매핑 시 정의.
6. **DiagnosticsBundle 통합** — Phase 5 에서 `AdapterDetection.diagnostics: ProcessOutput?` 추가 검토.

---

## 완료 기준

- [x] Phase 4 Task 4.1~4.10 전부 완료
- [x] 183/183 테스트 통과
- [x] /team 4명 병렬 리뷰 + **must-fix 13건 전원 반영**
- [x] /simplify 검토 + 2건 적용 (clock 주입 + extractVersion wrapper 제거)
- [x] swiftlint --strict: 0 violations
- [x] App 정상 실행 (release build)
- [x] Phase 1-3 회귀 없음
- [x] 레이어 경계 준수 (Core ⟂ Adapters)
- [x] 리뷰 리포트 저장 (이 파일)
- [x] Phase 4 완료 커밋 + phase-4-end 태그

**다음**: Phase 5 — 로깅/옵저버빌리티 (OSLog + 진단)
