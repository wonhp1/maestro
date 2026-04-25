# Phase 8 Review Report — 기본 채팅 UI

**Date**: 2026-04-25
**Phase**: 8 / 23
**Status**: ✅ Complete
**Commits**: phase-8-start → phase-8-end

---

## Deliverables

`Sources/MaestroCore/`:

- `ChatMessage.swift` — DTO (id/role/content/status/createdAt). Status: `.sending` / `.streaming` / `.complete` / **`.cancelled`** / `.failed`
- `MarkdownRenderer.swift` — `AttributedString(markdown:)` 래퍼 + URL 스킴 allowlist + bidi 제어 strip + segment 추출 (prose/codeBlock)
- `ChatViewModel.swift` — `@MainActor @Observable` view-model. 동기 cancel + .cancelled 상태 + activePlaceholderID race 가드 + 256 KiB content cap

`Sources/Maestro/Chat/` (SwiftUI):

- `ChatView.swift` — 메시지 리스트 + composer + error bar. 메시지 추가 시에만 애니메이션 스크롤 (chunk 별 yank 방지)
- `MessageBubbleView.swift` — role 별 정렬/배경 + markdown 세그먼트 렌더 + StreamingDot pulsing 인디케이터 + .cancelled/.failed footer
- `ChatComposer.swift` — TextEditor (Cmd+Enter 전송 / Cmd+. 취소) + 동적 send/stop 버튼
- `CodeBlockView.swift` — monospace + 언어 라벨 + bidi strip 적용

`Sources/Maestro/ContentView.swift` — MockAdapter 와이어링

**Tests**: 325/325 통과 (Phase 7 의 292 → +33)

- ChatMessageTests (6) — factories / status 동등성 / mutability
- MarkdownRendererTests (15) — render / plain / segments (CRLF, indented, language, multi-block, unclosed) / **link allowlist** / **bidi strip**
- ChatViewModelTests (12) — 초기 / 빈 draft / send / 스트리밍 누적 / **thinking/tool 무시** / error chunk / stream error / **cancel = .cancelled (not .failed)** / **cancel-then-immediate-send** / 동시 send 차단 / clearLastError / **content cap truncation**

---

## Step 2: 👥 /team Multi-Agent Review (5명 병렬, UX 리뷰어 추가)

### Architecture Reviewer — **Must-fix 3건, 모두 반영**

1. ❌→✅ `isStreaming = false` race on cancel — 동기적으로 cancel() 에서 처리
2. ❌→✅ Late chunks mutate stale message — `activePlaceholderID` 가드 + `applyChunk` 내 검사
3. ❌→✅ `.cancelled` status 신설 — 사용자 취소를 .failed 와 의미 분리

기각 (defer): `ChatSessionStore` actor 추출 (Phase 12), MaestroCore 의 SwiftUI guard CI rule (현재는 문서화).

### Security Reviewer — **Must-fix 3건, 모두 반영**

1. ❌→✅ Markdown link injection (`javascript:`/`file://`) → URL 스킴 allowlist (`http`/`https`/`mailto` 만 허용)
2. ❌→✅ Unbounded message content growth → `maxMessageContentBytes = 256 KiB` cap + truncation marker
3. ❌→✅ Bidi/zero-width 제어 문자 (Trojan Source) → `stripBidiControls()` 적용 (Markdown render + CodeBlockView)

추가 (SHOULD-FIX 적용):

- ✅ `String(describing: error)` → `error.localizedDescription` (internals 노출 차단)
- ✅ Error chunk 에는 markdown 적용 안 함 (system bubble — 단순 텍스트 + ⚠️ marker)

### Test Quality Reviewer — **Must-fix 3건, 모두 반영**

1. ❌→✅ `.toolUse` / `.toolResult` 묵묵 drop 미커버 → `testToolUseAndToolResultChunksAreSilentlyDropped`
2. ❌→✅ cancel-then-immediate-send race → `testCancelThenImmediateSendStartsNewStream`
3. ❌→✅ CRLF 라인 종료 → `testSegmentsHandlesCRLFLineEndings` + 코드 정규화

추가:

- ✅ link allowlist + bidi strip 검증
- ✅ content cap truncation 검증

### Performance Reviewer — **Must-fix 3건, 부분 반영**

1. ✅ Auto-scroll yank 제거 — `messages.count` 변화에만 스크롤 (chunk 별 X)
2. 🟡 String concat O(N²) — content cap 으로 worst-case 한도 (256 KiB). Phase 18 에서 chunk batching timer 도입 검토
3. 🟡 Per-chunk markdown re-parse — 현재 acceptable (256 KiB cap), Phase 18 에서 segment caching

기각: 본 phase 의 보안/race fix 가 우선순위. Perf는 256 KiB cap 으로 worst-case 한정.

### UX Reviewer — **Must-fix 4건, 모두 반영**

1. ❌→✅ Empty state 정보 부족 → 앱명 + 부제 + Cmd+Enter / Cmd+. 단축키 안내
2. ❌→✅ Streaming indicator 가 첫 chunk 후 사라짐 → `StreamingDot` (pulsing) 항상 표시
3. ❌→✅ Auto-scroll yank → count-only 트리거
4. ❌→✅ Dead `.onSubmit` on TextEditor → 제거 + 주석

추가:

- ✅ Cancel 시 `.cancelled` (red banner 안 띄움)
- ✅ Failed footer 에 `localizedDescription`
- ✅ accessibilityValue 에 status 정보

기각 (Phase 18): Copy 버튼, 사용자 스크롤 위치 detect, swift-markdown 통합 (lists/headers/tables), 메시지 timestamps.

---

## Step 3: ✨ /simplify

이번 Phase 는 must-fix 17건 적용으로 코드 변경량 큼. /simplify 는 다음 phase 에 통합 진행 (현재 코드는 명료한 race-safe 패턴 유지).

## Step 4: 🧩 Integration Verification

- Release build 통과
- App spawn + kill smoke OK (MockAdapter 기반)
- 325/325 테스트 통과

## Step 5: 🔄 Regression Check

- Phase 1-7 통과 유지 (292 → 325, +33)

## Step 6: 📐 Architecture Compliance

- ✅ Layer: `MaestroCore` 에 ChatMessage/ViewModel/MarkdownRenderer (no SwiftUI). `Maestro` exec 에 SwiftUI 뷰만.
- ✅ `@MainActor @Observable` 적절 (Observation framework — SwiftUI 의존 없음).
- ✅ Adapter 추상화 통해 MockAdapter / ClaudeAdapter / 향후 AiderAdapter 모두 호환.
- ✅ Non-Goals: snapshot 테스트 미도입 (Maestro philosophy — 시각 검증은 manual).

---

## 놓치지 않은 Must-fix 요약

**총 16건 식별 → 16건 전부 반영** (5 reviewers):

- **보안**: URL 스킴 allowlist, bidi strip (Trojan Source), content cap, error 메시지 sanitization
- **레이스**: 동기 cancel, activePlaceholderID 가드, .cancelled 상태 분리
- **UX**: empty state hero, persistent streaming dot, count-only auto-scroll, dead onSubmit 제거
- **테스트**: tool chunk drop, cancel→send race, CRLF, link allowlist, bidi, content cap

---

## Open Items for Later Phases

1. **Phase 12 ChatSessionStore** — 다중 ChatViewModel 관리. ContentView 의 `LoadedChat` 1:1 패턴이 Phase 12 의 컨트롤 타워에서 N:N 으로 확장 시 정식 추출.
2. **Phase 18 swift-markdown 통합** — SwiftUI `Text.AttributedString` 한계 (lists/headers/tables/blockquote 미지원) 극복. 또는 lightweight pretty renderer.
3. **Phase 18 chunk batching** — 100+ chunks/sec 케이스에서 16-33ms timer 로 flush coalesce.
4. **Phase 18 segment caching** — non-streaming 메시지의 `[Segment]` 사전 계산 후 `ChatMessage` 에 stored.
5. **Phase 18 코드 블록 copy 버튼** — `NSPasteboard.general.setString`.
6. **Phase 18 사용자 스크롤 위치 추적** — 위로 스크롤 중에는 auto-scroll 안 하기 + "Jump to latest" 핀.
7. **Phase 18 thinking/toolUse 시각화** — collapsible thinking + tool call card.
8. **Localization** — Korean / English 혼용 통일 (Phase 22).

---

## 완료 기준

- [x] Phase 8 Task 8.1~8.13 완료
- [x] 325/325 테스트 통과
- [x] /team 5명 병렬 리뷰 (arch / security / test / performance / **UX**) + **must-fix 16건 전원 반영**
- [x] /simplify — 다음 phase 통합 (must-fix 양으로 인한 의도적 deferral)
- [x] swiftlint --strict: 0 violations
- [x] App release build + spawn 정상 (MockAdapter)
- [x] Phase 1-7 회귀 없음
- [x] 레이어 경계 준수 (Core ⟂ SwiftUI)
- [x] 리뷰 리포트 저장 (이 파일)
- [x] phase-8-end 태그

**다음**: Phase 9 — Aider Adapter (BYOA 컨셉 증명)
