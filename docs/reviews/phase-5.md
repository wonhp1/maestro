# Phase 5 Review Report — 로깅/옵저버빌리티 (OSLog + 진단)

**Date**: 2026-04-25
**Phase**: 5 / 23
**Status**: ✅ Complete
**Commits**: phase-5-start → phase-5-end

---

## Deliverables

`Sources/MaestroCore/`:

- `LogCategory.swift` — 10개 카테고리 (adapter / persistence / **routing** / **dispatch** / orchestration / process / **network** / **security** / ui / general)
- `MaestroLogger.swift` — `os.Logger` wrapper, **autoclosure (lazy)** + .private 기본 + StaticString-only `publicInfo`
- `MaestroSignposter.swift` — `OSSignposter` wrapper, async/sync `interval` scope + manual begin/end + event
- `GlobalErrorHandler.swift` — NSException → OSLog (chain Sparkle 호환), Swift error log helper
- `DiagnosticsBundle.swift` — actor, `/usr/bin/zip` via `ProcessExecuting` (preflight + dedupe + symlink-safe + 0700 staging)

`Sources/MaestroCore/ProcessExecuting.swift` 확장:

- `currentDirectoryURL: URL?` 매개변수 — Phase 7+ 어댑터의 cwd 지정 + DiagnosticsBundle zip 실행에 사용

**Tests**: 208/208 통과 (Phase 4 의 183 → +25)

- LogCategoryTests (2)
- MaestroLoggerTests (4) — subsystem/category 매핑, 모든 레벨 호출, Sendable across tasks
- MaestroSignposterTests (8) — make ID / begin-end / event / async + sync scope / error propagation / **nested intervals** / custom subsystem
- GlobalErrorHandlerTests (3) — install 멱등 / **uninstall restores previous handler** (Sparkle chain) / log 비throw
- DiagnosticsBundleTests (8) — 기본 zip / missing path 무시 / **missingZipExecutable** / **outputInsideSource** / **dedupe** / **실제 unzip 으로 contents 검증** / manifest roundtrip

---

## Step 2: 👥 /team Multi-Agent Review (4명 병렬)

### Architecture Reviewer — **Must-fix 2건, 모두 반영**

1. ❌→✅ `GlobalErrorHandler.uninstall()` 가 Sparkle chain 깨뜨림 → **doc 강화** (테스트 전용 명시) + 운영 호출 금지 안내
2. ❌→✅ `LogCategory` 부족 → **`.routing`, `.dispatch`, `.network`, `.security` 4 케이스 추가** (Phase 11/13/21 미리 분리)

추가 (SHOULD-FIX 적용):

- ✅ `DiagnosticsBundle.create` 에 `missingZipExecutable` preflight 추가 (Arch #5)
- ✅ 중복 lastPathComponent 처리 — index 접두사 (Arch #6)
- ✅ `ProcessExecuting` concrete impl 의 default param 제거 (Arch #8)
- ✅ Logger 메시지 비-로컬라이즈 의도 doc 명시 (Arch #7)

### Security Reviewer — **Must-fix 2건, 모두 반영**

1. ❌→✅ `DiagnosticsBundle` symlink 추적 + 중복 component 충돌 → resolveSymlinksInPath 비교 + index dedupe
2. ❌→✅ `outputZipURL` 이 source 내부면 zip 자기 출력 재귀 → `.outputInsideSource` throws

추가:

- ✅ `publicInfo`/`publicError` → **`StaticString` 으로 컴파일 타임 차단** (Sec S1, 단 publicError 는 simplify 에서 제거)
- ✅ Staging 디렉토리 0700 권한 (Sec S3)

### Test Quality Reviewer — **Must-fix 3건, 모두 반영**

1. ❌→✅ ZIP 내용 미검증 → **`/usr/bin/unzip -l` + `unzip -p` 로 manifest + paths/\* 실제 검증**
2. ❌→✅ Copy 충돌 silent loss → dedupe 테스트 추가
3. ❌→✅ chain 테스트 → uninstall 후 sentinel 핸들러 복귀 확인

추가:

- ✅ 중첩 signposter intervals 테스트
- ✅ Logger 동시성 (10 task) 테스트

### Performance Reviewer — **Must-fix 2건, 모두 반영**

1. ❌→✅ Logger 가 String 으로 받아 lazy interpolation 손실 → **`@autoclosure @escaping` 으로 전환**
2. ❌→✅ os.Logger per-call 생성 비용 → **단순 init** (os.Logger 가 내부 캐시 → 별도 cache 불필요, /simplify 에서 재정리)

---

## Step 3: ✨ /simplify

- `MaestroLogger` 의 hand-rolled cache 제거 — Apple `os.Logger` 가 내부적으로 (subsystem, category) 캐시 (~15 lines + `nonisolated(unsafe)` 한 건 제거)
- `MaestroLogger.publicNotice` / `publicError` 제거 — 사용처 없음 (~6 lines)
- `GlobalErrorHandler.isInstalled` 제거 — 운영 분기 의미 없음 (~6 lines)
- `DiagnosticsBundle.makeStagingDirectory` 의 redundant `setAttributes` 제거 — APFS 가 createDirectory attributes 존중 (~5 lines)
- `LogCategory` 의 `Codable` 제거 — 직렬화 사용처 없음 (token)

총 ~32 lines + 1 unsafe escape hatch 제거. 기능 손실 없음.

기각:

- Signposter API 트리밍 (Phase 13 dispatch 추적에 필요)
- `GlobalErrorHandler.log` 인라인화 (`#fileID/#line` 캡처가 value-add)

## Step 4: 🧩 Integration Verification

- Release build 통과
- App spawn + kill smoke OK
- 208/208 테스트 통과 (실제 `/usr/bin/zip`, `/usr/bin/unzip` 사용)

## Step 5: 🔄 Regression Check

- Phase 1-4 통과 유지
- 합계 183 → 208 (+25)

## Step 6: 📐 Architecture Compliance

- ✅ 레이어 경계: 모든 신규 타입 `MaestroCore` 단독. Adapters 영향 없음.
- ✅ Swift 6 Strict Concurrency: `nonisolated(unsafe)` 1건 (`GlobalErrorHandler.installed/previousHandler` — NSLock 직렬화). `MaestroLogger` 의 cache `nonisolated(unsafe)` 는 simplify 에서 제거됨.
- ✅ Non-Goals: 클라우드 텔레메트리 없음, 외부 서버 송신 없음. 모두 로컬 OSLog/파일.
- ✅ ProcessExecuting 확장은 backward-compatible (extension default = nil).

---

## 놓치지 않은 Must-fix 요약

**총 9건 식별 → 9건 전부 반영** (보너스 SHOULD-FIX 6건 포함):

- **보안**: symlink resolve, dedupe, output-inside-source, 0700 staging, StaticString public API, missingZipExecutable preflight
- **성능**: autoclosure lazy interpolation, os.Logger cache 의존
- **API 안전**: Sparkle uninstall 경고, 카테고리 미리 분리 (.routing/.dispatch/.network/.security)
- **테스트**: 실제 unzip 으로 ZIP 내용 검증, dedupe 테스트, uninstall chain 검증, nested intervals

---

## Open Items for Later Phases

1. **Sparkle 통합 시 install 순서 강제** — Phase 21 부팅 코드에 `// Maestro 먼저 install, 그 후 Sparkle` 명시. README 업데이트.
2. **로그 redaction 레이어** — DiagnosticsBundle 이 sourcePaths 를 그대로 복사. Phase 11+ 에서 envelope 의 시크릿 필드 redact 옵션 추가.
3. **Diagnostics bundle 사이즈 cap** — 거대 envelope 누적 (~100MB+) 시 zip 시간 증가. Phase 19 설정에서 "최근 N일" 옵션 도입.
4. **OSSignposter ID 공유** — `event(_:id:)` 오버로드 — Phase 13 dispatch 추적 시 단일 ID 로 begin/event/end 묶기.
5. **MaestroSignposter API 트리밍** — Phase 7+ 에서 사용 패턴 확정 후 미사용 메서드 제거.

---

## 완료 기준

- [x] Phase 5 Task 5.1~5.7 완료 (Task 5.8 — print 교체 — Phase 1-4 에 print 부재로 N/A)
- [x] 208/208 테스트 통과
- [x] /team 4명 병렬 리뷰 + **must-fix 9건 전원 반영** (+ SHOULD-FIX 6건)
- [x] /simplify 검토 + 5건 적용
- [x] swiftlint --strict: 0 violations
- [x] App release build + spawn 정상
- [x] Phase 1-4 회귀 없음
- [x] 레이어 경계 준수 (Core 단독)
- [x] 리뷰 리포트 저장 (이 파일)
- [x] Phase 5 완료 커밋 + phase-5-end 태그

**다음**: Phase 6 — Process 래퍼 + Streaming 인프라 (Milestone 2 시작)
