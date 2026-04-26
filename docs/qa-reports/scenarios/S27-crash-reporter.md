# S27 — 크래시 리포터

**상태**: ✅ PASS (코드 레벨)
**검증 방식**: Source review
**대상**: `Sources/MaestroCore/CrashReporter.swift`, `Sources/Maestro/ControlTower/ControlTowerEnvironment+Bootstrap.swift`

---

## 글로벌 핸들러 설치

`CrashReporter.install()` (`CrashReporter.swift:125-127`) → `installGlobalHandlers()` (`:132-164`).

- `lock` + `installed` 플래그 (`:129-130, 135-136`) — 중복 설치 차단
- `NSSetUncaughtExceptionHandler` 등록 (`:144-150`) → `writeCrashRecord(kind: "exception", ...)`
- 시그널 핸들러 등록 (`:152-163`): `SIGABRT`, `SIGILL`, `SIGSEGV`, `SIGFPE`, `SIGBUS`, `SIGPIPE`
  - 핸들러는 record 작성 후 `signal(sig, SIG_DFL); raise(sig)` — 정상 OS 종료 흐름 유지

`writeCrashRecord` (`:172-191`) — async-signal-unsafe 인지 (`:173-175` 주석에 명시), atomic write 시도. 트레이드오프 합리적.

## 디스크 위치

`installCrashReporter(paths:)` (`Bootstrap.swift:9-15`):

```swift
let crashDir = paths.root.appending(path: "crashes", directoryHint: .isDirectory)
let reporter = CrashReporter(directory: crashDir)
reporter.install()
showPendingCrashAlertIfNeeded(reporter: reporter)
```

→ 실제 경로: `~/Library/Application Support/Maestro/crashes/crash-<UUID>.json`

⚠️ 이 경로는 `AppSupportPaths` 의 명명된 디렉토리 (`sessionsDir`, `logsDir` 등) 가 아닌 ad-hoc append — `paths.swift` 에 `crashesDir` 상수 미정의. CLAUDE.md 의 "새 storage: add a path constant to lib/config.ts, never hardcode" 와 동일 컨벤션 위반.

## record 포맷 (`CrashReport`, `:4-32`)

JSON 필드: `id` (UUID), `occurredAt` (Date), `appVersion`, `kind` (`exception`|`signal`), `message`, `stackTrace: [String]`.
파일 perms 0600 (`CrashReporter.swift:77-80`) — 다른 로컬 사용자 차단.

## 다음 부팅 시 alert

부팅 시 `installCrashReporter()` 호출 직후 `showPendingCrashAlertIfNeeded(reporter:)` (`Bootstrap.swift:19-41`):

1. `loadPendingReports()` → `crashes/` 디렉토리 스캔, `.json` 파일들 디코드 (`CrashReporter.swift:85-102`)
2. 비어있으면 silent return
3. `NSAlert` (`Bootstrap.swift:28-34`):
   - **messageText**: `"이전 실행에서 \(reports.count) 건의 크래시가 감지됐어요"`
   - **informativeText**: `"진단 번들로 보내주시면 문제 파악에 큰 도움이 됩니다."`
   - 버튼: `"진단 번들 만들기"` / `"나중에"`
4. "진단 번들 만들기" 선택 시 `DiagnosticsExporter.exportInteractive(paths:)` 호출
5. **사용자 선택과 무관하게 `reporter.dismissAll()` 실행** (`Bootstrap.swift:39`) — 같은 alert 가 무한 재표시되지 않도록 한 의도

⚠️ `dismissAll()` 호출이 alert 응답과 무관 — "나중에" 를 눌러도 디스크에서 모든 report 가 삭제됨. 사용자가 진단 번들을 만들 의향이 있어도 다음 실행에서는 사라진 상태. 의도라면 "나중에" 라벨이 misleading.

## 보안 / 한계 (코드 주석에 명시)

- stack trace 만 — 사용자 데이터 X (`CrashReporter.swift:43-44`)
- 외부 자동 전송 X — 사용자 명시적 선택 후 진단 번들로만 노출
- signal handler 안에서 JSONEncoder 사용은 async-signal-unsafe — Phase 26+ PLCrashReporter 통합 예정 (`:47-49, 173-175`)

---

## Verdict

- ✅ NSException + 6개 signal 핸들러 설치, 중복 install 가드
- ✅ atomic write, 0600 perms, JSON 포맷 단순/안전
- ✅ 다음 부팅 시 한국어 alert + 진단 번들 export 경로
- ⚠️ `crashesDir` path 상수 미정의 (Bootstrap 에서 ad-hoc append)
- ⚠️ alert 응답과 무관하게 `dismissAll()` 실행 — "나중에" 의도와 불일치 가능 (issue 후보 I-NEW-1)
