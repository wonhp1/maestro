# Implementation Plan: v0.4.3 Reachability + Friendly UX

**Status**: 🔄 In Progress
**Started**: 2026-04-26
**Last Updated**: 2026-04-26
**Estimated Completion**: 2026-04-26

---

**⚠️ CRITICAL INSTRUCTIONS**: After completing each phase:

1. ✅ Check off completed task checkboxes
2. 🧪 Run all quality gate validation commands (test + lint + build)
3. 👥 Run `/team` multi-agent review (architecture / security / test-quality / ux)
4. ✨ Run `/simplify` review and apply suggestions
5. 🔧 Auto-fix any errors surfaced
6. 📅 Update "Last Updated" date
7. 📝 Document learnings in Notes section
8. ➡️ Only then proceed to next phase

⛔ **DO NOT skip quality gates or proceed with failing checks**

---

## 📋 Overview

### Feature Description

Maestro v0.4.2 ships with strong domain logic but **many features are unreachable from the UI**:
the Discussion engine has zero entry point, every folder is hardcoded to Claude (no vendor picker),
and `.app` launches fail to find CLIs that live outside the system PATH.

This plan ships **v0.4.3** with three goals:

1. Every implemented feature must have a discoverable UI entry point.
2. The "+ 폴더 추가" flow must let users pick the vendor (Claude / Aider) and show CLI detection status.
3. macOS `.app` launch must find CLIs installed via npm-global / homebrew / etc.

The UX bar is "사용자에게 친절하게 쉽게 알 수 있도록" — empty states, tooltips, error messages
written for humans, not stack traces.

### Success Criteria

- [ ] Maestro.app launched from Finder finds `claude` (npm-global) without terminal launch
- [ ] "+ 폴더 추가" dialog shows vendor picker with live `✓ claude v0.4.x` / `✗ aider 미설치` indicators
- [ ] Sidebar exposes "+ 새 토론" entry → modal → DiscussionDetailView mounts
- [ ] DiscussionListView appears in sidebar; ongoing discussion shows current speaker / turn
- [ ] FolderSettingsSheet adapter picker reads from AdapterRegistry (no hardcoded list)
- [ ] Diagnostics export menu actually writes the bundle (not no-op)
- [ ] Crash from previous launch shown in alert on next launch
- [ ] Empty states present: "아직 폴더가 없어요" / "아직 토론이 없어요" with single CTA
- [ ] All swiftlint --strict 0 violations
- [ ] All tests pass (target: 722 → ~770+)
- [ ] v0.4.3 signed + notarized DMG built and verified with Gatekeeper

### User Impact

사용자가 앱을 받아서:

1. 더블클릭 → claude 자동 발견 → 즉시 사용 가능
2. 폴더 추가 시 vendor 선택 + 설치 안내
3. 사이드바에서 토론 시작 → control이 모더레이팅 → 결론 도출
4. 진단 번들 / 크래시 리포트 / 어댑터 설정 모두 메뉴/설정에서 접근 가능

---

## 🏗️ Architecture Decisions

| Decision                                        | Rationale                                                                        | Trade-offs                                       |
| ----------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------ |
| Login shell PATH 추출 (`bash -lc 'echo $PATH'`) | 사용자 환경의 실제 PATH 그대로 사용 — homebrew/npm-global/asdf 등 모두 자동 처리 | 첫 실행 시 ~50ms 지연 / 캐싱으로 완화            |
| AdapterRegistry를 source of truth로 일원화      | UI/도메인 양쪽에서 같은 어댑터 목록 사용 → "claude/aider" 하드코딩 제거          | 새 어댑터 추가 시 등록 한 곳만 보면 됨           |
| Discussion modal sheet (NavigationLink 아닌)    | 시작 단계는 가벼운 결정 작업 — modal이 적합                                      | 진행 중 토론은 detail pane에서 normal navigation |
| LLMModerator를 control 어댑터로 사용            | 이미 control 어댑터가 system prompt 주입됨 — moderator도 동일 패턴               | LLM 호출 비용 / RoundRobin 옵션 함께 제공        |
| Crash review를 alert로 (전용 view 없음)         | 빈도 낮음, 오버엔지니어링 불필요                                                 | 상세 stack trace는 진단 번들로                   |

---

## 📦 Dependencies

### Required Before Starting

- [x] v0.4.2 코드베이스 (이미 main에 머지됨)
- [x] 테스트 인프라 (XCTest, 722 tests baseline)
- [x] swiftlint --strict 0 violations baseline
- [x] sign/notarize pipeline 검증됨 (v0.4.2 빌드 성공)

### External Dependencies

- 신규 패키지 추가 없음 (Sparkle 외 모두 표준 라이브러리)

---

## 🧪 Test Strategy

### Testing Approach

**TDD Principle**: Write tests FIRST, then implement to make them pass

### Test Pyramid for This Feature

| Test Type             | Coverage Target | Purpose                                                                      |
| --------------------- | --------------- | ---------------------------------------------------------------------------- |
| **Unit Tests**        | ≥80%            | LoginShellPathExtractor, AdapterDetectionViewModel, DiscussionStartViewModel |
| **Integration Tests** | Critical paths  | Folder add with vendor pick, Discussion start → engine wire                  |
| **Manual UI Tests**   | Key flows       | Cold launch → folder add → discussion start → conclude                       |

### Test File Organization

```
Tests/MaestroCoreTests/
├── LoginShellPathExtractorTests.swift   (Phase 1)
├── AdapterDetectionViewModelTests.swift (Phase 2)
├── DiscussionStartViewModelTests.swift  (Phase 3)
├── DiscussionListViewModelTests.swift   (Phase 4)
└── (existing tests)

Tests/MaestroTests/  (UI / integration)
├── FolderAddFlowTests.swift             (Phase 2)
└── DiscussionFlowTests.swift            (Phase 3-4)
```

### Coverage Requirements by Phase

- **Phase 1 (PATH)**: LoginShellPathExtractor unit tests ≥90%
- **Phase 2 (Vendor picker)**: AdapterDetectionViewModel ≥80%, FolderAddFlow integration
- **Phase 3 (Discussion start)**: DiscussionStartViewModel ≥80%
- **Phase 4 (Discussion list/conclude)**: DiscussionListViewModel ≥80%
- **Phase 5 (Orphan wire-up)**: smoke tests for each wired feature
- **Phase 6 (Release)**: full regression, end-to-end manual scenario

---

## 🚀 Implementation Phases

### Phase 1: Login Shell PATH Augmentation

**Goal**: `Maestro.app` launched from Finder/Dock finds `claude`, `aider`, and any other CLI that the user's interactive shell can find.
**Estimated Time**: 1 hour
**Status**: ⏳ Pending

#### Tasks

**🔴 RED: Write Failing Tests First**

- [ ] **Test 1.1**: `LoginShellPathExtractorTests` — extract PATH from a stub shell, parse colon-separated, dedupe, merge with current PATH
  - File: `Tests/MaestroCoreTests/LoginShellPathExtractorTests.swift`
  - Cases: empty stdout, malformed stdout, timeout, normal `/opt/homebrew/bin:/usr/local/bin:...`, dedupe
- [ ] **Test 1.2**: `EnvironmentAugmenterTests` — given an extractor, sets `setenv("PATH", merged, 1)` once and only once
  - Idempotent on second call

**🟢 GREEN: Implement to Make Tests Pass**

- [ ] **Task 1.3**: `LoginShellPathExtractor.swift` (MaestroCore)
  - Spawns `/bin/zsh -lc 'echo $PATH'` (or `$SHELL` fallback) with 3s timeout
  - Returns `[String]` of dedupe'd path components
- [ ] **Task 1.4**: `EnvironmentAugmenter.swift` (MaestroCore)
  - `augmentPATHFromLoginShell()` — runs extractor, merges into current PATH (current first), `setenv`
- [ ] **Task 1.5**: Wire-in at app launch — call `EnvironmentAugmenter.augmentPATHFromLoginShell()` in `MaestroApp.init` BEFORE any adapter detection
  - File: `Sources/Maestro/MaestroApp.swift`

**🔵 REFACTOR: Clean Up Code**

- [ ] **Task 1.6**: Cache result for app lifetime (one-shot static)
- [ ] **Task 1.7**: Log augmented paths via `MaestroLogger.process` for debugging

#### Quality Gate ✋

**TDD Compliance**:

- [ ] Red → Green → Refactor 순서
- [ ] Coverage: LoginShellPathExtractor + EnvironmentAugmenter ≥90%

**Build & Tests**:

- [ ] `swift build` 성공
- [ ] `swift test` 100% 통과
- [ ] swiftlint --strict 0 violations

**Manual**:

- [ ] `open build/Maestro.app` → control agent successfully spawns claude (no AdapterError 0)

**👥 /team 리뷰**:

- [ ] architecture / security / test-quality 3명 병렬 리뷰
- [ ] must-fix 모두 자동 수정

**✨ /simplify**:

- [ ] 단순화 제안 적용

---

### Phase 2: Adapter Detection + Vendor Picker on Folder Add

**Goal**: 사용자가 "+ 폴더 추가" 누르면 NSOpenPanel 후 **vendor 선택 sheet** 가 떠서 Claude/Aider 라디오 + 각 어댑터의 라이브 감지 상태 (✓ 설치 + 버전 / ✗ 미설치 + 설치 안내) 를 보여준다.
**Estimated Time**: 2 hours
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 2.1**: `AdapterDetectionViewModelTests` — registry에 등록된 모든 어댑터에 대해 detect() 호출, 결과 캐싱
  - Cases: 모두 설치됨, 일부 미설치, 모두 미설치, detect 실패
- [ ] **Test 2.2**: `FolderAddFlowTests` — picker → vendor sheet → registry.add(adapterId: 선택값) end-to-end
- [ ] **Test 2.3**: `VendorPickerStateTests` — preselect 가장 최근 사용 어댑터 / 미설치 어댑터 선택 시 disabled

**🟢 GREEN**

- [ ] **Task 2.4**: `AdapterDetectionViewModel.swift` (MaestroCore) — `@Observable`, `detections: [AdapterID: AdapterDetection]`
- [ ] **Task 2.5**: `VendorPickerSheet.swift` (Maestro/Folders) — radio + ✓/✗ 표시 + 미설치 시 "어떻게 설치?" inline 안내
  - Claude: `npm install -g @anthropic-ai/claude-code` 또는 docs URL
  - Aider: `pip install aider-chat`
- [ ] **Task 2.6**: `FolderViewModel.addFolder()` 변경 — picker 후 vendor sheet 띄우기, 사용자 선택 받아 registry.add
- [ ] **Task 2.7**: `FolderSettingsSheet`의 하드코딩 `["claude","aider"]` → AdapterRegistry 동적 읽기

**🔵 REFACTOR**

- [ ] **Task 2.8**: 공통 컴포넌트 `AdapterDetectionRow` — sheet/settings 양쪽에서 재사용
- [ ] **Task 2.9**: 친절 카피 (한국어): "Claude를 사용할 거면 위를 선택하세요" 같은 hint

#### Quality Gate ✋

**TDD**:

- [ ] Red → Green → Refactor
- [ ] AdapterDetectionViewModel 커버리지 ≥80%

**Build & Tests**:

- [ ] swift build / swift test / swiftlint --strict 모두 GREEN

**Manual**:

- [ ] "+ 폴더 추가" → 폴더 선택 → sheet 표시 → ✓ claude / ✗ aider 보임 → 라디오 → 폴더 등록 성공
- [ ] FolderSettingsSheet에서 어댑터 변경 가능

**👥 /team**: architecture / security / test-quality / ux
**✨ /simplify**

---

### Phase 3: Discussion Start UI

**Goal**: 사이드바 하단에 "+ 새 토론" 버튼. 누르면 sheet — 주제, 참가자 (등록된 폴더 multi-select), moderator 전략 (RoundRobin / LLM), maxTurns. "시작" → DiscussionEngine 인스턴스 생성 + DiscussionDetailView 마운트.
**Estimated Time**: 3 hours
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 3.1**: `DiscussionStartViewModelTests` — 입력 검증 (주제 비어있음, 참가자 < 2, maxTurns 범위)
- [ ] **Test 3.2**: `DiscussionStartViewModelTests.testStart` — valid 입력 → DiscussionEngine 생성 + Discussion record 영속화
- [ ] **Test 3.3**: `DiscussionStartFlowTests` (integration) — sheet → 시작 → list에 새 토론 표시

**🟢 GREEN**

- [ ] **Task 3.4**: `DiscussionStartViewModel.swift` (MaestroCore) — @Observable, validate + start
- [ ] **Task 3.5**: `DiscussionStartSheet.swift` (Maestro/Discussion)
  - 주제 TextField (placeholder: "예: 새 기능 우선순위 정하기")
  - 참가자 multi-select (체크박스 list, 최소 2개)
  - moderator 전략 segmented control: RoundRobin / Random / LLM (control)
  - maxTurns slider (5-50, 기본 20)
  - "시작" / "취소" 버튼
- [ ] **Task 3.6**: 사이드바 하단 "+ 새 토론" entry — `SidebarView` 변경
- [ ] **Task 3.7**: 시작 → DiscussionDetailView를 detail column에 mount

**🔵 REFACTOR**

- [ ] **Task 3.8**: 빈 상태 — 참가자 < 2 시 시작 버튼 disabled + 이유 표시
- [ ] **Task 3.9**: 친절 카피: 첫 토론 시 짧은 설명 ("여러 에이전트가 한 주제로 의견 교환합니다")

#### Quality Gate ✋

**TDD / Build / Lint**: 동일 패턴

**Manual**:

- [ ] 사이드바 "+ 새 토론" → sheet → 폴더 2개 선택 → 시작 → DiscussionDetailView 표시 + 첫 발언자 turn 시작

**👥 /team / ✨ /simplify**

---

### Phase 4: Discussion List + Conclude UX

**Goal**: 진행 중인 토론들이 사이드바에 list로 표시. 각 row는 주제, 참가자 아바타, 현재 발언자, turn 수. 토론 detail에서 "종료" 버튼 + 결론 input.
**Estimated Time**: 2 hours
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 4.1**: `DiscussionListViewModelTests` — registry 변경 → list 갱신, 종료된 토론 표시 분리
- [ ] **Test 4.2**: `DiscussionConcludeTests` — 종료 → state == .completed + 결론 영속화
- [ ] **Test 4.3**: LLM moderator가 자동 종료 신호 (`[CONCLUDE]`) 보내면 engine state 전이 검증

**🟢 GREEN**

- [ ] **Task 4.4**: `DiscussionListViewModel` 확장 — sidebar mount용
- [ ] **Task 4.5**: 사이드바 "토론" 섹션 — 폴더 섹션 아래에 추가
- [ ] **Task 4.6**: `DiscussionDetailView` 종료 버튼 + 결론 sheet
- [ ] **Task 4.7**: 진행 중 표시 — 현재 발언자 highlight, "에이전트 X가 답변 중…" indicator

**🔵 REFACTOR**

- [ ] **Task 4.8**: 종료된 토론 archive 섹션 (접힘)
- [ ] **Task 4.9**: 친절 알림 — 종료 시 "토론이 끝났어요. 결론은 control 폴더에 저장됩니다."

#### Quality Gate ✋

**Manual**:

- [ ] 토론 시작 → 5턴 진행 → 수동 종료 → 결론 저장 확인
- [ ] LLM moderator 선택 → 자동 종료 동작

**👥 /team / ✨ /simplify**

---

### Phase 5: Orphan Wire-up + Friendly UX Pass

**Goal**: 나머지 orphan 기능들에 진입점 + 전체 UX 친절도 다듬기.
**Estimated Time**: 2 hours
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 5.1**: `DiagnosticsExportTests` — 메뉴 트리거 → ZIP 파일 생성 검증
- [ ] **Test 5.2**: `CrashReviewAlertTests` — 시작 시 unread crash 있으면 alert 트리거

**🟢 GREEN**

- [ ] **Task 5.3**: 진단 번들 export 메뉴의 no-op handler 실제 wire (`MaestroApp.swift:61`)
- [ ] **Task 5.4**: 시작 시 `CrashReporter.load()` 호출 → unread 있으면 alert + dismiss/export 옵션
- [ ] **Task 5.5**: 빈 상태 (Empty State) 일관 컴포넌트
  - 폴더 0개: "프로젝트 폴더를 추가하면 시작할 수 있어요" + [+ 폴더 추가]
  - 토론 0개: "여러 에이전트와 의견 교환을 시작해보세요" + [+ 새 토론]
  - 메시지 0개: "메시지를 입력하고 ⌘↵ 로 전송"
- [ ] **Task 5.6**: 에러 메시지 한국어 친화화 — `AdapterError.notInstalled` → "claude CLI가 설치되어 있지 않아요. `npm install -g @anthropic-ai/claude-code` 로 설치하세요."

**🔵 REFACTOR**

- [ ] **Task 5.7**: Tooltips — Cmd+K, ⌘N, 진단 번들 등 단축키/기능 hover 시 설명
- [ ] **Task 5.8**: First-run onboarding 한 화면 점검 (Phase 19 산출물 재검토)

#### Quality Gate ✋

**Manual**:

- [ ] 첫 실행 (clean App Support) → onboarding → 폴더 추가 안내 → 추가 → 메시지 → 토론 → 진단 export → 모두 친절 카피

**👥 /team / ✨ /simplify**

---

### Phase 6: Integration + v0.4.3 Release

**Goal**: 전체 회귀 테스트, end-to-end 시나리오 검증, signed/notarized DMG 빌드, 태그 push.
**Estimated Time**: 1 hour
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 6.1**: 풀 회귀 — 기존 722 + 신규 모든 테스트 실행
- [ ] **Test 6.2**: end-to-end manual 시나리오 (UI verification)

**🟢 GREEN**

- [ ] **Task 6.3**: `MaestroConfig.appVersion = "0.4.3"` bump
- [ ] **Task 6.4**: `scripts/release.sh` 실행 — build + sign + notarize + DMG
- [ ] **Task 6.5**: Gatekeeper / stapler 검증
- [ ] **Task 6.6**: git tag v0.4.3 + push

**🔵 REFACTOR**

- [ ] **Task 6.7**: README의 "현재 기능" 섹션 업데이트 — Discussion / vendor picker 언급
- [ ] **Task 6.8**: PLAN_v0.4.3 status → ✅ Complete + Notes 채우기

#### Quality Gate ✋

**Final**:

- [ ] 신규 테스트 100% GREEN, 회귀 0
- [ ] swiftlint --strict 0 violations
- [ ] DMG signed + stapled, Gatekeeper accepted
- [ ] CI release.yml 통과
- [ ] GitHub Release v0.4.3 자동 생성

**Manual end-to-end** (clean App Support 시작):

1. `open Maestro.app` → onboarding → "+ 폴더 추가" → 폴더 선택 → vendor sheet → Claude → 등록
2. Chat에서 메시지 → claude 응답 수신
3. "+ 새 토론" → 폴더 2개 선택 → RoundRobin → 시작 → 5턴 진행 → 종료 → 결론 저장
4. 메뉴 → 진단 번들 → ZIP 파일 저장 확인
5. 메뉴 → 업데이트 확인 → Sparkle 모달

---

## ⚠️ Risk Assessment

| Risk                                                | Probability | Impact | Mitigation                                       |
| --------------------------------------------------- | ----------- | ------ | ------------------------------------------------ |
| Login shell PATH 추출 timeout / hang                | 낮          | 중     | 3s 타임아웃 + fallback to system PATH            |
| AdapterRegistry detect 호출이 blocking UI           | 중          | 중     | async detect + skeleton UI / 결과 cache          |
| Discussion engine LLM moderator 무한 루프           | 중          | 높     | maxTurns + idle timeout                          |
| SwiftUI sheet stack 깊이 제한 (NSOpenPanel + sheet) | 낮          | 낮     | Sheet 닫고 다음 sheet 띄우기 (chained)           |
| 회귀 테스트 실패 (Discussion 관련 기존 테스트)      | 중          | 중     | 변경 범위 limited to view layer + new view model |

---

## 🔄 Rollback Strategy

각 Phase 시작 전 `git tag plan-v043-phase-N-start` 찍어두고 실패 시 `git reset --hard <tag>`.
이미 main 머지된 코드는 revert PR로.

---

## 📊 Progress Tracking

### Completion Status

- **Phase 1 (PATH)**: ⏳ 0%
- **Phase 2 (Vendor picker)**: ⏳ 0%
- **Phase 3 (Discussion start)**: ⏳ 0%
- **Phase 4 (Discussion list/conclude)**: ⏳ 0%
- **Phase 5 (Orphan wire-up + UX)**: ⏳ 0%
- **Phase 6 (Release)**: ⏳ 0%

**Overall Progress**: 0% complete (0 / 6 phases)

### Time Tracking

| Phase     | Estimated | Actual | Variance |
| --------- | --------- | ------ | -------- |
| Phase 1   | 1 h       | -      | -        |
| Phase 2   | 2 h       | -      | -        |
| Phase 3   | 3 h       | -      | -        |
| Phase 4   | 2 h       | -      | -        |
| Phase 5   | 2 h       | -      | -        |
| Phase 6   | 1 h       | -      | -        |
| **Total** | **11 h**  | -      | -        |

---

## 📝 Notes & Learnings

### Implementation Notes

(채워질 예정)

### Blockers Encountered

(채워질 예정)

### Improvements for Future Plans

(채워질 예정)

---

## 📚 References

- 관련 audit: 본 대화 turn 의 Explore subagent 결과
- 영향 받는 view 파일: `Sources/Maestro/{Folders,ControlTower,Discussion}/`
- 영향 받는 도메인 파일: `Sources/MaestroCore/{ControlAgent*,Discussion*,FolderViewModel,AdapterRegistry}.swift`
- 선행 PR/태그: v0.4.2 (현재 main HEAD)

---

## ✅ Final Checklist

- [ ] All 6 phases 완료, 모든 quality gate 통과
- [ ] 모든 phase에 /team 리뷰 + /simplify 적용
- [ ] 신규 테스트 작성 + 회귀 0
- [ ] swiftlint --strict 0
- [ ] DMG signed + notarized + stapled
- [ ] v0.4.3 git tag + GitHub Release
- [ ] README 업데이트
- [ ] 본 plan 문서 status → ✅ Complete

---

**Plan Status**: 🔄 In Progress
**Next Action**: 사용자 승인 후 Phase 1 자동 시작
**Blocked By**: 사용자 승인 대기
