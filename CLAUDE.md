# CLAUDE.md — Maestro 프로젝트

미래의 Claude (혹은 다른 AI 어시스턴트)가 이 프로젝트를 이어받을 때 **이 파일을 먼저 읽는다**.

---

## 🚨 먼저 할 일 (무조건)

```
1. docs/plans/PLAN_maestro.md 전체 읽기 (요약본 말고 전체)
   특히 "🧭 START HERE" 섹션을 가장 먼저
2. docs/reviews/ 디렉토리 훑기 (이전 Phase 리뷰에서 중요 결정 파악)
3. git log --oneline | head -30 (최근 어떤 작업을 했는지)
4. 현재 Phase Status 확인 후 이어서 진행
```

---

## 한 줄 요약

> **Maestro = Claude/Cursor/Aider 같은 서로 다른 AI 코딩 CLI를 한 팀으로 지휘하는 macOS 네이티브 앱.**

## 핵심 3가지 (절대 잊지 말 것)

1. **BYOA (Bring Your Own Agent)** — CLI는 사용자가 직접 설치. 우리는 어댑터만.
2. **사람이 지휘자** — 자율 에이전트 아님. HITL (Human-in-the-loop).
3. **로컬 완결형** — 서버 없음, 클라우드 없음. JSON 파일 + Keychain.

## 절대 하지 말 것

- ❌ PTY를 에이전트 호출에 쓰지 말 것 (사용자용 쉘 탭에만)
- ❌ @멘션 가로채기 방식 구현 금지 (Cmd+K 팔레트로)
- ❌ Claude/Anthropic에 종속되는 설계 금지

## 기술 스택

- **언어**: Swift 6.0+ (Strict Concurrency 활성)
- **UI**: SwiftUI (macOS 14+ 전용)
- **테스트**: XCTest
- **빌드**: Swift Package Manager
- **의존성**: SwiftTerm (쉘 탭), Sparkle (자동 업데이트)
- **스토리지**: JSON/JSONL 파일 + macOS Keychain
- **로깅**: OSLog

## 디렉토리 구조 (목표)

```
Maestro/
├── Package.swift
├── Sources/
│   ├── Maestro/           # executable (앱 진입점)
│   ├── MaestroCore/        # 도메인 로직 (플랫폼 독립)
│   └── MaestroAdapters/    # 에이전트 어댑터 (Claude, Aider, ...)
├── Tests/
│   ├── MaestroCoreTests/
│   ├── MaestroAppTests/
│   ├── MaestroIntegrationTests/
│   └── MaestroUITests/
├── Resources/
└── docs/
    ├── plans/PLAN_maestro.md   ← 계획서 (single source of truth)
    ├── reviews/                ← 각 Phase 완료 후 /team 리뷰 결과
    ├── audits/                 ← a11y 감사 등
    ├── benchmarks/             ← 성능 기준선
    ├── demos/                  ← Milestone 데모 영상/스크린샷
    └── website/                ← 랜딩 페이지 정적 HTML
```

## 데이터 위치

런타임 사용자 데이터: `~/Library/Application Support/Maestro/`

```
├── config.json
├── folders.json                # 폴더 레지스트리
├── agents/<folder-hash>.json   # 폴더별 에이전트 정보
├── inbox/<agent>/              # 받은편지함
├── outbox/<agent>/             # 보낼편지함
├── threads/<thread-id>.jsonl   # 대화 로그
└── logs/
```

API 키/시크릿: **macOS Keychain** (평문 저장 금지)

## 개발 원칙

1. **TDD 엄격히 준수** — Red → Green → Refactor
2. **6단계 Phase Completion Protocol** 모든 Phase에 적용
   - Self / /team / /simplify / Integration / Regression / Architecture
3. **매 Task 완료 시 체크박스 업데이트** (계획서 동기화 정책)
4. **커밋 메시지에 Task 번호 포함** (예: `Task 3.7: Implement FileStore`)
5. **Swift 6 Strict Concurrency** — `Sendable` 준수 (Phase 1부터)
6. **String Catalog 기반 i18n** — 하드코딩 문자열 금지 (Phase 22에서 감사)
7. **커버리지 목표** — 도메인 ≥90%, 앱 ≥75%

## 용어 주의

| ✅ 써도 됨      | ❌ 쓰지 말 것   |
| --------------- | --------------- |
| Agent           | subagent        |
| MessageEnvelope | message (단독)  |
| Adapter         | plugin          |
| Dispatch        | send            |
| Report          | response (단독) |
| Discussion      | debate          |
| Control Tower   | dashboard       |

자세한 Glossary는 `docs/plans/PLAN_maestro.md` 의 "📘 Glossary" 섹션 참조.

## 사용자 (1인)

- **이름**: 김경원 (gimgyeong-won)
- **이메일**: wme1018@gmail.com
- **주 언어**: 한국어 (UI 1차 타겟, 영어는 2차)
- **전작**: ControlKim (`/Users/gimgyeong-won/Desktop/kax/control-kim/`)

## Phase 진행 방식

**M1-M3 (초기 9주)**: 순차 실행 (아키텍처 안정화)
**M4-M5 (중기 5주)**: 부분 병렬 (엔진 + UI 병행 가능)
**M6-M8 (후기 6주)**: 병렬 실행 (독립 트랙 많음)

**리뷰는 Phase 1부터 `/team` 6인 소환** (solo 실행이어도 리뷰는 병렬).

## 테스트/빌드 명령어

```bash
# 빌드
swift build --configuration debug

# 테스트
swift test --parallel
swift test --sanitize=thread           # 스레드 안정성
swift test --enable-code-coverage      # 커버리지

# 린트
swiftlint --strict
swift-format lint --recursive Sources Tests

# UI 테스트 (Xcode 필요)
xcodebuild test -scheme Maestro -destination 'platform=macOS'

# 성능 벤치마크 (Phase 22 이후)
./scripts/bench.sh
```

## 현재 상태 조회

```bash
# Phase 진행 상황
grep -E "P\d+.*✅|🔄" docs/plans/PLAN_maestro.md

# 완료된 리뷰
ls docs/reviews/

# 최근 커밋
git log --oneline | head -20
```

## 다음에 할 일을 찾는 법

1. `docs/plans/PLAN_maestro.md` 열기
2. "Phase 진행 상황" 표 확인 — 현재 🔄 In Progress 인 Phase
3. 해당 Phase의 Tasks 체크박스 확인 — 체크 안 된 가장 위 Task가 다음 할 일
4. TDD 원칙으로 진행 (Red → Green → Refactor)
5. 완료 즉시 체크박스 업데이트 + 커밋

## 막혔을 때

1. 계획서의 해당 Phase "Rollback Strategy" 참조
2. 이전 Phase의 `docs/reviews/phase-N.md` 에서 비슷한 문제 있었는지 검색
3. ControlKim (`/Users/gimgyeong-won/Desktop/kax/control-kim/`) 의 유사 기능 구현 참조
4. Swift 문서: https://docs.swift.org/swift-book/
5. 그래도 안 되면 사용자에게 질문

---

**Golden Rule**: 이 프로젝트의 "What"과 "How"는 계획서에, "Why"와 "배경"은 계획서의 Backstory에 있다. 혼란스러우면 **계획서로 돌아가라**.
