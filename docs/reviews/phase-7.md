# Phase 7 Review Report — Claude Adapter (첫 실제 어댑터)

**Date**: 2026-04-25
**Phase**: 7 / 23
**Status**: ✅ Complete
**Commits**: phase-7-start → phase-7-end

---

## Deliverables

`Sources/MaestroAdapters/`:

- `ClaudeProfile.swift` — 정적 프로파일 (executable, version regex `\b([0-9]+\.[0-9]+\.[0-9]+)\b`, detect args)
- `ClaudeJSONResult.swift` — `--output-format json` 결과 디코딩 + `validatedResultText()` 의미 검증 (`is_error` / `subtype` 처리)
- `ClaudeStreamParser.swift` — `--output-format stream-json --verbose` 라인 별 파싱 → `ResponseChunk` (text / thinking / toolUse / toolResult / completion / error)
- `ClaudeSlashCommands.swift` — built-in 10개 + `~/.claude/commands/` + `<folder>/.claude/commands/` 스캔. **심볼릭 링크 거부 + 16 KiB read cap**.
- `ClaudeAdapter.swift` — `actor`, `AgentAdapter` 컨formance
  - createSession: UUID + folderPath symlink 사전 해제 (TOCTOU 방어)
  - sendMessage: collected JSON 모드 + stdout 16 MiB cap (OOM 방어)
  - streamMessage: stream-json 모드, **첫 stdout 도착 시점에 initialized 기록** (cancel 후 재시도가 --resume 으로)
  - listSlashCommands: built-in + user + project
  - destroySession: in-memory 만 (디스크 세션 파일은 보존 — 사용자가 `claude --resume` 으로 재개 가능)
  - **detect() 결과 캐시** + `invalidateDetectionCache()` API (perf must-fix)
  - **EnvironmentSanitizer.default** 강제 — Claude 자체 인증 (Keychain) 활용

**Tests**: 292/292 통과 (Phase 6 의 237 → +55)

- ClaudeProfileTests (4)
- ClaudeJSONResultTests (6) — 성공 / unknown fields / error / missing result / malformed / subtype-error edge
- ClaudeStreamParserTests (10) — assistant text / thinking / tool_use / user tool_result / result success-error / system 무시 / malformed / unknown type / 다중 블록
- ClaudeSlashCommandsTests (9) — built-ins / 빈 dir / .md filter / description / frontmatter / 정렬 / 빈 file / **symlink 거부** / **큰 파일 cap**
- ClaudeAdapterTests (16) — createSession / destroy / sendMessage 첫/재호출 / env sanitize / cwd / claude error / processFailed / notInstalled / unknownSession / streamMessage 기본 / 초기화 / non-zero / listSlashCommands / 메타데이터
- ClaudeAdapterStreamTests (6) — verbose 인자 / sendMessage 비-verbose / **stderr 미-yield** / **stderr propagation** / **첫 stdout init 시점** / error 후 not-initialized
- ClaudeAdapterDetectionCacheTests (2) — cache hit / invalidate 후 재detect
- ClaudeAdapterIntegrationTests (3, **실제 claude CLI**) — detect / metadata / create-destroy real session

---

## Step 2: 👥 /team Multi-Agent Review (4명 병렬)

### Architecture Reviewer — **Must-fix 1건, 모두 반영**

1. ❌→✅ Stream `--session-id`/`--resume` race on cancel — initializedSessions 가 stream 완료 후에만 set 됨. 사용자가 mid-stream cancel 시 다음 호출에서 `--session-id` 가 기존 세션 파일과 충돌. → **첫 stdout 도착 시점에 set** 으로 변경.

기각 (defer):

- `streamMessage` early validation in nonisolated wrapper — UX 영향 미미
- exit-code throw vs error chunk channel — 현재 동작 OK
- `StaticAgentProfile` protocol 추출 — Phase 9 Aider 패턴 확정 후 결정
- `destroySession.preserveHistory` 파라미터 — Aider 시 추가
- `listSlashCommands` 캐시/invalidation hook — Phase 8 UI 통합 시 결정

### Security Reviewer — **Must-fix 2건, 모두 반영**

1. ❌→✅ Symlink escape + unbounded file read in slash commands → **symlink 자체 거부** (`attributesOfItem` 체크) + `FileHandle.read(upToCount: 16 KiB)` cap
2. ❌→✅ JSON DoS — collected stdout 무제한 → **16 MiB cap** before decode

추가:

- ✅ folderPath symlink 사전 해제 (TOCTOU)
- ✅ stderr 로그 simplified — "claude stderr" 만 (라인 내용 노출 안 함)
- ✅ `EnvironmentSanitizer.default.sanitizedProcessEnvironment()` 강제 — Claude 의 OAuth 토큰 차단

기각: argv `--` separator (argv-array 가 이미 안전), executable PATH allowlist (사용자 PATH 신뢰).

### Test Quality Reviewer — **Must-fix 4건, 모두 반영**

1. ❌→✅ stderr 분기 미커버 → `testStderrLinesNotYieldedAsChunks`
2. ❌→✅ stderr 가 throw 메시지에 포함되지 않음 → `testNonZeroExitPropagatesStderr` + 코드 변경
3. ❌→✅ streamMessage cancellation 테스트 → `testInitializedAtFirstStdoutNotAtStreamEnd` (break 후 상태 확인)
4. ❌→✅ `--verbose` flag 검증 → `testStreamArgsIncludeVerboseAndStreamJSON` + 반대 케이스

추가: `RecordingStreamerSpy` actor stub 도입.

### Performance Reviewer — **Must-fix 2건, 모두 반영**

1. ❌→✅ `detect()` per-call spawn → actor `cachedDetection` 도입 (Phase 7 perf must-fix). 두 번째 sendMessage 부터는 detector 호출 없음 (테스트로 검증).
2. ❌→✅ `firstMeaningfulLine` 전체 파일 read → `FileHandle.read(upToCount: 16 KiB)` 로 cap.

기각:

- listSlashCommands mtime 캐시 — Phase 8 UI 도입 시 결정
- 액터 cross-session parallelism (nonisolated send) — 큰 재구조, 정량 데이터 후 결정
- Codable enum stream parser — Claude schema 안정 후 마이그레이션

---

## Step 3: ✨ /simplify

- `ClaudeStreamParser.extractFinalResultText` 제거 — 미사용 (~11 lines + 2 테스트)
- `validatedAgentId` / `validatedAdapterId` cache 인라인 — premature opt
- `buildArguments` 의 `verbose` 파라미터 제거 — `outputFormat == "stream-json"` 으로 derive

기각:

- `ClaudeProfile` 인라인 — Phase 9 Aider 가 같은 패턴 사용 예정
- `activeSessionIds()` 제거 — 테스트가 사용
- `ClaudeJSONResult` 슬림화 — `sessionId`/`stopReason` 은 향후 logger/diagnostic 활용 예정
- frontmatter 파싱 단순화 — 현재 동작 확실

## Step 4: 🧩 Integration Verification

- Release build 통과
- App spawn + kill smoke OK
- 292/292 테스트 통과 (실제 `claude` CLI 통합 3건 포함 — 사용자 환경에 claude 2.1.118 존재 확인)

## Step 5: 🔄 Regression Check

- Phase 1-6 통과 유지 (237 → 292, +55)

## Step 6: 📐 Architecture Compliance

- ✅ Adapters → Core 단방향. `ClaudeAdapter` 는 `MaestroCore` 의 `AgentAdapter` 프로토콜만 의존.
- ✅ Swift 6 Strict Concurrency: `actor` 격리, `nonisolated` streamMessage wrapper (cancellation 전파). `@unchecked Sendable` 추가 없음.
- ✅ Non-Goals: PTY 미지원 (interactive `claude` 모드 — 향후 별도). MCP 직접 통합 없음 (claude 가 자체 처리).
- ✅ EnvironmentSanitizer 강제 — Claude OAuth 토큰 leak 차단.

---

## 놓치지 않은 Must-fix 요약

**총 9건 식별 → 9건 전부 반영** (보너스 4건 포함):

- **보안**: symlink 거부, 16 MiB stdout cap, 16 KiB md read cap, folderPath TOCTOU 해제, stderr privacy
- **레이스**: stream init 시점 변경 (cancel 후 --resume 정확)
- **성능**: detect cache + invalidate API, file read cap
- **API**: stderr error propagation, `--verbose` 자동 derive
- **테스트**: 4 must-fix 케이스 전부 추가

---

## Open Items for Later Phases

1. **PTY 모드 ClaudeAdapter** — interactive `claude`, `Ctrl+C` 핸들링. Phase 8 UI 도입 시 필요할 가능성
2. **Cross-session 병렬성** — actor 가 send 직렬화. 정량 측정 후 nonisolated split 검토
3. **Slash command discovery via system init** — 첫 sendMessage 시 자동으로 모든 slash 학습 (CLI spawn 시점)
4. **Codable enum stream parser** — Claude stream-json 스키마 stable 확인 후 마이그레이션 (현재 untyped `[String: Any]`)
5. **session_id collision 방어** — Maestro 가 발급한 UUID 가 Claude 가 이미 가진 파일과 충돌? UUID 4 라 수학적으로 0% 이지만 sanity check
6. **Aider Adapter (Phase 9) 패턴 통합** — `ClaudeProfile` enum 패턴이 좋은지 / `StaticAgentProfile` 프로토콜로 추출할지 결정

---

## 완료 기준

- [x] Phase 7 Task 7.1~7.12 완료
- [x] 292/292 테스트 통과 (실제 claude CLI 3건 포함)
- [x] /team 4명 병렬 리뷰 + **must-fix 9건 전원 반영**
- [x] /simplify 검토 + 3건 적용 (~25 lines)
- [x] swiftlint --strict: 0 violations
- [x] App release build + spawn 정상
- [x] Phase 1-6 회귀 없음
- [x] 레이어 경계 준수 (Adapters → Core 단방향)
- [x] 리뷰 리포트 저장 (이 파일)
- [x] phase-7-end 태그

**다음**: Phase 8 — 기본 채팅 UI (SwiftUI + Markdown + 스트리밍 표시)
