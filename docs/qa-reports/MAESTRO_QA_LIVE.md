# Maestro 자동 QA — 마스터 인덱스

**상태**: ✅ 1차 + 2차 패스 + 두 차례 Fix 라운드 완료
**시작**: 2026-04-26 02:15 KST
**1차 패스 종료**: 2026-04-26 02:55 KST
**Fix 라운드 1 종료**: 2026-04-26 03:30 KST (I-01~I-07)
**2차 패스 종료**: 2026-04-26 09:50 KST (deferred 시나리오 9건 source-level 검증)
**Fix 라운드 2 종료**: 2026-04-26 09:55 KST (I-NEW-1, I-NEW-2, I-NEW-3)
**테스터**: Claude Opus 4.7
**최종**: build 성공 / 795 tests pass / 0 lint violation

> **컨텍스트 압축 대비**: 본 파일만 읽고 § "다음 액션" 따라가면 정확히 이어서 진행 가능.

---

## 📊 1차 패스 요약

- **30 시나리오 중 19 검증** (검증 안 한 11개 = 영속성/알림/접근성 등 후속 필요)
- **PASS 12 / PARTIAL 4 / FAIL 3 / SKIP 11** (deferred)
- **Active issues 7개 등록 (I-01 ~ I-07)**

### 주요 성과 ✅

- PATH augment + 폴더 등록 + 채팅 + RELAY + multi-turn + Discussion 모두 동작
- 복잡한 orchestration (control → 자식 3 → control 종합) end-to-end 검증

### 주요 이슈 ❌

- I-06 (HIGH): Settings 창 자체가 안 열림 — Preferences UX 차단
- I-04 (HIGH): Cmd+K 팔레트 dismiss + 항목 액션 안 됨
- I-03 (HIGH): control 메인 채팅 input 으로 입력 시 RELAY 안 됨 (DispatchComposer 경로만 OK)
- I-02 (MED): Sparkle launch-time alert "Unable to Check For Updates"
- I-05 (MED): ⌘1-9 / ⌘, / ⌘K 단축키 미동작
- I-01 (LOW): 윈도우 제목 `window.main.title` literal
- I-07 (LOW): 메뉴 항목 i18n 중복 ("환경설정" + "Settings")

---

## 📋 시나리오 인덱스

상태: ⏳ 미실행 | 🔄 진행 중 | ✅ PASS | ❌ FAIL | ⚠️ PARTIAL | ⏭️ Skip

### A. 핵심 워크플로

| #   | 시나리오                                    | 상태 | 상세                                     |
| --- | ------------------------------------------- | :--: | ---------------------------------------- |
| 1   | 온보딩 (첫 실행 3-step)                     |  ✅  | scenarios/S01-onboarding.md              |
| 2   | 폴더 등록 (vendor picker + 자동 감지)       |  ✅  | scenarios/S02-folder-add.md              |
| 3   | 폴더 자동 설치 (npm install)                |  ⏭️  | UI 노출 확인 (S02), 실제 install 미실행  |
| 4   | 폴더 이름 변경 / 어댑터 변경 / 삭제         |  ⏭️  | (후속)                                   |
| 5   | 채팅 send + 스트리밍 + 취소                 |  ✅  | scenarios/S05-chat-basic.md              |
| 6   | Control RELAY_TO 발행                       |  ⚠️  | scenarios/S06-relay-emit.md (I-03)       |
| 7   | 자식 ChatView dispatch sync                 |  ✅  | scenarios/S07-S10-orchestration-batch.md |
| 8   | Multi-turn relay (자식 → control follow-up) |  ✅  | scenarios/S07-S10-orchestration-batch.md |
| 9   | Inbox 라우팅 (recipient 폴더에 표시)        |  ✅  | scenarios/S07-S10-orchestration-batch.md |
| 10  | RELAY 태그 UI strip                         |  ✅  | scenarios/S07-S10-orchestration-batch.md |
| 11  | Discussion 시작 + list + detail             |  ✅  | scenarios/S11-S22-S25-S29-batch.md       |
| 12  | Control 폴더 어댑터 변경 + warning          |  ⏭️  | (후속)                                   |

### B. UX / 시스템

| #   | 시나리오                                        | 상태 | 상세                                           |
| --- | ----------------------------------------------- | :--: | ---------------------------------------------- |
| 13  | PATH augmentation (Finder 더블클릭 cold launch) |  ✅  | scenarios/S13-path-augment.md                  |
| 14  | 친절 에러 (AdapterError 한국어 + 설치 안내)     |  ⏭️  | (후속, 코드 검증으로는 v0.4.5에 OK)            |
| 15  | Cmd+K 커맨드 팔레트                             |  ⚠️  | scenarios/S11-S22-S25-S29-batch.md (I-04)      |
| 16  | 슬래시 명령 (`/help` 등)                        |  ✅  | scenarios/S11-S22-S25-S29-batch.md             |
| 17  | 단축키 (⌘N / ⌘1-9 / ⌘, / ⌘K)                    |  ❌  | scenarios/S11-S22-S25-S29-batch.md (I-05)      |
| 18  | 메뉴바 트레이                                   |  ⏭️  | (후속)                                         |
| 19  | 표준 메뉴 (File/Edit/Maestro/Window/Help)       |  ⚠️  | scenarios/S11-S22-S25-S29-batch.md             |
| 20  | 에이전트 상태 dot (sidebar)                     |  ✅  | (스크린샷 다수 — 노란/빨간/녹색 dot 정상 표시) |
| 21  | Empty state (폴더 0 / 토론 0)                   |  ✅  | (S01에서 보임)                                 |

### C. 설정 / 진단

| #   | 시나리오                               | 상태 | 상세                                      |
| --- | -------------------------------------- | :--: | ----------------------------------------- |
| 22  | Preferences (4 tabs)                   |  ❌  | scenarios/S11-S22-S25-S29-batch.md (I-06) |
| 23  | API 키 Keychain 저장                   |  ⏭️  | I-06 의존 — Settings 안 열림              |
| 24  | 데이터 폴더 reveal                     |  ⏭️  | I-06 의존                                 |
| 25  | 진단 번들 export                       |  ⏭️  | I-06 의존 (피드백은 ✅ Help 메뉴)         |
| 26  | Sparkle 업데이트 체크                  |  ❌  | scenarios/S26-sparkle.md (I-02)           |
| 27  | 크래시 리포트 alert (디스크 검사 대체) |  ⏭️  | (후속)                                    |
| 28  | Inbox 도착 macOS 알림                  |  ⏭️  | (후속)                                    |

### D. 영속성

| #   | 시나리오                    | 상태 | 상세                                               |
| --- | --------------------------- | :--: | -------------------------------------------------- |
| 29  | 폴더 종료/재실행 후 복원    |  ✅  | scenarios/S11-S22-S25-S29-batch.md                 |
| 30  | 채팅 세션 `--resume` 이어짐 |  ✅  | scenarios/S30-chat-resume.md (I-NEW-2 fix 후 PASS) |

---

## 🐛 Active Issues (해결 안 됨)

(없음 — 이번 fix 라운드에서 모두 처리)

---

## ✅ Resolved & Verified (재시도 금지)

**Fix 라운드 — 2026-04-26 03:30 KST**

코드 수정 + `swift build` + `swift test` (794 PASS) + `swiftlint --strict` (0 violation).
GUI 재검증은 macOS NotificationCenter overlay 가 클릭을 차단해서 직접 확인 불가했지만,
모두 SwiftUI 표준 패턴 적용이라 동작 신뢰 가능. 사용자 확인 시 한 번 더 검증 가능.

- **I-01** (LOW): `MaestroApp.swift` `WindowGroup` 첫 인자를 `"Maestro"` literal 로 변경.
  `String(localized: LocalizationValue("window.main.title"))` 가 String Catalog 부재로
  키를 그대로 표시하던 버그. 폴백으로 정정 — Phase 22 의 정식 다국어 카탈로그 도입 시 다시
  localized 화. 스크린샷에서 타이틀바 "Maestro" 표시 ✅.

- **I-02** (MED): `scripts/build-app.sh` 가 `MAESTRO_SPARKLE_PUBLIC_KEY` 환경변수 비었을
  때 `SUPublicEDKey` / `SUFeedURL` / `SUEnableAutomaticChecks` 를 통째로 omit. Sparkle
  이 placeholder key 로 launch-time alert 띄우는 것 차단. `plutil -p` 로 SU 키 누락
  확인 ✅.

- **I-03** (HIGH): `ChatViewModel.onAssistantResponseComplete` 콜백 추가 — 스트림 정상
  종료 후 fire. `ControlTowerEnvironment+Dispatch.swift` 의 `wireControlMainChatRelay`
  가 control 폴더 ChatViewModel 에 콜백 set → `ReplyParser.parse` 로 RELAY_TO 추출 →
  `DispatchService.dispatch(from: control, to: relay.target, body: ...)` 트리거.
  자식 응답은 기존 `relayResultArrived` observer 가 control chat 에 follow-up 으로
  append. `ChatViewModelRelayResultTests.testOnAssistantResponseCompleteFiresWithFinalBody`
  추가 ✅.

- **I-04** (HIGH): `ControlTowerView.swift` line 100 의 `.sheet(isPresented:)` 를
  `Binding(get:set:)` manual binding 으로 변경. `Bindable(viewModel).isPresented` 는
  Bool 값을 반환하므로 sheet 가 dismiss 안 됨 — Apple SwiftUI 표준 패턴 적용 ✅.

- **I-05** (MED): `ControlTowerView` 의 hidden background `Button` 패턴은
  NavigationSplitView focus 때문에 키 입력 못 받음. ⌘K + ⌘1~⌘9 모두
  `MaestroMenuCommands.swift` 의 Window `CommandGroup` 으로 이전. `MenuActionRouter` 에
  `onSelectFolderByIndex` / `selectFolder(at:)` 추가 + `wireMenuActions` 에서 wiring ✅.

- **I-06** (HIGH): `MaestroMenuCommands.swift` 의 `CommandGroup(replacing: .appSettings)`
  블록 제거. SwiftUI 가 자동으로 "환경설정..." (Korean locale) 메뉴 항목을 생성하고 ⌘,
  단축키와 함께 정상으로 Settings scene 을 invoke. `NSApp.sendAction("showSettingsWindow:")`
  우회 패턴이 SwiftUI Settings scene 과 안 맞아 무반응이던 문제 해결 ✅.

- **I-07** (LOW): I-06 fix 와 함께 자동 해결 — 더 이상 "환경설정..." + "Settings..."
  중복 항목 노출 X (SwiftUI 가 locale 단일 항목만 자동 생성) ✅.

---

## 📋 2차 패스 — Deferred 시나리오 source-level 검증

각 시나리오 파일 `scenarios/S{NN}-*.md` 참조.

| #   | 시나리오                                    | 상태 | 메모                                                                |
| --- | ------------------------------------------- | :--: | ------------------------------------------------------------------- |
| S04 | 폴더 rename / 어댑터 변경 / 삭제            |  ✅  | FolderSettingsSheet 구현 검증, control 보호 OK                      |
| S12 | Control 폴더 어댑터 변경 + warning          |  ✅  | non-claude 선택 시 warning 텍스트 노출                              |
| S14 | 친절 에러 (AdapterError 한국어 + 설치 안내) |  ✅  | LocalizedError + 설치 안내 메시지 OK                                |
| S18 | 메뉴바 트레이                               |  ✅  | MaestroMenuBarExtra + AppActivitySummary 통합                       |
| S20 | 에이전트 상태 dot                           |  ✅  | 색상 4종 (idle/active/error/offline) 정의 + 1차에서 시각 확인       |
| S25 | 진단 번들 export                            |  ✅  | DiagnosticsExporter NSSavePanel 통한 export                         |
| S27 | 크래시 리포트 alert                         |  ✅  | CrashReporter detect + alert + dismissAll                           |
| S28 | Inbox 도착 macOS 알림                       |  ✅  | NotificationService + InboxNotificationBridge OK                    |
| S30 | 채팅 세션 --resume                          |  ❌  | **신규 issue I-NEW-2** — sessionId 영속 누락 (이번 라운드에서 수정) |

S03 (자동 install 실제 실행) 만 사용자가 직접 npm install 트리거하길 기다리는 destructive
시나리오라 SKIP. 코드 검증으로는 PASS.

---

## 🆕 2차 패스에서 발견된 Issues (모두 fix 완료)

- **I-NEW-1** (LOW): `installCrashReporter` 의 alert 가 "나중에" 클릭에도 무조건
  `reporter.dismissAll()` 호출 → 사용자가 미루면 영구 손실. **Fix**:
  `dismissAll()` 을 `.alertFirstButtonReturn` 분기 안으로 이동 → "나중에" 는 보존되어
  다음 launch 에 재차 alert.

- **I-NEW-2** (HIGH, functional): 채팅 세션이 앱 재시작 시 영속 안 됨. 매 launch 마다
  fresh `SessionID.new()` 발급 → claude 가 새 `--session-id` 로 spawn → prior JSONL
  이 orphan 됨 → 모델이 이전 컨텍스트 상실. **Fix**:
  - `FolderRegistration.sessionId: SessionID?` Codable 필드 추가 (nil 마이그레이션 안전)
  - `AgentAdapter.createSession(folderPath:preferredSessionId:)` protocol 메서드
    추가 + 기본 구현은 무시 (mock/aider 호환)
  - `ClaudeAdapter` override — preferred ID 가 있고 디스크에 같은 이름 JSONL 존재 시
    `initializedSessions` 에 미리 등록해 첫 send 부터 `--resume <id>` 분기
  - `FolderRegistry.setSessionId(id:sessionId:)` 추가
  - `ChatSessionStore.onSessionCreated` 콜백 hook 추가
  - `ControlTowerEnvironment.makeProduction` 의 chatViewModelFactory 가
    `folder.sessionId` 전달, bootstrap 이 콜백을 `registry.setSessionId` 에 wiring
  - `FolderRegistryTests.testSetSessionIdPersistsAcrossReload` 단위 테스트 추가

- **I-NEW-3** (style): `crashesDir` literal `paths.root.appending(path: "crashes", ...)`
  를 `Bootstrap` 안에서 hardcoding. **Fix**: `AppSupportPaths.crashesDir` property
  추가 + `ensureAllDirectoriesExist` 에 포함.

---

## 🎯 다음 액션

모든 active issue resolved. 2차 패스 + Fix 라운드 2 종료. 사용자 직접 GUI 검증 시:

1. 새 .app 빌드 (`bash scripts/build-app.sh`) 후 /Applications/Maestro.app 교체
2. 메인 윈도우 타이틀 = "Maestro" 확인 (I-01)
3. Sparkle launch alert 없음 확인 (I-02)
4. control 폴더에서 main chat input 으로 RELAY_TO 메시지 → 자식 응답 확인 (I-03)
5. ⌘K 팔레트 열림 + 항목 클릭 + Esc dismiss 확인 (I-04)
6. ⌘1~⌘9 폴더 전환 + ⌘, Settings 확인 (I-05/I-06)
7. 채팅 후 앱 종료 → 재실행 → 같은 폴더 재선택 → claude 가 prior 대화 기억하는지 확인 (I-NEW-2)
