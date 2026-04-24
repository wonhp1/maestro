# Phase 2 Review Report — 도메인 모델

**Date**: 2026-04-25
**Phase**: 2 / 23 (도메인 모델)
**Status**: ✅ Complete
**Duration**: ~4시간 (계획 4-5일 대비 매우 빠름 — 순수 데이터 타입 특성)

---

## Deliverables (Phase 2 최종)

`Sources/MaestroCore/`:

- `Identifiers.swift` — `Identifier<Tag>` phantom 제네릭 + `EnvelopeID`/`ThreadID`/`SessionID`/`AgentID`/`AdapterID` typealiases. 엄격 검증 (path traversal/shell meta/control char 차단).
- `MessageType.swift` — `task`/`question`/`report`/`fyi` enum.
- `MessageEnvelope.swift` — 봉투 + `schemaVersion`/`correlationId`/`deliveryStatus` 신뢰성 필드 + task/report 팩토리 + 불변 업데이트.
- `Session.swift` — `SessionStatus` 상태머신 + `SessionExitCause` (userTerminated/crashed/idleSwept/unspecified).
- `AgentProfile.swift` — **argv 기반 실행 모델** (`InvokeArg`: literal/placeholder). shell 거치지 않음.
- `MessageThread.swift` — 봉투 컬렉션. strict append 만 유지.
- `Discussion.swift` — 상태머신 5개 상태 + 턴 누적 + envelope threadId 검증.
- `JSONCodecs.swift` — `Date.ISO8601FormatStyle` 기반 (Swift 6 완전 Sendable, `nonisolated(unsafe)` 없음).

`Tests/MaestroCoreTests/`: **79/79 통과** (0.008s)

- `IdentifierTests`: 14 케이스 (security 경계 포함)
- `MessageTypeTests`: 3
- `MessageEnvelopeTests`: 8
- `SessionTests`: 10 (전이 매트릭스 전수 + exit cause)
- `AgentProfileTests`: 10 (shell-unsafe input 보존 포함)
- `ThreadTests`: 5
- `DiscussionTests`: 14 (전이 매트릭스 전수 + maxTurns 경계)
- `JSONCodecsTests`: 8 (포맷 불변식 + 날짜 정밀도)
- `AppLaunchTests`+`MainWindowTests`: 7 (Phase 1 regression)

---

## Step 2: 👥 /team Multi-Agent Review (4명 병렬)

### Architecture Reviewer — **Must-fix: 4건, 모두 반영**

1. ❌→✅ `MessageEnvelope` 에 `schemaVersion`/`correlationId`/`deliveryStatus` 추가 (P11 router 대비)
2. ❌→✅ `Session` 에 `exitCause` 추가 (crash vs user-terminated 구분)
3. ❌→✅ `Discussion.recordTurn(from:)` 봉투 threadId 검증
4. ❌→✅ `AgentProfile.invokeTemplate` (String) → `invokeArgs: [InvokeArg]` (argv)

### Security Reviewer — **Must-fix: 2건, 모두 반영**

1. ❌→✅ `Identifier.validated` 엄격화: path traversal (`..`/`/`), control char, null byte, shell meta 전부 차단. 문자 whitelist `[A-Za-z0-9._-]` 1-64자, 선두 `.`/`-` 금지
2. ❌→✅ `AgentProfile` argv 배열로 — shell 인젝션 원천 차단 (Security 지적과 Arch 지적 일치)

Plus 적용한 nice-to-have:

- ❌→✅ `Codable Identifier.init(from:)` 가 이제 `ensureValid` 재검증 (디스크 편집 공격 방어)
- ❌→✅ `Date.ISO8601FormatStyle` 로 `nonisolated(unsafe)` 제거

### Test Quality Reviewer — **Must-fix: 8건, 모두 반영**

1. ❌→✅ `IdentifierError` 값 단언 추가
2. ❌→✅ `Session` no-op (`active→active`, `idle→idle`) + terminal (`terminated→*`) 매트릭스 전수
3. ❌→✅ `Discussion` 전이 매트릭스 전수 (기존 50% → 100%)
4. ❌→✅ `recordTurn` after maxTurns 자동완료 → 다음 턴 거부 검증
5. ❌→✅ `MessageThread.appendStrict` → `append` 로 통합 (non-strict 제거)
6. ❌→✅ JSONCodecsTests 신규: sortedKeys / withoutEscapingSlashes / fractional seconds / fallback
7. ❌→✅ 고정 날짜 사용 (`Date()` 제거)
8. ✅ 중복 Hashable/RawRepresentable 테스트 는 유지 (작은 regression safety net)

### Docs Reviewer — **Must-fix: 4건, 모두 반영**

1. ❌→✅ `MessageEnvelope.swift` 에 "Envelope Protocol" 파일 레벨 doc 추가
2. ❌→✅ `expectReply` 관례 문서화 (`task/question`→true, `report/fyi`→false)
3. ❌→✅ Glossary: `Thread (구현체: MessageThread)` 로 명시
4. ❌→✅ `Session` `Discussion` `MessageEnvelope` 에 forward pointer 주석 (Phase N 소비)

---

## Step 3: ✨ /simplify

- `AgentProfile.renderInvokeCommand` 의 dead-code `reduce` 블록 제거
- `Session.canTransition` switch 에서 redundant `default` 제거 (exhaustive)

## Step 4: 🧩 Integration Verification

- `swift build`: 성공 (0.07s 후 캐시)
- `swift run Maestro`: 창 유지 확인
- Phase 1 회귀 없음

## Step 5: 🔄 Regression Check

- Phase 1 `AppLaunchTests` (4) + `MainWindowTests` (3) 여전히 통과
- 새로 추가된 `testAppBundleIdentifierPinnedValue`, `testMacOSVersionInvariantMatchesPackageDeclaration` 유지
- 전체 79개 중 Phase 1 소속 7개 통과

## Step 6: 📐 Architecture Compliance

- ✅ 레이어 경계 유지 (MaestroCore 단독 빌드됨, 앱/어댑터 의존성 없음)
- ✅ Swift 6 Strict Concurrency 전 타겟 (Sendable 100%, `nonisolated(unsafe)` 0건)
- ✅ Non-Goals 준수 (PTY 없음, 가로채기 없음, 벤더 중립)
- ✅ 신규 도메인 타입 모두 `Hashable + Codable + Sendable`
- ✅ Phantom-typed ID 5종으로 타입 혼용 컴파일 타임 차단

---

## Metrics

| 항목                  | 값                      |
| --------------------- | ----------------------- |
| 테스트 수             | 55 → 79 (+24)           |
| 테스트 통과율         | 100% (79/79)            |
| 테스트 실행 시간      | 0.008s                  |
| 도메인 파일           | 8개 (~550 LOC 프로덕션) |
| 외부 의존성           | 0                       |
| `nonisolated(unsafe)` | 0                       |

---

## Learnings

- **Swift 6 Strict Concurrency 에서 `ISO8601DateFormatter` 는 Sendable 불친화.** `Date.ISO8601FormatStyle` (값 타입) 가 정답 — 훨씬 깔끔.
- **Date roundtrip 은 부동소수점 드리프트 주의.** 밀리초 정밀도로 저장 + 정수 초 고정 date 를 테스트에 쓰거나 `accuracy:` 허용 오차 명시.
- **Argv 배열 vs 문자열 템플릿** — 보안/아키텍처 관점 모두에서 argv 가 우수. 초기 설계 실수였으나 Phase 2 말에 바로잡음.
- **Phantom types 5종 (Envelope/Thread/Session/Agent/Adapter)** 은 과하지 않음. Adapter 가 Session 과 별개로 경계를 자주 넘어서 정당.
- **/team 병렬 리뷰의 가치**: Architecture / Security / Test / Docs 각자 완전히 다른 군집의 must-fix 를 독립적으로 식별. 한 명으론 모두 못 잡았을 18건.

---

## Open Questions for Later Phases

1. **MessageThread vs Discussion 관계** — Architecture 리뷰에서 지적. 현재 Discussion 은 DiscussionTurn 배열을 갖고 실제 envelope 는 MessageThread 에 별도 저장. Phase 11 (router) 또는 Phase 14 (discussion engine) 에서 composition 으로 통합할지, 분리 유지할지 결정.
2. **`MessageEnvelope.to: AgentID` 단수 vs N-party 토론** — Phase 14 에서 broadcast 필요 시 `recipients: [AgentID]` 확장 여부 결정.
3. **`MessageType.fyi` + `expectReply`** 상관관계 — type 에서 기본값 파생 vs 명시 전달. 현재는 관례 (문서화), 필요시 Phase 11 에서 enforce.
4. **Schema migration 프레임워크** (Phase 23) — `schemaVersion=1` 유지, 변경 시 `Migrator` 체인 실행.
5. **Session.folderPath canonicalize** — Phase 4 에서 읽을 때 sandbox container 확인 필수 (Security 리뷰 지적).

---

## Phase 2 완료 기준 확인

- [x] 모든 Task 완료 (2.6~2.15)
- [x] 79/79 테스트 통과
- [x] /team 4명 병렬 리뷰 + 18 must-fix 전원 반영
- [x] Integration / Regression / Architecture 통과
- [x] 리뷰 리포트 저장 (이 파일)
- [x] Next: git 커밋 + phase-2-end 태그

**다음 Phase**: Phase 3 — 파일 영속성 레이어 + Keychain
