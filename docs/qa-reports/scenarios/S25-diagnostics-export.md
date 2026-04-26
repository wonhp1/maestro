# S25 — 진단 번들 export

**상태**: ✅ PASS (코드 레벨)
**검증 방식**: Source review (이전 GUI 세션은 Settings 창 미오픈으로 skip — issue I-06)
**대상**: `Sources/Maestro/Settings/DiagnosticsExporter.swift`, `Sources/MaestroCore/DiagnosticsBundle.swift`

---

## DiagnosticsExporter (UI wrapper)

`DiagnosticsExporter.swift:8-65` — `@MainActor enum` (정적 함수만).

### `exportInteractive(paths:)` (`:9-34`)

1. `NSSavePanel` 표시:
   - title: "진단 번들 저장 위치"
   - message: "Maestro 진단 정보를 ZIP 으로 내보냅니다 (로그 / 설정 / 폴더 메타)."
   - 기본 파일명: `Maestro-Diagnostics-{YYYYMMDD}.zip` (`:36-42`)
   - allowedContentTypes `[.zip]`
2. 사용자 OK 시 `bundle.create(outputZipURL:sourcePaths:)` 호출
3. sourcePaths (filter 로 존재 파일만):
   - `paths.preferencesFile`
   - `paths.foldersFile`
   - `paths.sessionsDir`
   - `paths.threadsDir`
   - `paths.logsDir`
4. 성공 → `showSuccessAlert(at:)` (`:44-55`) — "확인" + "Finder 에서 보기" 버튼
5. 실패 → `showFailureAlert(error:)` (`:57-64`) — `error.localizedDescription` 표시

## DiagnosticsBundle (`DiagnosticsBundle.swift`)

`actor DiagnosticsBundle` (`:20-`) — 외부 `ProcessExecuting` + `/usr/bin/zip` 사용 (`:54-61`).

### `Manifest` 구조 (`:21-45`)

- `appName`, `appVersion`, `bundleIdentifier`, `macOSVersionString`
- `createdAt: Date`
- `includedRelativePaths: [String]` (예: `paths/registry/registry.json`)

### `create(outputZipURL:sourcePaths:now:)` (`:70-`)

1. `/usr/bin/zip` executable 사전 확인 → `DiagnosticsBundleError.missingZipExecutable` (`:75-78`)
2. staging 디렉토리 생성
3. 각 source path 복사 → `paths/<name>/...` 구조
4. `manifest.json` 생성 (앱 버전 + OS 버전 + 포함 경로 목록)
5. ZIP 생성

### 보안 명시 (`:13-16`)

> 시크릿(Keychain)은 **포함하지 않음** — 호출자가 sourcePaths 선택 시 신중히 결정.
> ZIP 자체는 암호화하지 않음.

---

## Verdict

- ✅ NSSavePanel 인터랙티브 저장 위치 선택
- ✅ ZIP 번들 (manifest + preferences + folders.json + sessions/ + threads/ + logs)
- ✅ 앱 버전 / bundleId / macOS 버전 manifest 기록
- ✅ 성공/실패 alert + "Finder 에서 보기" UX
- ⚠️ 런타임 검증 차단됨: 진입점인 Settings → Advanced 탭이 issue I-06 (Settings 창 안 열림) 에 막혀 있음. 코드 자체는 완비.
