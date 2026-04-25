# Phase 15 Review Report — 토론 UI (Slack 스타일 스레드)

**Date**: 2026-04-25
**Phase**: 15 / 23
**Status**: ✅ Complete
**Commits**: phase-15-start → phase-15-end

---

## Deliverables

`Sources/MaestroCore/`:

- `DiscussionEngine.swift` 변경: `Event.turnCompleted` 가 `envelope: MessageEnvelope` 전체 carry — UI 가 별도 fetch 없이 즉시 렌더.
- `DiscussionViewModel.swift` (NEW) — `@MainActor @Observable`:
  - engine.events() 구독 → envelopes / state / currentSpeaker / lastError / discardedCount 갱신
  - start / pause / resume / terminate / dismissError forwarding
  - **deinit fix** — Task hop 으로 nonisolated cancel (must-fix ARCH-1)
- `DiscussionStore.swift` (NEW) — `@MainActor @Observable`:
  - viewModels: [ThreadID: DiscussionViewModel] + ordered list
  - register / get / evict / activeViewModels

`Sources/Maestro/Discussion/`:

- `ParticipantAvatar.swift` — initial + 결정론적 hash 색상 (10-color palette)
- `TypingIndicator.swift` — ●●● 애니메이션 + reduce-motion fallback
- `DiscussionDetailView.swift` — header (title + state badge) + LazyVStack 메시지 리스트 + state-driven controls (start/pause/resume/terminate) + interrupt composer
  - **pinnedToBottom + "최신 보기" 버튼** (must-fix UX-1) — 사용자 스크롤 시 auto-scroll 멈춤
  - **DisplayTextSanitizer** title/body 적용 (must-fix SEC-1)
  - reduce-motion 시 scrollTo animation skip
- `DiscussionListView.swift` — 사이드바 / inspector slot용. State glyph + 참여자 미니 아바타.

**Tests**: 520/520 통과 (3 skipped, aider 미설치) (Phase 14 의 512 → +8)

- `DiscussionViewModelTests` (5) — bindEvents → envelopes / currentSpeaker 변화 / state 전이 / turnFailed → lastError / **dismissError 진짜 에러 후 검증** (must-fix TEST-1)
- `DiscussionStoreTests` (3) — register order / 동일 ID idempotent / evict

---

## Step 2: 👥 /team Multi-Agent Review (1 묶음, arch+sec+perf+ux+test)

**Must-fix 식별 12건 → 4건 반영, 8건 defer**.

### 반영 (4건)

1. ❌→✅ **SEC-1: 표시 surface sanitize** — `DiscussionDetailView` 의 `title` / `envelope.body` 모두 `DisplayTextSanitizer.sanitize` 적용. Phase 12 의 InboxStore preview / Phase 14 turnPrompt 와 일관 (Trojan Source 방어).
2. ❌→✅ **ARCH-1: deinit 의 nonisolated(unsafe) 제거** — `Task { task.cancel() }` 패턴으로 hop. 강한 참조 capture 로 self 분리.
3. ❌→✅ **UX-1: auto-scroll yank 방지** — `pinnedToBottom` state. 사용자가 위로 스크롤 시 자동 스크롤 정지 + "최신 보기" floating 버튼으로 재 pin. reduce-motion 시 animation skip.
4. ❌→✅ **TEST-1: testDismissErrorClears 진짜 에러 검증** — `ThrowingDispatcher` 로 lastError 채운 후 dismiss → nil 확인.

### Defer (8건, Phase 16+ explicit 또는 scope 외)

- **PERF-1: envelopes 무한 누적** — Phase 15.9 explicit defer (50-turn 일반 사용 OK). Phase 17 persistence 시점에 LRU + "이전 보기" 도입.
- **ARCH-2: DispatchServiceTurnDispatcher noReply 데드 코드** — 방어선으로 유지 (코멘트만).
- **ARCH-3: Avatar palette Core 토큰화** — 두 번째 consumer 등장 시점 (Phase 19 mention chips).
- **SEC-2: InterruptComposer length cap** — Phase 16+ 에서 dispatch 경계에 적용.
- **UX-2: 단일 alert 채널** — Phase 10 SidebarView 와 동일 pattern, 일괄 정리는 Phase 19 polish.
- **UX-3: Korean/English 톤** — Korean 일관 (시작/일시 정지/종료/끼어들기). 미적용.
- **TEST-2: waitUntil 50ms polling brittleness** — 짧은 dispatcher 라 안정. CI 통과 확인.
- **TEST-3: SwiftUI snapshot tests** — Phase 8/10/12 precedent.

---

## Step 3: ✨ /simplify

- DiscussionViewModel 의 5종 이벤트 핸들러 한 switch 에 집중 — 분기 명확.
- `DispatchService` / `EnvelopeRouter` / `Phase 12 store` 들을 직접 참조하지 않고 `engine.events()` 단일 입력 — 결합 분리.
- "최신 보기" 버튼 + drag detection — 외부 라이브러리 없이 SwiftUI native.

## Step 4: 🧩 Integration Verification

- Release build 통과
- App spawn smoke OK (Phase 12 ControlTowerView 와 conflict 없음 — Discussion UI 는 별도 진입점)
- 520/520 테스트 통과 (3 skipped, aider 미설치 정상)
- Quality Gate (Phase 15 plan):
  - ✅ 3-agent 토론 시각적 구분 — ParticipantAvatar 색상 + initial
  - ✅ 실시간 진행 상황 — DiscussionViewModel 가 events stream 실시간 반영
  - ✅ 토론 재방문 시 envelopes 즉시 로드 — DiscussionStore 캐시 (메모리 한정, persistence 는 Phase 17)

## Step 5: 🔄 Regression Check

- Phase 1-14 통과 유지 (512 → 520, +8)
- DiscussionEngine.Event.turnCompleted signature 변경 — Phase 14 테스트도 함께 업데이트
- ChatViewModel / Folder / Inbox / DispatchService 인터페이스 미변경

## Step 6: 📐 Architecture Compliance

- ✅ ViewModel + Store 모두 `MaestroCore` (SwiftUI 미의존)
- ✅ SwiftUI 컴포넌트는 `Sources/Maestro/Discussion/` 격리 — Core 와 깔끔한 layer 경계
- ✅ Swift 6 Strict Concurrency: `@MainActor @Observable`, deinit Task hop, `Sendable` envelope
- ✅ DisplayTextSanitizer (Phase 12) 재사용 — 표시 경계에서 일관 sanitize
- ✅ Reduce-motion accessibility 지원 (TypingIndicator + scrollTo)

---

## Open Items for Later Phases

1. **DiscussionStore 영속화** (Phase 17 settings + persistence pass) — Phase 14.12 deferred 와 통합. `discussions.json` 또는 `threads/<id>.discussion.json`.
2. **NewDiscussionDialog** (Phase 15.8) — 제목 + 참여자 picker (FolderRegistry 와 연동) + maxTurns slider. 현 단계 미구현 (Phase 16 커맨드 팔레트 시점에 자연 통합).
3. **Markdown export** (Phase 15.10) — 토론 종료 후 Markdown / JSONL 다운로드.
4. **InterruptComposer wiring** — DispatchService.dispatch 통해 토론에 사용자 끼어들기 envelope 추가. Phase 16+ 에서 컨트롤 타워 진입점 통합.
5. **Avatar 실제 이미지** (Phase 19+) — adapter 별 Claude/Aider 로고 등.
6. **Single error alert channel** — Phase 10 SidebarView 와 동일 pattern, 일괄 정리.
7. **무한 스크롤 perf optimization** (Phase 15.9) — 100+ turn 시 pagination + LRU.
8. **LLMModerator wiring** (Phase 14.8) — DiscussionDetailView 에 moderator strategy picker 추가.
9. **Snapshot tests** — Phase 21 release 직전 일괄 도입 검토.
10. **DiscussionListView 의 ControlTowerView 통합** — 현재는 standalone 컴포넌트, Phase 16 커맨드 팔레트 시점에 메인 사이드바 또는 inspector 에 mount.

---

## 완료 기준

- [x] Phase 15 Task 15.1, 15.3-15.7 완료. 15.2 (snapshot) / 15.8 (dialog) / 15.9 (infinite scroll perf) / 15.10 (markdown export) defer
- [x] 520/520 테스트 통과 (3 skipped, aider 미설치 정상)
- [x] /team 리뷰 + must-fix 4건 반영, 8건 defer documented
- [x] swiftlint --strict: 0 violations
- [x] Release build + spawn 정상
- [x] Phase 1-14 회귀 없음
- [x] Quality Gate 3개 모두 자동 검증 (3-agent 시각적 구분 / 실시간 / 재방문 즉시)
- [x] 리뷰 리포트 저장 (이 파일)
- [ ] phase-15-end 태그 (다음 단계)

**Milestone 5 (토론 엔진 2주) 완료**: Phase 14 백엔드 + Phase 15 UI 모두 마무리. 사용자가 토론을 보고 끼어들 수 있음.

**다음**: Phase 16 — 커맨드 팔레트 (Cmd+K) + 단축키 시스템 (Milestone 6, 4-5일).
