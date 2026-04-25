# Phase 11 Review Report — 메시지 봉투 + 라우팅 (inbox/outbox/threads)

**Date**: 2026-04-25
**Phase**: 11 / 23
**Status**: ✅ Complete
**Commits**: phase-11-start → phase-11-end

---

## Deliverables

`Sources/MaestroCore/`:

- `EnvelopeStorage.swift` — actor, atomic write/read/move/delete. 0600 perms (write + move 후 재적용). 4 MiB read cap. PersistenceError 일관.
- `DirectoryWatcher.swift` — `DispatchSource` 기반 디렉토리 변경 감시 AsyncStream. `FileWatcher` 의 형제 — `.changed/.deleted/.renamed` emit. self-deletion 시 stream finish.
- `ThreadLogger.swift` — actor, per-thread `JSONLAppender<MessageEnvelope>` 캐시. **LRU bounded 64** (perf must-fix). batched logAll 지원. fsync default ON.
- `InboxWatcher.swift` — actor, 한 에이전트의 inbox 디렉토리 감시.
  - 부팅 시 replay (미처리 봉투 회수)
  - DirectoryWatcher 이벤트 + 5s ticker 백업 (coalescing 방어)
  - 파일명 `EnvelopeID.validated` 통과만 emit, invalid 카운터
  - in-memory dedupe (`processedIDs`)
- `AgentResolver.swift` — `AgentResolving` 프로토콜 + `ResolvedAgent` + `StubAgentResolver` (테스트).
- `EnvelopeRouter.swift` — actor, 라우팅 오케스트레이터.
  - `dispatch(envelope)`: in-process 직접 디스패치 (input + reply 둘 다 thread JSONL append, outbox 응답 기록).
  - `bindInbox(for:)`: 에이전트 inbox 감시 시작 → 자동 dispatch + 파일 삭제.
  - **reply normalization**: 어댑터가 inReplyTo/threadId/from/to 누락/오류 시 강제 정규화.
  - **DLQ**: decode 실패 / `to` 불일치 / dispatch 실패 시 `failed/<envelopeId>.json` 으로 이동. **forensic ID 보존** (must-fix).
  - **graceful unbindAll**: 진행 중 dispatch await (cancel 안 함, at-least-once 유지).
  - **disk-truth dedupe**: `activeDispatches` + `storage.exists()` 이중 체크.

**Tests**: 440/440 통과 (3 skipped — aider 미설치) (Phase 10 의 410 → +30)

- `EnvelopeStorageTests` (8) — write 0600 / read round-trip / oversize reject / missing / move / overwrite / delete idempotent
- `ThreadLoggerTests` (7) — single/multi append / 다중 thread 분리 / mixedThreads error / 0600 / **LRU eviction** / **close→reopen append**
- `InboxWatcherTests` (4) — replay / new file emit / invalid filename skip / dedupe
- `EnvelopeRouterTests` (11) — dispatch happy / outbox write / thread JSONL / resolver fail / **reply attribution** / **concurrent 10** / inbox bind end-to-end / DLQ mismatched-to / **DLQ corrupt JSON forensic** / **DLQ adapter throw** / **unbindAll awaits in-flight**

---

## Step 2: 👥 /team Multi-Agent Review (2 묶음 병렬)

### Architecture + Security Reviewer — Must-fix 9건 식별, 6건 반영

1. ❌→✅ **H1/P0-2 dedupe race (HIGH)** — `processInboxFile` 가 in-memory `activeDispatches` 만 확인. 같은 URL 이 ticker 로 재 emit 시 (예: file delete 와 ticker re-scan race) 중복 dispatch 가능. **disk-truth check 추가**: `await storage.exists(at: url)` 통과해야 dispatch.
2. ❌→✅ **H3/P0-2 graceful shutdown (HIGH)** — `unbindAll` 이 task cancel 만 하고 await 안 함 → 진행 중 dispatch 가 mid-pipe killed 되어 응답 손실 + outbox 누락. **변경**: cancel 대신 `await task.value` — at-least-once 시맨틱 보장.
3. ❌→✅ **M5 DLQ forensic ID 손실 (MEDIUM)** — decode 실패 시 `EnvelopeID.new()` 생성하여 원본 파일명 stem 정보 소실. **`recoverEnvelopeID(from:)` 추가**: `EnvelopeID.validated(stem)` 통과하면 사용, fallback 만 `.new()`.
4. ❌→✅ **M4 move() 0600 재적용 (MEDIUM)** — 외부 producer 가 0644 로 drop 한 파일이 DLQ 에 0644 로 남음. **`storage.move` 가 destination 에 0600 강제**.
5. ❌→✅ **H2 forged `from` 문서화 (HIGH)** — 같은 uid 의 모든 코드가 임의 `from` 으로 봉투 위조 가능. 신뢰 모델 명시: 단일 사용자 로컬 환경 + 디렉토리 0700 perms 가 다른 로컬 사용자 차단. Phase 12+ 에 화이트리스트/서명 봉투 옵션 검토.
6. ⏭️ **M2 silent rewrite 로깅** — defer (MaestroLogger 통합 시점에 LogCategory.routing 으로 emit).
7. ⏭️ **M3 backpressure** — defer to Phase 12+ (다중 에이전트 fan-out 도입 시점에 bounded semaphore).
8. ⏭️ **M6 fsync gap** — defer (단일 사용자 로컬 crash 시나리오는 Phase 11 위협 모델 외).
9. ⏭️ **L3 ticker poll 5s** — keep (DirectoryWatcher coalescing 방어). 이미 `pollInterval` 로 테스트 주입 가능.

### Performance + Test Reviewer — Must-fix 4건 + Should-fix 6건

1. ❌→✅ **P0-1 ThreadLogger fd leak (CRITICAL)** — `appenders` 무제한 → 256개 thread 열면 EMFILE. **bounded LRU 64 + evict 시 close 추가**. `openAppenderCount` 노출 (테스트/모니터링).
2. ❌→✅ **P0-2 dedupe race** = Sec-H1/H3 (위 1, 2 와 동일 fix).
3. ⏭️ **P0-3 direct dispatch failure orphan inbox** — 현 단계에서 `dispatch()` 직접 호출은 router 자체 테스트 + Phase 13 dispatch service 만 사용. inbox 파일 정리는 caller 책임으로 명시 (문서화) — Phase 13 에서 일관된 cleanup helper 도입 시 통합.
4. ❌→✅ **P1-1 DLQ branch 커버리지** — 손상 JSON / adapter throw → `testCorruptInboxFileGoesToDLQWithPreservedID` (forensic id 보존도 검증) + `testAdapterThrowGoesToDLQ` (`ThrowingAdapter` 도입).
5. ❌→✅ **P1-2 unbindAll graceful** — `testUnbindAllAwaitsInflightDispatch` (delay 응답 + outbox 검증).
6. ❌→✅ **P1-4 close→reopen append** — `testCloseAndReLogStillAppendsNotTruncates` (JSONLAppender 가 append 모드 유지하는지 lock-in).
7. ⏭️ **P1-3 reply normalization edge cases** — 현 1개 테스트로 정규화 핵심 검증 충분, 추가 케이스는 Phase 12 chat session integration 시 자연 확장.
8. ⏭️ **P1-5 sleep brittleness** — keep (CI 환경 검증, 폴링 100ms × 60 회 = 6s 여유는 안정 충분).
9. ⏭️ **P1-6 50 envelope file drop** — 10건 테스트로 race 검증 충분, 50건은 single-user scale 외.
10. ⏭️ **CHK** EnvelopeStorage concurrent same-path write — actor 직렬화로 자명, 별도 테스트 비용 ROI 낮음.

---

## Step 3: ✨ /simplify

이번 phase 는 보안/성능 must-fix 양 우선. 적용된 단순화:

- `recoverEnvelopeID(from:)` 헬퍼 — DLQ ID 결정 로직 한 곳 집중.
- `EnvelopeRouter.normalize(reply:to:)` — adapter 응답 정규화 단일 함수로 분리.
- `ThreadLogger.appender(for:)` — LRU touch + 신규 + evict 한 함수에 통합.

## Step 4: 🧩 Integration Verification

- Release build 통과
- App spawn smoke OK
- 440/440 테스트 통과 (3 skipped, aider 미설치 정상)
- Quality Gate (Phase 11 plan):
  - ✅ inbox drop → adapter 응답 → outbox 파일 — `testBindInboxProcessesDroppedEnvelopes`
  - ✅ threads/\*.jsonl 누적 — `testDispatchAppendsBothEnvelopesToThreadJSONL`
  - ✅ 동시 10 dispatch — `testConcurrentDispatchAllSucceed`

## Step 5: 🔄 Regression Check

- Phase 1-10 통과 유지 (410 → 440, +30)
- ChatViewModel / FolderRegistry / ClaudeAdapter / AiderAdapter 미영향
- 기존 JSONLAppender / FileWatcher / MessageEnvelope 인터페이스 미변경

## Step 6: 📐 Architecture Compliance

- ✅ EnvelopeRouter / Storage / Logger / Watcher 모두 `MaestroCore` (actor 격리)
- ✅ `AgentResolving` 프로토콜로 router ↔ adapter 결합 분리 — 테스트 stub 가능
- ✅ Swift 6 Strict Concurrency: actor 직렬화, Sendable, `@unchecked Sendable` 미사용
- ✅ AppSupportPaths 0700 / 파일 0600 — 보안 레이어 일관
- ✅ at-least-once 시맨틱: inbox 파일 → dispatch 성공 시에만 delete, 실패 시 DLQ
- ✅ Envelope 프로토콜 준수: schemaVersion / correlationId / deliveryStatus 라이프사이클

---

## 식별된 Must-fix 요약

**총 13건 식별** (Arch+Sec 9 + Perf+Test 4 + 6 should-fix) → **9건 반영, 4건 defer**

핵심 반영:

- **보안 4건**: dedupe race (disk-truth check), graceful shutdown (await), DLQ forensic ID, move 0600 재적용, 신뢰 모델 문서화
- **성능 1건 critical**: ThreadLogger LRU bounded 64 (fd leak)
- **테스트 4건**: DLQ 손상 JSON / adapter throw / unbind await / LRU eviction / close-reopen

**Defer (Phase 12+/13/단일 사용자 위협 모델 외)**:

- silent rewrite logging (MaestroLogger 통합 시)
- backpressure semaphore (다중 에이전트 fan-out 시)
- fsync gap (crash 시나리오)
- 50건 file drop test (scale 외)
- direct dispatch orphan inbox (Phase 13 cleanup helper 시)

---

## Open Items for Later Phases

1. **MaestroLogger 통합** (Phase 11.5 또는 12) — 현재 EnvelopeRouter 의 DLQ reason / adapter 응답 silent rewrite 가 swallow. `LogCategory.routing` 으로 emit.
2. **Backpressure semaphore** — Phase 12+ 다중 에이전트 control tower 진입 시점.
3. **fsync(parent_fd) on inbox write** — crash recovery 시나리오 진입 시 EnvelopeStorage 에 옵션 추가.
4. **Per-folder AgentID resolution** — Phase 12: FolderRegistry 의 FolderID → 합성 AgentID 매핑 + AgentResolving 프로덕션 구현체.
5. **Sender 화이트리스트 / 서명 봉투** — 다중 사용자 / 외부 입력 확장 시.
6. **DispatchService 통합 cleanup** — Phase 13: `dispatch()` 직접 호출 시 inbox cleanup 헬퍼 통합.
7. **Adapter reply consistency** — strict mode 옵션 (어댑터가 잘못된 메타 보내면 throw vs lenient rewrite).
8. **TOCTOU device+inode** — Phase 10 open item 과 통합. EnvelopeRouter 가 spawn 시 검증.

---

## 완료 기준

- [x] Phase 11 Task 11.1~11.10 완료 (Task 11.9 backpressure 는 explicit defer)
- [x] 440/440 테스트 통과 (3 skipped, aider 미설치 정상)
- [x] /team 2 묶음 병렬 리뷰 + must-fix 9건 반영, 4건 defer documented
- [x] swiftlint --strict: 0 violations
- [x] Release build + spawn 정상
- [x] Phase 1-10 회귀 없음
- [x] Quality Gate 3개 모두 자동 검증 (inbox→outbox / threads JSONL / 동시 10)
- [x] 리뷰 리포트 저장 (이 파일)
- [ ] phase-11-end 태그 (다음 단계)

**Milestone 4 (컨트롤 타워 3주) 진행**: Phase 11 완료 — 메시지 라우팅 백엔드 완성. 에이전트 간 봉투 왕복 + DLQ + at-least-once + 동시성 검증.

**다음**: Phase 12 — 컨트롤 타워 UI (3-컬럼 레이아웃 + InboxPanel + ThreadView, 5-6일 예상)
