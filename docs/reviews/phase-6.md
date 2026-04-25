# Phase 6 Review Report — Process 래퍼 + Streaming 인프라

**Date**: 2026-04-25
**Phase**: 6 / 23
**Status**: ✅ Complete
**Commits**: phase-6-start → phase-6-end

---

## Deliverables

`Sources/MaestroCore/`:

- `EnvironmentSanitizer.swift` — OAuth/시크릿 deny-list (Anthropic/OpenAI/HF/AWS/GitHub/Cloudflare/...) + suffix 패턴 (`_API_KEY`, `_TOKEN`, `_SECRET`, `_BASE_URL` 등) + `default` / `strict` (allow-list) 프리셋
- `ProcessStreamer.swift` — `ProcessStreaming` 프로토콜 + `DefaultProcessStreamer`
  - Task-based 동시 drain (race-free) — pipes EOF 까지 직접 read
  - `LineBuffer` — `\n` split + CRLF strip + `maxLineBytes` cap + skip-mode (cap 초과 라인의 잔여 폐기)
  - SIGTERM → grace → SIGKILL + PID reuse 가드 + Task cancel 전파
  - `ProcessStreamEvent`: `.stdoutLine` / `.stderrLine` / `.exited(exitCode, reason)` (`.exit` / `.uncaughtSignal`)
- `ProcessExecuting.swift` 확장 — `environment` 매개변수 (Phase 6 추가)
  - 기존 `currentDirectoryURL` 호출은 extension 으로 backward-compat
  - `ExitNotifier` 가 ProcessStreamer 와 공유

**Tests**: 237/237 통과 (Phase 5 의 208 → +29)

- EnvironmentSanitizerTests (10) — deny key / prefix / suffix / 시스템 보존 / strict / case-insensitive
- ProcessStreamerTests (16) — echo / stderr separation / multi-line / partial EOF / launch fail / timeout / cancellation / custom env / sanitized env / cwd / **high-volume 5K lines** / **multibyte UTF-8 across reads** / CRLF / zero-output / signal-killed / line cap truncate
- ProcessExecutorEnvTests (4) — custom env / nil inherits parent / sanitized blocks secret / **sanitized + cwd 결합**

---

## Step 2: 👥 /team Multi-Agent Review (4명 병렬)

### Architecture Reviewer — **Must-fix 3건, 모두 반영**

1. ❌→✅ `LineBuffer.append` O(N²) on big chunks → 단일 패스 + skip-mode + Data slice 안전 처리
2. ❌→✅ Watchdog Task leak on natural exit → terminationHandler 가 `watchdog?.cancel()`
3. ❌→✅ EnvironmentSanitizer deny-list 부족 → HF / Cohere / Mistral / Replicate / Groq / Google / Gemini / GitLab / Vercel / Cloudflare / Docker / SSH / KUBECONFIG / `_BASE_URL` 등 대폭 확장 + suffix 패턴 자동 차단

추가:

- ✅ `.exited` 가 `TerminationReason` (`.exit` / `.uncaughtSignal`) 카운드 (Phase 7 ClaudeAdapter 가 stop reason 매핑에 활용)
- ✅ trailing `\r` 자동 strip (CRLF)

### Security Reviewer — **Must-fix 3건, 모두 반영**

1. ❌→✅ ProcessStreamer 무제한 메모리 → `maxLineBytes` cap (기본 1 MiB) + skip-mode
2. ❌→✅ PID reuse race in cancel/watchdog SIGKILL → SIGKILL 직전 `process.isRunning` 재확인 + `[weak proc]`
3. ❌→✅ `environment: nil` 이 부모 env 무방비 상속 → doc 강화 + `EnvironmentSanitizer.strict` (allow-list) 프리셋 도입

추가:

- ✅ 모든 매칭 case-insensitive (`AnthRopic_API_KEY`, `aws_access_key_id` 모두 차단)
- ✅ FD close on launch failure
- ✅ readabilityHandler/terminationHandler race 제거 — Task-based drain 으로 전환

### Test Quality Reviewer — **Must-fix 5건, 모두 반영**

1. ❌→✅ High volume stream (5000 lines) — 모든 라인 보존 + 순서 검증
2. ❌→✅ Multi-byte UTF-8 across reads (한글 100KB 라인) — chunk 경계에서 정확 복원
3. ❌→✅ Cancellation during termination handler — 빠른 종료 race 검증
4. ❌→✅ Sanitizer case-insensitive — 명시적 검증
5. ❌→✅ Sanitized env + 커스텀 cwd 결합 검증

추가:

- ✅ Zero-output process (only `.exited` event)
- ✅ Signal-killed process (`reason == .uncaughtSignal`)
- ✅ Line cap truncation 동작
- ✅ CRLF trailing `\r` 제거

### Performance Reviewer — **Must-fix 1건, 모두 반영**

1. ❌→✅ LineBuffer O(N²) — 단일 패스 + Data slice 인덱싱 안전화

기각 (의도적):

- BufferingPolicy.bufferingNewest — JSON 스트림 dropping 잘못. unbounded 명시 의도.

---

## Step 3: ✨ /simplify

- `EnvironmentSanitizer.denySubstrings` 빈 배열 — YAGNI, 제거 (~6 lines)
- `ExitNotifier` 두 파일 중복 정의 → ProcessExecuting 의 것을 공유 (~30 lines)

기각:

- AtomicFlag 제거 — terminate signal 판별 로직 안전성에 필요
- 3개 파일 SIGTERM/grace/SIGKILL cascade 통합 — 패턴 약간씩 다름 (sync vs async vs detached), 추출 위험
- OneShot 단순화 — 동시성 안전성 우선

## Step 4: 🧩 Integration Verification

- Release build 통과
- App spawn + kill smoke OK
- 237/237 테스트 통과 (실제 `/bin/echo`, `/bin/sh`, `/bin/sleep`, `/usr/bin/seq` 사용)

## Step 5: 🔄 Regression Check

- Phase 1-5 통과 유지 (208 → 237, +29)

## Step 6: 📐 Architecture Compliance

- ✅ Core 단독 — Adapters 영향 없음
- ✅ Swift 6 Strict Concurrency — `nonisolated(unsafe)` 추가 없음. `@unchecked Sendable` 4건 (`StreamContext`, `LineBuffer`, `ExitNotifier`, `AtomicFlag` — NSLock 직렬화)
- ✅ ProcessExecuting backward-compat — extension default 로 기존 호출자 영향 없음
- ✅ Non-Goals: PTY 미지원 (Phase 7 ClaudeAdapter 가 필요시 별도 도입), stdin 미지원

---

## 놓치지 않은 Must-fix 요약

**총 12건 식별 → 12건 전부 반영**:

- **메모리**: maxLineBytes cap, watchdog leak 차단, async-let 누수 방지
- **레이스**: readabilityHandler↔terminationHandler 제거 (Task-based drain), PID reuse 가드
- **보안**: sanitizer 대폭 확장 (15+ 키 + suffix 자동 패턴 + strict allow-list 프리셋), case-insensitive 매칭
- **API 안전**: `.exited(exitCode, reason)` 으로 signal 구분, environment nil 경고, CRLF 정규화
- **테스트**: high-volume / multibyte / cap 등 5건 추가

---

## Open Items for Later Phases

1. **stdin 지원** — Phase 7 ClaudeAdapter 가 PTY-style 양방향 통신 필요 시 `ProcessPTYSession` 별도 도입
2. **AsyncStream backpressure** — 현재 unbounded. 매우 빠른 producer + 매우 느린 consumer 시 메모리 폭증 가능성. Phase 18 UI 통합 시 측정
3. **`run` 오버로드 정리** — ProcessExecuting 에 3개 호출 패턴 — 사용 패턴 굳어진 후 통합 검토
4. **kill cascade 헬퍼** — ProcessStreamer/ProcessExecuting 양쪽에 SIGTERM→grace→SIGKILL 패턴 중복. 약간씩 다른 sync/async 컨텍스트에 맞는 단일 헬퍼 도입 가능

---

## 완료 기준

- [x] Phase 6 Task 6.1~6.11 완료
- [x] 237/237 테스트 통과
- [x] /team 4명 병렬 리뷰 + **must-fix 12건 전원 반영**
- [x] /simplify 검토 + 2건 적용 (~36 lines 감소)
- [x] swiftlint --strict: 0 violations
- [x] Release build + app spawn 정상
- [x] Phase 1-5 회귀 없음
- [x] 레이어 경계 준수
- [x] 리뷰 리포트 저장 (이 파일)
- [x] phase-6-end 태그

**다음**: Phase 7 — Claude Adapter (첫 실제 어댑터 + Phase 4-6 인프라 통합 검증)
