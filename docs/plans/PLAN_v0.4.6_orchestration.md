# Implementation Plan: v0.4.6 Orchestration Loop + Auto-install + Control Vendor

**Status**: 🔄 In Progress
**Started**: 2026-04-26
**Last Updated**: 2026-04-26

---

## 📋 Overview

v0.4.5 까지: control 이 RELAY_TO 발행 → 자식 spawn + 응답 → **응답이 사용자 시점에서 보이지 않음**.
inbox routing 만 fix 했으나, 자식 응답이 control 채팅으로 follow-up 으로 흐르지 않아
사용자는 결과를 종합해 받지 못함. 이번 릴리스에서 진짜 멀티 에이전트 루프 완성.

추가로 사용자 요청: 어댑터 자동 설치 + control 어댑터 사용자 선택.

### Success Criteria

- [ ] control 에 "각 폴더 역할 보고" 메시지 → 자식 5개 응답이 control 채팅에 follow-up assistant 메시지로 도착
- [ ] 자식 폴더 ChatView 가 dispatch 받은 메시지 + 자기 응답을 표시 (현재 비어있음)
- [ ] 미설치 어댑터에 "자동 설치" 버튼 → npm install / pip install 진행 + 결과 표시
- [ ] Control 폴더 어댑터를 사이드바 ⌘, 또는 onboarding 에서 변경 가능
- [ ] Vendor picker 카피 친절화 (한 줄 설명, "처음 쓰기 좋음" 등)
- [ ] 모든 phase /team 리뷰 + /simplify, MUST-FIX 자동 적용
- [ ] swiftlint --strict 0, 모든 신규 + 회귀 테스트 GREEN
- [ ] v0.4.6 signed/notarized DMG + tag push

---

## 🚀 Implementation Phases

### Phase 1: Child ChatView ↔ Dispatch Sync

**Goal**: 자식 폴더에 dispatch 도착 → 자식 ChatView 에 incoming user 메시지 + assistant 응답으로 표시.
**Estimated**: 2 h

**Tasks**:

- 🔴 Test: ChatViewModel.appendIncomingDispatch(envelope:) state 검증
- 🟢 Implement: ChatViewModel 에 incoming dispatch 주입 API + ControlTowerDispatchObserver 가 호출
- 🔵 Refactor: 자식 / 부모 양쪽 일관

**Quality gate**: 통합 시나리오 — control → child → child ChatView 에 메시지 보임

---

### Phase 2: Multi-turn Relay Loop (자식 응답 → control 채팅)

**Goal**: RELAY_TO 후 자식 응답들을 종합해서 control 채팅에 system/assistant 메시지로 follow-up.
**Estimated**: 2 h

**Tasks**:

- 🔴 Test: DispatchService 가 모든 relay 응답 수신 후 콜백 호출 (RelayResultsAggregator)
- 🟢 Implement: relays for-loop 을 수집 모드로 (`expectReply: true`) → results 배열 → control ChatView 에 follow-up 주입
- 🔵 Refactor: timeout 조정 (자식 5개 병렬 = 최대 timeout × 1)

**Quality gate**: 5개 자식에게 dispatch → 5개 응답 모두 control 채팅에 들어옴

---

### Phase 3: Adapter Auto-install

**Goal**: vendor picker 에서 미설치 어댑터에 "자동 설치" 버튼 → 진행 시트 → 완료 후 자동 재감지.
**Estimated**: 2.5 h

**Tasks**:

- 🔴 Test: AdapterInstaller (npm/pip presence 감지, install 명령 spawn, 결과 파싱)
- 🟢 Implement:
  - `AdapterInstaller` actor — Claude (`npm install -g @anthropic-ai/claude-code`) / Aider (`pip install aider-chat`)
  - `InstallProgressSheet` SwiftUI — terminal-style log + 취소 + 완료 후 ✓
  - VendorPickerSheet 에 "설치하기" 버튼 (미설치 + 패키지 매니저 발견 시)
- 🔵 Refactor: 사용자 친화 에러 ("npm 이 없어요. https://nodejs.org 에서 Node 설치")

**Quality gate**: aider 미설치 상태 → 설치 버튼 → pip install 진행 → ✓ → 폴더 추가 가능

---

### Phase 4: Control Vendor 사용자 선택

**Goal**: control 폴더의 adapterId 도 사용자 선택 존중. ⌘, 로 변경 가능. onboarding 에 한 단계 추가.
**Estimated**: 1.5 h

**Tasks**:

- 🔴 Test: chatViewModelFactory 가 control 폴더의 folder.adapterId 사용 (현재 하드코딩)
- 🟢 Implement:
  - `chatViewModelFactory` 에서 `folder.adapterId` 로 분기 (아이더 가능)
  - onboarding 마지막 단계 — "메인 컨트롤 어댑터?" picker
  - FolderSettingsSheet 가 control 폴더에서도 정상 동작 (이미 가능, 검증)
- 🔵 Refactor: appendSystemPromptProvider Aider 호환 — Aider 는 system prompt 자동 주입 미지원, 한계 명시 alert

**Quality gate**: control 폴더 어댑터를 aider 로 변경 → 설치되어 있으면 동작, 안되어있으면 안내

---

### Phase 5: Vendor Picker 친절 카피 + UX 다듬기

**Goal**: vendor picker / 폴더 추가 / 토론 시작 등 사용자 노출 모든 카피 1단계 친절화.
**Estimated**: 1 h

**Tasks**:

- 🟢 Implement:
  - VendorPickerSheet: 각 어댑터에 1줄 설명 + "처음 쓰기 좋음" 추천 라벨
  - 설치 안내 → 자동 설치 버튼으로 대체
  - Empty state 카피 일관 (폴더 없음 / 토론 없음 / 메시지 없음)
- 🔵 Refactor: docstring 정리

**Quality gate**: 신규 사용자 첫 5분 시나리오 무리 없이 진행

---

### Phase 6: Integration + v0.4.6 Release

**Goal**: 풀 회귀 + DMG 빌드 + tag.

---

## 📊 Progress

- Phase 1: ⏳
- Phase 2: ⏳
- Phase 3: ⏳
- Phase 4: ⏳
- Phase 5: ⏳
- Phase 6: ⏳

**Plan Status**: 🔄 In Progress
**Next Action**: Phase 1 시작
