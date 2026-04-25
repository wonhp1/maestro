# Phase 10 Review Report — 레지스트리 + 폴더 관리 UI

**Date**: 2026-04-25
**Phase**: 10 / 23
**Status**: ✅ Complete
**Commits**: phase-10-start → phase-10-end

---

## Deliverables

`Sources/MaestroCore/`:

- `Identifiers.swift` — `FolderTag` / `FolderID` 추가 (UUID 기반 stable identity)
- `FolderRegistration.swift` — Codable 모델, `validateDisplayName` (bidi/ZW/control 차단), `validatePath` (심볼릭 링크 해소 + 디렉토리 검증)
- `FolderRegistry.swift` — actor, `folders.json` 영속화 (FileStore 기반 0600 perms), CRUD, `events()` AsyncStream, `loadFromDisk` 시 invalid entry prune
- `FolderPicker.swift` — `FolderPicking` 프로토콜 + `StubFolderPicker` 테스트 actor
- `FolderViewModel.swift` — `@MainActor @Observable`, bootstrap/select/add/delete/rename/changeAdapter, errorMessage 통합

`Sources/Maestro/Folders/`:

- `NSOpenPanelFolderPicker.swift` — `FolderPicking` 의 NSOpenPanel 구현 (canChooseDirectories=true, canChooseFiles=false)
- `SidebarView.swift` — List + 폴더 행 + "+ 폴더 추가" 버튼 + contextMenu(삭제/설정) + .onDeleteCommand + 단일 alert 채널
- `FolderSettingsSheet.swift` — 표시 이름/어댑터 변경 폼

`Sources/Maestro/`:

- `ContentView.swift` — `NavigationSplitView { Sidebar / Detail }` + `AppEnvironment`(@Observable)
  - `withObservationTracking` 기반 selection 감시 (polling 제거)
  - 채팅 세션 준비 중 loading state

**Tests**: 410/410 통과 (3 skipped — aider 미설치) (Phase 9 의 364 → +46)

- `FolderRegistrationTests` (18) — validateDisplayName / validatePath 정상/심볼릭/문제 케이스 / Codable
- `FolderRegistryTests` (15) — CRUD / 이벤트 / 동시 add 직렬화 / 디스크 prune 검증 / 0600 perms / 재로드
- `FolderViewModelTests` (10) — bootstrap / picker happy/cancel/duplicate / delete selection 처리 / rename / changeAdapter / select touch
- `FolderPickerTests` (3) — Stub 동작 검증

---

## Step 2: 👥 /team Multi-Agent Review (4명 병렬)

### Architecture Reviewer — Must-fix 5건 (1건 반영, 4건 defer)

1. ❌→✅ **Polling watcher → withObservationTracking** — `AppEnvironment.startSelectionWatcher` 가 200ms polling. `@Observable` 상에서 `withObservationTracking { _ = vm.selectedFolderID } onChange:` 패턴으로 교체 — 0 latency + idle 시 0 CPU. 동시에 UX-2 (selection latency) 도 해결.
2. ⏭️ Defer — **ChatSessionStore 추출** (Phase 12 explicit scope) — 현재 `AppEnvironment.activeChatViewModel` 단일. Phase 12 의 다중 세션 캐싱 시 promote.
3. ⏭️ Defer — **AppEnvironment DI seam** (Phase 12) — 현재 `bootstrap` 이 paths/picker/adapter 하드코딩. Phase 11+ 통합 테스트 시 init 주입 추가.
4. ⏭️ Defer — **`nonisolated(unsafe) var observationTask` 정리** — 현재 `FolderViewModel.deinit` 이 cancel 하기 위해 사용. Swift 6 `Box` actor 패턴은 broader concurrency cleanup 시점.
5. ⏭️ Defer — **FolderRegistry → AgentID derivation** — Phase 11 EnvelopeRouter 가 inbox 디렉토리 키 결정 시점에 통합.

### Security Reviewer — Must-fix 4건 (3건 반영, 1건 TODO 추가)

1. ❌→✅ **심볼릭 링크 traversal (HIGH)** — `validatePath` 가 `standardizedFileURL` 만 호출 — symlink 미해소. NSOpenPanel 이 `~/notes -> /etc` 반환 시 Aider `--yes-always` (Phase 9) 와 결합한 cwd escape RCE. **`resolvingSymlinksInPath` 추가 + resolved URL 반환 + 호출자가 resolved 저장**. add 시 dedupe 도 resolved 기준.
2. ❌→✅ **folders.json untrusted load (HIGH)** — `loadFromDisk` 가 디코드된 folders 를 무검증 사용. 누군가가 `/etc` path + bidi displayName 주입 가능. **모든 entry 에 `validateDisplayName` + `validatePath` 재적용 + 통과 못한 항목 prune + 디스크 cleanup**. 손상된 항목은 `invalidEntries` 에 보존 → UI surface 가능.
3. ❌→✅ **bidi/zero-width spoofing (MEDIUM)** — `validateDisplayName` 이 `.controlCharacters` 만 체크 — U+202A-E, U+2066-9, U+200B-D, U+FEFF 통과. Trojan Source 스타일 알림 spoofing 가능. **별도 `spoofingCharacters` CharacterSet 추가**.
4. ⏭️ Defer (TODO) — **TOCTOU between registration and Phase 11 spawn** — validatePath 시점과 cwd spawn 시점 사이 swap 가능. Phase 11 EnvelopeRouter spawn site 에 device+inode 비교 코멘트.

### UX Reviewer — Must-fix 3 HIGH 반영 + 7 MEDIUM/5 LOW defer

1. ❌→✅ **Alert 충돌 (HIGH)** — `pendingDeletion` + `errorMessage` 두 alert 가 같은 view 에. SwiftUI 가 동시 발생 시 두 번째 silently drop. **`SidebarAlert` enum 단일 채널화** + `.onChange(of: errorMessage)` 으로 errorMessage → alert 라우팅.
2. ❌→✅ **Selection latency (HIGH)** — 200ms polling 이 click-to-chat lag 유발. `withObservationTracking` 으로 즉시 반응 + ChatViewModel 생성 중 "채팅 세션 준비 중…" loading state 추가.
3. ❌→✅ **키보드 delete affordance (HIGH)** — context menu 만 → `.onDeleteCommand` 추가, ⌫ 가 선택 폴더 삭제 confirm 트리거.
4. ⏭️ Defer (Phase 19 settings UI) — ⌘, 발견성, Reveal in Finder, 어댑터 displayName, VoiceOver 라벨, 추가 성공 토스트, duplicate 복구 hint, 상대시간 자동 갱신, Korean 톤 통일

### Test Quality Reviewer — Blocker 4건 + High 6건 (5건 반영)

1. ❌→✅ **B1: 손상 JSON / 누락 path 테스트** — `testLoadFromDiskPrunesEntriesWithMissingPath` (디렉토리 삭제 후 reload prune)
2. ❌→✅ **B2: 디스크 신뢰 테스트** — `testLoadFromDiskPrunesEntriesWithBidiSpoofedName` (직접 evil JSON 주입)
3. ❌→✅ **B3: update no-op** — `testUpdateWithBothNilParamsIsNoOpButPersists` (현재 동작 lock-in)
4. ⏭️ Defer — **B4: Korean string assertion brittleness** — humanReadable 의 Korean copy 검증. 현 단계에서 typed error API 분리는 over-engineering. Phase 22 (i18n) 시점에 String Catalog + key-based 어설션으로 교체.
5. ❌→✅ **H1: changeAdapter** — `testChangeAdapterUpdatesFolder`
6. ❌→✅ **H3: 동시 add 직렬화** — `testConcurrentAddSerializedByActor` (10 concurrent → all succeed + 디스크 일관성)
7. ⏭️ Defer — **H2/H4/H5: events lifecycle / picker 동시 호출 / touch unknown** — 현 커버리지로 충분, Phase 11 router 테스트 통합 시 자연 확장.

---

## Step 3: ✨ /simplify

이번 phase 는 must-fix 양이 많아 simplify 통합. 적용된 단순화:

- `withObservationTracking` 도입으로 polling Task + `nonisolated(unsafe)` 1개 제거
- 단일 alert enum 으로 두 alert modifier → 하나
- `validatePath` 가 `URL` 반환 → 호출자가 `standardizedPath` 다시 계산할 필요 X

## Step 4: 🧩 Integration Verification

- Release build 통과
- App spawn smoke OK
- 410/410 테스트 통과 (3 skipped, aider 미설치 정상)
- Quality Gate:
  - 3+ 폴더 동시 등록 — `testConcurrentAddSerializedByActor` 가 10개 검증
  - 폴더 클릭 → 어댑터 채팅 전환 — `withObservationTracking` 이벤트 후 `makeChatViewModel`
  - 앱 재시작 → 폴더 목록 유지 — `testRegistryRehydratesAcrossInstances`

## Step 5: 🔄 Regression Check

- Phase 1-9 통과 유지 (364 → 410, +46)
- ClaudeAdapter / AiderAdapter 미영향
- 기존 ChatView 는 detail pane 에 정상 mount

## Step 6: 📐 Architecture Compliance

- ✅ `MaestroCore` 가 SwiftUI/AppKit 미의존 (NSOpenPanelFolderPicker 만 `Sources/Maestro/`)
- ✅ `FolderPicking` 프로토콜 분리로 ViewModel 테스트 가능 (StubFolderPicker)
- ✅ Swift 6 Strict Concurrency: actor / @MainActor / Sendable 일관
- ✅ FileStore 0600 perms / 0700 디렉토리 perms 유지
- ✅ Phantom-typed FolderID — AdapterID/SessionID 등과 mix-up 컴파일 차단

---

## 식별된 Must-fix 요약

**총 16건 식별 (Arch 5 + Sec 4 + UX 3 HIGH + Test 4 + 1)** → **8건 반영, 8건 defer (대부분 Phase 11/12 explicit scope 또는 Phase 19/22 i18n)**

핵심 반영:

- **보안 3건**: 심볼릭 링크 해소, 디스크 untrusted load 재검증, bidi/ZW spoofing 차단
- **UX 3건**: 단일 alert 채널, observation 기반 selection (polling 제거), 키보드 delete
- **테스트 5건**: 손상 path / bidi inject / 동시 add / changeAdapter / update no-op
- **아키텍처 1건**: polling Task → withObservationTracking

---

## Open Items for Later Phases

1. **ChatSessionStore 추출** (Phase 12) — multi-session 캐싱 시점.
2. **AppEnvironment DI seam** (Phase 12) — Phase 11 router 통합 테스트 시점에 init 주입.
3. **TOCTOU 방어** (Phase 11) — EnvelopeRouter spawn site 에서 device+inode 검증.
4. **FolderID → AgentID 매핑** (Phase 11) — inbox 디렉토리 키 일치 결정.
5. **AdapterID displayName** (Phase 19) — 어댑터 메타 표준화. 현재 raw id ("claude") 노출.
6. **VoiceOver / a11y 라벨** (Phase 19/20) — 사이드바 row + custom button.
7. **⌘, Settings scene** (Phase 19) — 현재 hidden button 이 sheet 직접 trigger. 표준 macOS Settings scene 으로 격상.
8. **Reveal in Finder** (Phase 19) — 설정 시트 + 컨텍스트 메뉴.
9. **Korean i18n** (Phase 22) — String Catalog 도입 + 톤 통일 + humanReadable 의 typed error 분리.
10. **invalidEntries UI surface** — `FolderRegistry.invalidEntries` 가 prune 된 항목 보존하지만 현재 UI 가 표시 안 함. Phase 12 inspector 패널 후보.
11. **`nonisolated(unsafe) var observationTask`** 정리 — broader Swift 6 concurrency cleanup pass.
12. **lastUsedAt write amplification** — 매 select 마다 `folders.json` 전체 rewrite. 사용 빈도 늘면 batched write 또는 별도 ephemeral 파일.

---

## 완료 기준

- [x] Phase 10 Task 10.1~10.10 완료
- [x] 410/410 테스트 통과 (3 skipped, aider 미설치 정상)
- [x] /team 4명 병렬 리뷰 + must-fix 8건 반영, 8건 defer 결정 documented
- [x] swiftlint --strict: 0 violations
- [x] Release build + spawn 정상
- [x] Phase 1-9 회귀 없음
- [x] Quality Gate 3개 모두 자동 검증 (테스트로)
- [x] 리뷰 리포트 저장 (이 파일)
- [ ] phase-10-end 태그 (다음 단계)

**Milestone 3 (BYOA 증명) 완료 + Milestone 4 (컨트롤 타워 3주) 진입**: Phase 10 완료. 사용자가 폴더를 등록하고 폴더별 어댑터를 지정 가능 — Maestro 의 핵심 UX 기반 완성.

**다음**: Phase 11 — 메시지 봉투 + 라우팅 (inbox/outbox/threads, EnvelopeRouter, 5일 예상)
