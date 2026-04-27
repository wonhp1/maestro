# Implementation Plan: v0.7.0 — 슬래시 명령어 UX 완성 (TUI 방식)

**Status**: ⏳ Pending
**Started**: 2026-04-27
**Last Updated**: 2026-04-27
**Estimated Completion**: 2026-04-27 (당일, 약 6h)

---

**⚠️ CRITICAL INSTRUCTIONS**: After completing each phase:

1. ✅ Check off completed task checkboxes
2. 🧪 Run all quality gate validation commands
3. ⚠️ Verify ALL quality gate items pass
4. 📅 Update "Last Updated" date above
5. 📝 Document learnings in Notes section
6. ➡️ Only then proceed to next phase

⛔ **DO NOT skip quality gates or proceed with failing checks**

---

## 📋 Overview

### Feature Description

Phase 17 (`SlashCommandRegistry` + `SlashCommandWatcher` + 팔레트 노출) 가 plan 상 "complete" 지만 사용자 입장에서 **슬래시 명령을 못 쓰는 상태**.

- ✅ `/help` 직접 타이핑 후 Cmd+Enter → CLI 가 받아서 동작 (기능적으론 됨)
- ❌ `/` 타이핑 시 자동완성 popup 안 나옴
- ❌ Cmd+K 팔레트에서 슬래시 클릭해도 입력창에 prepopulate 안 됨 (Phase 17 review MED-2 가 Phase 18 로 defer 됐는데 picking 안 됨 → orphan)
- ❌ 인수 메타데이터 (`<topic>`) 가 메타에만 있고 사용자 UX 에 노출 안 됨

v0.7.0 은 **Claude TUI 와 동등한 인라인 슬래시 UX** 를 SwiftUI native (macOS 14+) 로 완성.

### Success Criteria

- [ ] `ChatComposer` / `DispatchComposer` 입력창에 `/` 또는 `/<query>` 타이핑 시 popover 자동 표시
- [ ] popover 안에 인수 힌트가 회색 텍스트로 시각적으로 표시 (예: `/review  PR-url`)
- [ ] 위/아래 화살표로 후보 선택, Enter 로 확정, Esc 로 취소
- [ ] 선택 시 입력창엔 명령만 들어감 (`/foo` 또는 인수 있는 명령은 `/foo `) — `<arg>` literal 텍스트 안 들어감
- [ ] Cmd+K 팔레트에서 슬래시 항목 클릭 시 동일하게 입력창에 `/foo` (또는 `/foo `) prepopulate
- [ ] 팔레트에 builtin / userFile / skill 별 아이콘 + 섹션 헤더
- [ ] 기존 입력 흐름 (Cmd+Enter 전송, Cmd+. 취소) 회귀 0
- [ ] 모든 기존 853+ 테스트 통과 + 신규 테스트 추가
- [ ] swiftlint 0 violation, swift build 0 warning (신규 코드)

### User Impact

- BYOA 일관성 — Claude TUI 익숙한 사용자가 Maestro 에서도 동일 흐름
- 신규 사용자 학습 곡선 ↓ — 명령 이름 외울 필요 X (popup 으로 발견)
- 팔레트 / inline 두 진입점 일관 — 어느 쪽이든 `/foo <arg>` 형태로 입력창 도달

---

## 🏗️ Architecture Decisions

| Decision                                                                                                      | Rationale                                                                                                       | Trade-offs                                                                                                                               |
| ------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `SlashSuggestionEngine` (pure logic, MaestroCore) 분리                                                        | TextEditor / TextField 양쪽에서 재사용. 테스트 가능 (UI 와 분리).                                               | 추가 파일 1개. UI 코드 ↓                                                                                                                 |
| FuzzyMatcher 재사용 (이미 `Sources/MaestroCore/FuzzyMatcher.swift`)                                           | 검증된 ranking. 외부 dependency 추가 X.                                                                         | 신규 점수 튜닝 필요 시 FuzzyMatcher 변경 (회귀 위험) — 사용 시 read-only                                                                 |
| `.popover(isPresented:)` overlay (TextEditor/TextField 위에 attach)                                           | SwiftUI 표준, 화면 위치 자동, accessibility 무료.                                                               | popover 가 TextEditor 키보드 focus 가져가지 않음 — `.onKeyPress` 가 입력창에 머물러야 (이게 macOS 14+ 표준 동작)                         |
| macOS 14+ `.onKeyPress(.upArrow/.downArrow/.return/.escape)`                                                  | NSEvent.addLocalMonitor 우회 불요 (Maestro target = macOS 14).                                                  | 13 미지원 — 현 plan 에서 무관                                                                                                            |
| 선택 시 입력창엔 명령만 insert (`/foo` 또는 인수 있으면 `/foo `) — `<arg>` literal 안 들어감                  | 실제 Claude TUI 와 동일 동작. SwiftUI TextEditor selection 한계 우회. 사용자가 자유롭게 인수 타이핑.            | 인수 placeholder 시각화는 popover 안에서만 (회색 보조 텍스트) — 입력창엔 hint 안 보임                                                    |
| ChatComposer / DispatchComposer 공통 popover 로직 → `SlashSuggestionsModifier` ViewModifier                   | 두 composer 의 popover 구현 중복 제거.                                                                          | ViewModifier 의 키 입력 routing — 두 composer 의 입력 위젯 type 다름 (TextEditor vs TextField) → modifier 가 binding 만 받고 각자 attach |
| 팔레트 wiring: `consumePendingSlashInsertion` 을 ChatComposer / DispatchComposer 의 `.task(id:)` 에서 polling | onAppear 한 번만 + 환경 변경 onChange — pendingSlashInsertion 은 set-and-clear 패턴이라 task(id:) 가 자연스러움 | environment 의 @Observable propagation 으로 자동 — polling 불요 (ControlTowerEnvironment 가 @Observable 이면 onChange 가능)              |

---

## 🗺️ Phase Breakdown

### Phase 1: Composer Wiring (Cmd+K 팔레트 → 입력창 prepopulate)

**Goal**: Cmd+K 에서 슬래시 항목 클릭 시 `ChatComposer` / `DispatchComposer` 의 입력창에 `/foo <arg>` 가 prepopulate. 사용자가 즉시 인수 타이핑 → Cmd+Enter.

**Estimated Time**: 30-45분
**Status**: ⏳ Pending

**Test Strategy**: `pendingSlashInsertion` 을 set 한 후 composer state 가 동기화되는지 검증.

#### Tasks

**🔴 RED**

- [ ] **Test 1.1**: `ChatComposerSlashConsumerTests` (신규) — environment.pendingSlashInsertion = "/foo <bar>" set 후 ChatComposer 가 viewModel.draft 에 동일 문자열 적재 + consume 후 environment 가 nil 로 클리어 검증
- [ ] **Test 1.2**: `DispatchComposerSlashConsumerTests` (신규) — 동일 흐름, DispatchComposer 의 @State draft 가 채워지는지 검증

**🟢 GREEN**

- [ ] **Task 1.3**: `ChatComposer.swift` 에 `@Bindable var environment: ControlTowerEnvironment` 추가 (또는 `Binding<String?>` for pendingSlashInsertion) + `.onChange(of: environment.pendingSlashInsertion)` 으로 consume → viewModel.draft 갱신
- [ ] **Task 1.4**: `DispatchComposer.swift` 의 `@State draft` → `@State` 유지하되, `.onChange(of:)` 로 pendingSlashInsertion 진입 시 draft 갱신. `consumePendingSlashInsertion()` 호출
- [ ] **Task 1.5**: `ChatView.swift` / `ControlTowerView.swift` 의 ChatComposer / DispatchComposer instantiation 에 environment 주입

**🔵 REFACTOR**

- [ ] **Task 1.6**: 두 composer 의 consume 로직 → `SlashConsumerModifier` ViewModifier 로 추출 (선택) — Phase 2 의 SlashSuggestionsModifier 와 같이 가는 게 좋으면 통합

#### Quality Gate ✋

- [ ] `swift build` green
- [ ] 853+ tests pass (+신규 2-3)
- [ ] `swiftlint --quiet` 0 violation
- [ ] **Manual smoke**: `/Applications/Maestro.app` 띄워서 Cmd+K → "/help" 검색 → 클릭 → ChatComposer 입력창에 `/help` 가 보여야 함. DispatchComposer 도 동일.
- [ ] 기존 Cmd+Enter 전송 / Cmd+. 취소 정상 동작

#### Dependencies / Coverage

- 의존: 없음 (현재 코드 베이스만 사용)
- Coverage: composer 의 consume 분기 100% (테스트 set 후 draft 검증)

#### Rollback

`git revert <Phase 1 commit>` — 단일 commit 으로 묶어서.

---

### Phase 2: Inline `/` Popover (자동완성 핵심)

**Goal**: 입력창에 `/` 또는 `/<query>` 타이핑 시 popover 자동 표시. 화살표/Enter/Esc 키 navigation. 선택 시 마지막 `/<query>` 토큰을 `/foo <args>` 로 replace.

**Estimated Time**: 4-5시간
**Status**: ⏳ Pending

**Test Strategy**: pure logic (`SlashSuggestionEngine`) 단위 테스트 우선. UI 통합은 manual smoke + ViewInspector 없이 가능한 minimal SwiftUI test.

#### Tasks

**🔴 RED**

- [ ] **Test 2.1**: `SlashSuggestionEngineTests` (신규, 12-15 cases)
  - 빈 draft → no suggestion
  - `"hello"` → no suggestion (no `/`)
  - `"hello /he"` → suggestion at last token, query="he"
  - `"/help"` → suggestion at draft start, query="help"
  - `"/help "` → no suggestion (token closed by space)
  - `"hello /he /cl"` → query="cl" (last `/` token)
  - 멀티라인: `"line1\n/he"` → query="he"
  - 부분 매치 / 정확 매치 ranking (FuzzyMatcher 위임)
  - replace range 정확성 (단일 토큰만, 앞 컨텍스트 보존)
- [ ] **Test 2.2**: `SlashSuggestionEngineReplaceTests` — `(draft, range, command) → newDraft` 검증
  - 인수 없음: `/he` + cmd("help") → `/help` (trailing space 없음)
  - 인수 있음: `/re` + cmd("review", args=["PR-url"]) → `/review ` (trailing space 만, `<arg>` literal 안 들어감)
  - 멀티 인수: `args=["a", "b"]` → `/cmd ` (사용자가 자유롭게 인수 타이핑)
- [ ] **Test 2.3**: `SlashKeyNavigationStateTests` — 후보 N개 + selectedIndex, ArrowUp/ArrowDown wrap-around, Enter return selected, Esc return nil

**🟢 GREEN**

- [ ] **Task 2.4**: `SlashSuggestionEngine` (Sources/MaestroCore/SlashSuggestionEngine.swift)
  ```swift
  public struct SlashSuggestionEngine: Sendable {
      public struct Suggestion: Sendable {
          public let candidates: [DiscoveredSlashCommand]
          public let replaceRange: Range<String.Index>
          public let query: String
      }
      public func evaluate(draft: String, registrySnapshot: [DiscoveredSlashCommand]) -> Suggestion?
      public func applySelection(draft: String, suggestion: Suggestion, selected: DiscoveredSlashCommand) -> String
  }
  ```
- [ ] **Task 2.5**: `SlashPopoverContent` (Sources/Maestro/CommandPalette/SlashPopoverContent.swift) — popover 의 List view (선택 highlight, 짧은 description, source label)
- [ ] **Task 2.6**: `SlashSuggestionsModifier` ViewModifier — `@Binding var draft: String` + popover overlay + `.onKeyPress` 통합
  - 상태: `@State var suggestion: Suggestion?` + `@State var selectedIndex: Int = 0`
  - `onChange(draft)` → engine.evaluate → suggestion update
  - `.popover(isPresented: suggestion != nil)` → SlashPopoverContent
  - `.onKeyPress(.upArrow)` → selectedIndex--, return .handled
  - `.onKeyPress(.downArrow)` → selectedIndex++
  - `.onKeyPress(.return)` → applySelection, suggestion = nil
  - `.onKeyPress(.escape)` → suggestion = nil
- [ ] **Task 2.7**: ChatComposer 의 TextEditor 에 `.modifier(SlashSuggestionsModifier(draft: $viewModel.draft, registry: env.slashCommandRegistry))`
- [ ] **Task 2.8**: DispatchComposer 의 TextField 에 동일 modifier
- [ ] **Task 2.9**: registry snapshot 호출은 actor await — modifier 내 `.task(id: draft)` 에서 비동기 갱신 (debounce 100ms — typing burst 흡수)

**🔵 REFACTOR**

- [ ] **Task 2.10**: Engine 의 query 추출 로직 (마지막 `/` token finder) → 별도 함수 + edge case (escape, 멀티라인) 보강
- [ ] **Task 2.11**: Phase 1 의 SlashConsumerModifier 와 통합 가능한지 검토 — 두 modifier 가 동일 binding 받으면 합칠 수 있음

#### Quality Gate ✋

- [ ] `swift build` green
- [ ] 853+ tests pass (+신규 ~25)
- [ ] swiftlint clean
- [ ] **Manual smoke**:
  - ChatComposer 에 `/` 타이핑 → popover 즉시 표시
  - 화살표 위/아래로 선택 이동
  - Enter → 선택 명령이 입력창에 들어감 (인수 없으면 `/foo`, 있으면 `/foo ` 만 — `<arg>` literal 텍스트는 안 들어감)
  - Esc → popover 닫힘, draft 변경 X
  - 빈 입력 또는 `hello` 같은 일반 텍스트 → popover 안 뜸
  - `hello /` → popover 뜨고 query="" (모든 후보)
- [ ] Cmd+Enter 전송 시 popover 닫히고 정상 dispatch

#### Dependencies / Coverage

- 의존: Phase 1 의 environment binding (이미 wire 됨)
- Coverage: SlashSuggestionEngine 95%+, modifier UI 는 manual smoke 만 (SwiftUI test infrastructure 없음)

#### Rollback

modifier attach 만 제거하면 Phase 1 상태로 복귀. SlashSuggestionEngine 은 dead code 로 남아도 무관.

---

### Phase 3: 소스별 아이콘 + 섹션 (팔레트 + popover polish)

**Goal**: 팔레트와 popover 의 슬래시 항목을 builtin / userFile / skill 별로 SF Symbol 아이콘 + (가능하면) 섹션 헤더로 그룹핑. popover 안에서는 인수 힌트도 회색 보조 텍스트로 표시.

**Estimated Time**: 1-1.5시간
**Status**: ⏳ Pending

**Test Strategy**: SlashCommandPaletteProvider 의 출력 검증 + 팔레트 / popover UI manual smoke.

#### Tasks

**🔴 RED**

- [ ] **Test 3.1**: `SlashCommandPaletteProviderTests` 확장 — DiscoveredSlashCommand 의 source 별로 expected icon name (`terminal`, `doc.text`, `folder`, `wand.and.stars`) + section label 검증

**🟢 GREEN**

- [ ] **Task 3.2**: `SlashCommandSourceKind` 에 `iconName: String` computed property 추가
  ```swift
  public var iconName: String {
      switch self {
      case .builtin: return "terminal"
      case .userFile: return "doc.text"
      case .projectFile: return "folder"
      case .skill: return "wand.and.stars"
      }
  }
  ```
- [ ] **Task 3.3**: `Command` 모델에 optional `iconName: String?` 추가 (CommandPalette 가 이미 icon 지원하면 skip)
- [ ] **Task 3.4**: `SlashCommandPaletteProvider.commands()` 가 `iconName` + source label 채워서 반환
- [ ] **Task 3.5**: 팔레트 UI 가 source 별 섹션 헤더 — 가능 여부는 CommandPalette view 구조에 의존. 단일 카테고리 한계면 subtitle 에 source label 만 추가
- [ ] **Task 3.6**: Phase 2 의 `SlashPopoverContent` 가 각 행에 (a) source icon, (b) 인수 힌트 회색 보조 텍스트 (`/review` 옆에 `<PR-url>` 회색으로) 표시

**🔵 REFACTOR**

- [ ] **Task 3.7**: 아이콘/라벨 매핑 dictionary 화 — 신규 source 추가 시 한 곳만 수정

#### Quality Gate ✋

- [ ] `swift build` green
- [ ] 853+ tests pass (+신규 ~3)
- [ ] swiftlint clean
- [ ] **Manual smoke**:
  - Cmd+K 팔레트에서 슬래시 섹션이 source 별로 시각적 구분 (icon + section/subtitle)
  - `/` popover 안에서도 각 행에 source icon + 인수 힌트 회색 텍스트 보임 (`/review  PR-url` 같은 형식)
  - 인수 없는 명령 (`/help`) 은 힌트 자리 비어있음

#### Dependencies / Coverage

- 의존: Phase 2 (popover)
- Coverage: provider output 100%

#### Rollback

iconName 필드 무시. 단순 cosmetic 변경이라 rollback 위험 0.

---

## ⚠️ Risk Assessment

| Risk                                                                                | Probability | Impact                            | Mitigation                                                                                                      |
| ----------------------------------------------------------------------------------- | ----------- | --------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `.onKeyPress` 가 popover 띄울 때 input field focus 잃음                             | Medium      | High (popup 안 뜨거나 키 안 먹힘) | popover 의 `attachmentAnchor` + `.allowsHitTesting(false)` 시도. 안 되면 popover 대신 `.overlay` 로 inline UI   |
| FuzzyMatcher 의 ranking 이 슬래시 명령 도메인에 부적합                              | Low         | Low                               | 사용자 피드백 후 점수 함수 튜닝. 신규 alias `Slash`-specific scorer 가능                                        |
| Multiline TextEditor 에서 popover 위치가 cursor 근처 X (전체 textfield 위에 attach) | Low         | Low                               | macOS 14 popover 는 view 기준 — 중앙 attach 가 일반적. cursor 추적 popup 은 NSTextView 필요 → 이번 plan 범위 외 |
| 환경 binding 변경이 ControlTowerView re-render storm                                | Low         | Medium                            | @Observable + onChange 패턴 — pendingSlashInsertion 만 observe. 다른 env 필드 변경은 영향 X                     |
| 854 → 900 테스트 실행 시간 늘어남                                                   | Low         | Low                               | 신규 테스트 모두 unit (Engine pure logic) — 100ms 미만                                                          |

---

## 🛠️ Rollback Strategy

Phase 별 단일 commit 으로 묶음. 문제 시:

- Phase 1 revert → 팔레트 클릭 dead 상태로 복귀 (현재와 동일)
- Phase 2 revert → popup 사라짐, Phase 1 wiring 만 유지
- Phase 3 revert → 아이콘/섹션 사라짐, 단일 `.slash` 카테고리

각 phase 가 독립적이라 부분 revert 가능.

---

## 📊 Progress Tracking

- [ ] Phase 1: Composer Wiring (Cmd+K → 입력창 prepopulate)
- [ ] Phase 2: Inline `/` Popover (TUI 핵심 — 자동완성)
- [ ] Phase 3: 소스별 아이콘 + 섹션 + 인수 힌트 (popover/팔레트 polish)
- [ ] 전체 wrap-up: appVersion 0.6.0 → 0.7.0 bump + DMG 빌드 + (별도 release pipeline 진행 시) 배포

---

## 📝 Notes & Learnings

(각 phase 완료 시 추가)

---

## 🔬 Per-Phase Review Protocol

각 phase 완료 시 (commit 전):

1. **Self review** — 전체 diff 한 번 읽기
2. **/simplify 리뷰** — 단순화 가능 항목 추출
3. **/team 리뷰** — concurrency / UX / edge case / API design 4-에이전트 병렬
4. **must-fix 반영** — HIGH/MEDIUM 즉시 fix
5. **defer 항목 기록** — Notes 섹션
6. **commit + push** — single commit per phase, 명확한 메시지
7. **CI watch** — green 까지 확인, flaky 면 별도 commit 으로 fix

---

## 🔗 Related Files

- `Sources/MaestroCore/SlashCommand.swift` — 모델 (수정 X)
- `Sources/MaestroCore/SlashCommandRegistry.swift` — actor (read-only)
- `Sources/MaestroCore/DiscoveredSlashCommand.swift` — Phase 3 에서 iconName 추가
- `Sources/MaestroCore/FuzzyMatcher.swift` — 재사용
- `Sources/MaestroCore/SlashSuggestionEngine.swift` — **신규 (Phase 2)**
- `Sources/Maestro/CommandPalette/SlashCommandPaletteProvider.swift` — Phase 3 에서 iconName 전달
- `Sources/Maestro/CommandPalette/SlashPopoverContent.swift` — **신규 (Phase 2)**
- `Sources/Maestro/CommandPalette/SlashSuggestionsModifier.swift` — **신규 (Phase 2)**
- `Sources/Maestro/Chat/ChatComposer.swift` — Phase 1+2 에서 modifier attach
- `Sources/Maestro/ControlTower/DispatchComposer.swift` — 동일
- `Sources/Maestro/ControlTower/ControlTowerView.swift` — `pendingSlashInsertion` (read-only)
- `Sources/Maestro/ControlTower/ControlTowerEnvironment+Bootstrap.swift` — 변경 X
- `docs/reviews/phase-17.md` — orphan defer 기록 (history)
