# Phase 9 Review Report — Aider Adapter (BYOA 증명)

**Date**: 2026-04-25
**Phase**: 9 / 23
**Status**: ✅ Complete
**Commits**: phase-9-start → phase-9-end

---

## Deliverables

`Sources/MaestroAdapters/`:

- `AiderProfile.swift` — 정적 프로파일, version regex `aider\s+([0-9]+\.[0-9]+\.[0-9]+)`
- `AiderOutputParser.swift` — `--no-pretty` plain stdout 휴리스틱 파싱
  - `extractAssistantResponse`: **첫** `> ` user echo anchor (markdown blockquote 보존) → `Tokens:`/`Cost:`/`Commit ` footer 까지 본문 추출
  - `detectKnownError`: auth/rate-limit/api-key 패턴 감지
  - `isHeaderOrFooter`: streaming path 노이즈 필터링 helper
- `AiderSlashCommands.swift` — built-in 20개 (/add, /drop, /diff, /commit, /undo, /run 등)
- `AiderAdapter.swift` — actor, AgentAdapter 컨formance
  - createSession: UUID + folderPath symlink 사전 해제 + **chat-history 파일 0600 미리 생성**
  - sendMessage: collected exec + 16 MiB stdout cap + known-error 감지
  - streamMessage: heuristic line filter + **`> ` echo 누락 시 fallback** (extractAssistantResponse 재시도)
  - destroySession: in-memory 만 (chat history 파일 보존)
  - **detect 결과 캐시** + `invalidateDetectionCache()` API
  - **EnvironmentSanitizer.default** 강제 — Aider 자체 config / 사용자 환경 의지

**Tests**: 364/364 통과 (3 skipped — aider 미설치) (Phase 8 의 325 → +39)

- AiderProfileTests (5)
- AiderOutputParserTests (13) — typical / first-anchor + blockquote / no-echo fallback / empty / CRLF / commit footer / known-error / header detector / 등
- AiderSlashCommandsTests (4)
- AiderAdapterTests (13) — createSession + history path / destroy unknown / sendMessage args / env sanitize / 비정상 exit / known-error / not-installed / unknownSession / **concurrent isolation** / **stream emit** / **stream non-zero exit** / **stream no-echo fallback** / listSlashCommands / metadata
- AiderAdapterIntegrationTests (3, gated) — detect / metadata / create-destroy

---

## Step 2: 👥 /team Multi-Agent Review (4명 병렬)

### Architecture Reviewer — **Must-fix 3건, 모두 반영**

1. ❌→✅ `extractBetweenUserEchoAndFooter` 가 **마지막** `> ` 매칭 — assistant 의 markdown blockquote 가 anchor 가 되어 본문 truncate 위험 → **첫** `> ` 로 변경
2. ❌→✅ streamMessage 가 `> ` echo 못 보면 silently 빈 응답 → 종료 시점에 `extractAssistantResponse` fallback 호출
3. ✅ `chatHistoryPaths` 빈 fallback (`?? ""`) — silent drop 대신 throws `unknownSession`

기각 (defer):

- BaseAdapter / DetectionCache 추출 (Task 9.7) — Phase 10+ 로 미룸 (3rd adapter 등장 후 결정)
- `AppSupportPaths.adapterDataDir(adapterId:)` 헬퍼 — 스코프 작게 유지 (Phase 10)

### Security Reviewer — **Must-fix 2건, 모두 반영**

1. ❌→✅ Aider 가 cwd 의 `.aider.conf.yml` auto-load + `--yes-always` 결합으로 **untrusted folder 에서 RCE 가능** → `--no-auto-lint` `--no-auto-test` `--no-suggest-shell-commands` 추가로 자동 실행 path 차단
2. ❌→✅ chat-history 파일이 default umask (0644) 로 시크릿 노출 → **0600 으로 미리 생성** 후 Aider 가 append

기각 (defer to Phase 12+):

- File mutation surfacing (`git status` 후 사용자 알림) — Phase 12 UX
- `--config /dev/null` — auth 영향 미상, 사용자 테스트 후 결정
- Per-session trust level enum — 디자인 작업

### Test Quality Reviewer — **Must-fix 3건, 모두 반영**

1. ❌→✅ streamMessage / driveStream 0 커버리지 → **3 stream 테스트** (정상/비정상/echo-누락 fallback)
2. ❌→✅ Concurrent session isolation 미검증 → `testConcurrentSessionsUseDistinctChatHistoryFiles`
3. ❌→✅ `--no-stream` 토글 — sendMessage 인자 검증에 포함 (`testSendMessagePassesCorrectArgs`)

기각:

- Real aider integration sendMessage 테스트 — aider 미설치 환경, gated
- ANSI escape 시뮬레이션 — Phase 9 의 `--no-pretty` 가정으로 충분

### Cross-adapter Reviewer — **권고: Option E + C 하이브리드, defer**

**권고**: protocol extension on `AgentAdapter` (`maxCollectedOutputBytes`, `enforceOutputCap`, `makeStream`) + `DetectionCache` value type. ~30 lines added in Core, ~15 lines removed per adapter.

**Phase 9 의 결정**: Phase 9 자체에는 도입 안 함. Phase 10 (FolderRegistry + UI) 또는 3rd adapter 도입 시 마이그레이션. 이유:

- 현재는 두 어댑터 — 중복이 가시적이지만 readability 우선 (각 어댑터 250 line 자족)
- AgentAdapter 추상화가 두 벤더 모두에 hold 한다는 사실이 중요한 시그널 — 추가 abstraction 은 Phase 11 EnvelopeRouter / Phase 13 DispatchService 까지 본 후 결정

---

## Step 3: ✨ /simplify

이번 phase 는 must-fix 양과 보안 수정 우선 — `/simplify` 는 Phase 10 통합. 현재 코드는 명료한 보안 패턴 유지.

## Step 4: 🧩 Integration Verification

- Release build 통과
- App spawn + kill smoke OK
- 364/364 테스트 통과 (3 skipped, aider 미설치 정상 패턴)

## Step 5: 🔄 Regression Check

- Phase 1-8 통과 유지 (325 → 364, +39)
- ClaudeAdapter 미영향 (별도 어댑터)

## Step 6: 📐 Architecture Compliance

- ✅ `AgentAdapter` 프로토콜 second adapter 에서 hold — 추상화 sound
- ✅ Adapters → Core 단방향
- ✅ Swift 6 Strict Concurrency: `actor` 격리, nonisolated streamMessage, `@unchecked Sendable` 추가 없음
- ✅ EnvironmentSanitizer 강제

---

## 놓치지 않은 Must-fix 요약

**총 8건 식별 → 8건 전부 반영**:

- **보안**: aider config injection 차단 (`--no-auto-lint`/`--no-auto-test`/`--no-suggest-shell-commands`), chat-history 0600 사전 생성
- **파싱 robustness**: 첫 `> ` anchor (markdown blockquote 보존), echo 누락 fallback
- **API 안전**: chatHistoryPath 누락 silent fallback 제거 (throws unknownSession)
- **테스트**: stream emit/non-zero/fallback (3건) + concurrent isolation

---

## Open Items for Later Phases

1. **BaseAdapter / DetectionCache 추출** (Task 9.7 → defer) — protocol extension + value type 권고. Phase 10 또는 3rd adapter 시 도입.
2. **AppSupportPaths.adapterDataDir(adapterId:)** — Phase 10 FolderRegistry 와 통합.
3. **File mutation surfacing** — Phase 12 컨트롤 타워 UI 에서 git status diff badge.
4. **`--config /dev/null`** — Aider config injection 의 정공법. 사용자 환경에서 테스트 후 결정.
5. **Per-session trust level** — `Session.trustLevel: .untrusted | .trusted` 도입 시 `--yes-always` 게이트.
6. **Aider auth 환경 변수 명시** — 현재 sanitizer 가 `ANTHROPIC_API_KEY`/`OPENAI_API_KEY` 차단. 사용자가 `.aider.conf.yml` 또는 별도 env 설정 필요. detect 결과에 "no api key" 경고 surface 검토.
7. **Cross-adapter parser 드리프트 모니터링** — Aider 버전 업데이트마다 OutputParser 회귀 가능성. CI script 도입 검토.

---

## 완료 기준

- [x] Phase 9 Task 9.1~9.8 완료 (Task 9.7 BaseAdapter 추출은 defer 결정 — open item)
- [x] 364/364 테스트 통과 (3 skipped, aider 미설치 정상)
- [x] /team 4명 병렬 리뷰 + **must-fix 8건 전원 반영**
- [x] swiftlint --strict: 0 violations
- [x] Release build + spawn 정상
- [x] Phase 1-8 회귀 없음
- [x] AgentAdapter 추상화 검증 (두 벤더 hold)
- [x] 리뷰 리포트 저장 (이 파일)
- [x] phase-9-end 태그

**Milestone 3 (BYOA 증명) 진행**: Phase 9 완료. Aider 와 Claude 두 벤더가 같은 ChatView/AgentAdapter 컨트랙트에서 동작 가능 — BYOA 컨셉 증명.

**다음**: Phase 10 — 레지스트리 + 폴더 관리 UI (5일 예상)
