# Phase 3 Review Report — 파일 영속성 + Keychain

**Date**: 2026-04-25
**Phase**: 3 / 23
**Status**: ✅ Complete
**Commits**: 98a4199 (초기) + 후속 must-fix 커밋

---

## Deliverables

`Sources/MaestroCore/`:

- `PersistenceError.swift` — 10개 에러 케이스 (readFailed, resourceLimitExceeded 등 추가)
- `AppSupportPaths.swift` — 경로 상수 + 0700 디렉토리 권한
- `FileStore<T>` — atomic JSON + 0600 파일 권한 + 파일 크기 제한 (10 MiB)
- `JSONLAppender<T>` — 캐시된 FileHandle + fsync + 동시성 안전
- `JSONLTailer<T>` — 청크드 read + partial buffer cap (16 MiB) + truncation 감지 + error 시 source.cancel
- `FileWatcher` — delete/rename 시 stream 자동 finish + coalescing 문서화
- `KeychainStore` — delete-then-add (legacy 속성 청소) + kSecAttrSynchronizable=false

**Tests**: 121/121 통과 (79 → +42)

- AppSupportPathsTests (6)
- FileStoreTests (10 + size-limit + 0600 permissions)
- JSONLAppenderTests (9 + concurrent + 0600 + close-reopen)
- JSONLTailerTests (4 + malformed + partial EOF)
- FileWatcherTests (4 + rename + delete)
- KeychainStoreTests (8)

---

## Step 2: 👥 /team Multi-Agent Review (4명 병렬)

### Architecture Reviewer — **Must-fix 4건, 모두 반영**

1. ❌→✅ JSONLTailer error path 에서 `source.cancel()` 미호출 → `cancelOnError` 헬퍼 도입
2. ❌→✅ Truncation 감지 (seek past EOF 시 silent no-op 방지) → `currentFileSize < offset` 비교 후 reset
3. ❌→✅ FileStore atomicity 한계 문서화 (rename은 보장, dir fsync 안 함) → 코드 주석 추가
4. ❌→✅ JSONLAppender fsync 추가 (`synchronize: true` 기본) → at-least-once 보장

### Security Reviewer — **Must-fix 3건, 모두 반영**

1. ❌→✅ 파일 권한 **0644 → 0600** (FileStore + JSONLAppender), 디렉토리 **0700** (AppSupportPaths.ensureAllDirectoriesExist)
2. ❌→✅ JSONLTailer 무제한 partial 버퍼 → `maxPartialLineBytes: 16 MiB` cap + OOM 방어
3. ❌→✅ Keychain update 시 `kSecAttrAccessible` 보존 안 됨 → **delete-then-add** 패턴으로 strict 재기록. `kSecAttrSynchronizable=false` 명시 (iCloud 비동기화)

- 추가: FileStore 에 `maxFileSize: 10 MiB` 기본 상한
- 추가: O_CLOEXEC 플래그 (fork/exec 시 FD 유출 방지)

### Test Quality Reviewer — **Must-fix 4건, 모두 반영**

1. ❌→✅ JSONLTailer malformed line / partial EOF 테스트 추가
2. ❌→✅ FileWatcher rename / delete 이벤트 테스트 추가
3. ❌→✅ JSONLAppender 100개 concurrent append 테스트 (actor 직렬화 증명)
4. ❌→✅ FileStore 파일 크기 제한 + 0600 권한 검증 테스트 추가

### Performance Reviewer — **Must-fix 4건, 모두 반영**

1. ❌→✅ JSONLAppender per-call FileHandle open/close → **캐시된 handle** + lazy open
2. ❌→✅ JSONLTailer `readDataToEndOfFile()` → **chunked read (64 KiB)** 루프로 100MB delta 메모리 폭발 방지
3. ❌→✅ partial buffer 무제한 growth → 16 MiB cap (Security #2 와 동일)
4. ❌→✅ FileWatcher coalescing 소비자에게 명시 → DocC 경고 + 이벤트 1:N 매핑 문서화

---

## Step 3: ✨ /simplify

- PersistenceError 에러 타입 통일 (read vs write 구분으로 오용 방지)
- FileStore.load 의 `atomicWriteFailed` 오용 → `readFailed` 로 정정

## Step 4: 🧩 Integration Verification

- 121 테스트 통과 (temp dir + Keychain 실 환경)
- 앱 실행 확인

## Step 5: 🔄 Regression Check

- Phase 1 (9) + Phase 2 (79) 통과 유지 — 총 121

## Step 6: 📐 Architecture Compliance

- ✅ 레이어 경계: MaestroCore 단독 빌드 (앱 의존성 없음)
- ✅ Swift 6 Strict Concurrency: 모든 신규 타입 `Sendable`, `@unchecked Sendable` 은 `TailState` 1건만 (NSLock 직렬화 검증됨)
- ✅ Non-Goals: PTY 없음, 네이티브 파일시스템만

---

## 놓치지 않은 Must-fix 요약

**총 13건 식별 → 13건 전부 반영** (중복 1건 포함 실질 12건):

- 보안: 파일 권한, OOM 방어, Keychain 속성
- 내구성: fsync, truncation, error path cancel
- 성능: handle caching, chunked read, buffer cap
- 테스트: malformed/partial/rename/delete/concurrent/size-limit

---

## Open Items for Later Phases

1. **디렉토리 레벨 watcher** (DirectoryWatcher) — Phase 11 InboxWatcher 에서 필요. 현재 FileWatcher 는 단일 파일만.
2. **Multi-process fcntl lock** — 현재 단일 프로세스 전제. 앱 + CLI 동시 실행 시 envelope 손상 가능.
3. **Dir fsync for crash safety** — FileStore rename 후 parent dir fsync. 크래시 복구 시나리오 실제 발견 시 추가.
4. **Data-protection keychain** — Xcode 프로젝트 래핑 (Phase 21) 시 entitlement 도입으로 업그레이드.
5. **JSON depth limit** — 악성 nested array 로 스택 오버플로 가능. Phase 11 router 에서 envelope 디코딩 전 사전 스캔 고려.

---

## 완료 기준

- [x] Phase 3 Task 3.7~3.14 전부 완료 (3.14 mock 은 실제 mock 대신 tempDir 방식으로 대체)
- [x] 121/121 테스트 통과
- [x] /team 4명 병렬 리뷰 + **must-fix 13건 전원 반영**
- [x] swiftlint --strict: 0 violations
- [x] 리뷰 리포트 저장 (이 파일)
- [x] Phase 3 완료 커밋 + phase-3-end 태그

**다음**: Phase 4 — AgentAdapter 프로토콜 + CLI 감지
