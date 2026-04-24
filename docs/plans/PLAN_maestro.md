# Implementation Plan: Maestro — AI 코딩 에이전트 공용 지휘소

**Status**: ⏳ Planned
**Started**: 2026-04-25
**Last Updated**: 2026-04-25
**Estimated Completion**: 2026-09-12 (20주 / 약 5개월)
**Platform**: macOS 14+ (Sonoma 이상)
**Tech Stack**: SwiftUI + Swift 6.0 (Strict Concurrency) + XCTest

---

## 🧭 START HERE — 컨텍스트 복구용 (필독)

**이 문서를 처음 열었거나, 한참 후에 다시 연 사람은 여기부터 읽는다.**

### 한 문장 요약

> **Maestro는 Claude/Cursor/Aider 같은 서로 다른 AI 코딩 CLI 에이전트들을 "한 팀"으로 지휘하는 macOS 네이티브 앱이다. 사용자(당신)가 지휘봉을 쥐고, 에이전트들은 팀원처럼 역할 분담하고 서로 보고하고 토론한다.**

### 핵심 3가지 (절대 잊으면 안 되는 것)

1. **BYOA (Bring Your Own Agent)** — Maestro는 CLI를 번들링하지 않음. 사용자가 `brew install claude` / `pip install aider` 등으로 직접 설치. Maestro는 "어댑터" 만 제공해서 감지 + 호출.

2. **사람이 지휘자** — 자율 에이전트 패턴 아님. 사용자가 "@cpo 보고해" 지시 → CPO 수행 → CPO가 control에 보고. 자동 실행 없음, 모든 초기 지시는 사람에게서.

3. **로컬 완결형** — 서버 없음, 클라우드 동기화 없음, 외부 텔레메트리 없음. 모든 데이터는 `~/Library/Application Support/Maestro/` JSON/JSONL 파일. Keychain에 시크릿만.

### 절대 하지 말 것 (Non-Goals 상위 3개)

- ❌ **PTY를 에이전트 호출에 쓰지 말 것** — Process + Pipe로 headless. PTY는 사용자용 쉘 탭에만.
- ❌ **가로채기 방식으로 @멘션 구현하지 말 것** — 명시적 Cmd+K 팔레트 or 별도 입력창으로.
- ❌ **Claude/Anthropic에 종속되지 말 것** — 어떤 결정도 "다른 에이전트도 OK여야 함" 원칙 통과해야.

### 컨텍스트 복구 단계별 읽기 순서

```
1️⃣ (5분)  이 "START HERE" 섹션 전체
2️⃣ (5분)  📖 Backstory 섹션 — 여기까지 어떻게 왔나
3️⃣ (5분)  🎯 Vision & Goals 섹션
4️⃣ (10분) 🏗️ Architecture Decisions 표 — 왜 각 결정이 있는가
5️⃣ (5분)  🚫 Non-Goals — 절대 하면 안 되는 것
6️⃣ (10분) 📘 Glossary — 프로젝트 전용 용어
7️⃣ (?)   📊 Progress Tracking — 지금 어디까지 왔는가
8️⃣ (?)   현재 Phase로 이동 → Tasks 이어서 진행
```

### "지금 어디까지 했지?" 빠른 체크

```bash
# 이 명령으로 현재 상태 즉시 파악
grep -E "^\*\*Status\*\*:" docs/plans/PLAN_maestro.md       # 전체 상태
grep -E "P\d+.*✅|🔄" docs/plans/PLAN_maestro.md             # 완료된 Phase
ls docs/reviews/                                              # 리뷰 끝난 Phase
git log --oneline | head -20                                  # 최근 커밋 → 어떤 Task 했는지
```

### 미래 AI 어시스턴트에게 (예: 새 Claude 세션)

당신이 Claude (혹은 다른 AI)로 이 계획을 이어받았다면:

1. **먼저 이 계획서를 full read** 하세요. 요약본 말고 전체.
2. **`docs/reviews/` 디렉토리 훑기** — 이전 Phase 리뷰에서 주요 결정/문제 파악.
3. **Decisions Log 섹션 확인** — 계획 수정 이력.
4. **`git log` 최근 30개 확인** — 실제 어떤 작업이 진행되었는가.
5. **Phase 진행 상황 표** 확인 — 어느 Phase가 `✅`고 어느 게 `🔄`인가.
6. **현재 Phase의 Tasks 체크박스** — 체크 안 된 가장 위 Task가 다음 할 일.
7. **⚠️ 절대로** 가장 위에 있는 "절대 하지 말 것" 3가지 위반 금지.

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

## 🧭 Micro-Task Progress Policy (매 작업마다 필수)

**"한 작업이 끝나면 즉시 계획서와 체크리스트를 본다."** 이것은 선택이 아닌 필수 습관이다.

### 왜 필요한가

- 14개 Phase × 평균 10개 Task = **200+ 세부 작업**. 진척도 잃으면 프로젝트 표류
- /team 리뷰가 어디까지 진행됐는지, 무엇이 남았는지 즉시 파악
- 중단 후 재개할 때 **"어디부터 다시"** 를 즉각 복원

### Task 완료 사이클 (매 미시 작업마다 반복)

```
1. 작업 시작
   └─ 계획서에서 해당 Task 확인 (Phase N, Task N.M)

2. 작업 수행
   └─ TDD: Red → Green → Refactor

3. 작업 완료 직후 (30초 이내)
   ├─ ✅ 계획서의 해당 [ ] 체크박스 → [x]
   ├─ 📝 커밋 메시지에 "Task N.M: <설명>" 포함
   └─ 🔍 같은 Phase 내 남은 Task 수 확인 (멘탈 모델 유지)

4. Phase의 모든 Task 완료 시
   ├─ Phase Completion Protocol 6단계 시작
   ├─ 각 Step 완료 시 해당 체크박스 업데이트
   └─ Phase별 리뷰 트래커 표 해당 행 업데이트

5. Phase 완료 시 (Quality Gate 통과)
   ├─ Phase Status: ⏳ Pending → ✅ Complete
   ├─ "Last Updated" 날짜 갱신
   ├─ Time Tracking 표에 실제 소요 시간 기록
   ├─ Notes & Learnings 섹션에 깨달음 1-2줄 기록
   └─ docs/reviews/phase-N.md 저장

6. Milestone 완료 시
   ├─ Milestone 진행 상황 표 업데이트
   ├─ 데모 녹화 또는 스크린샷 (docs/demos/)
   └─ 본인/팀에게 공유
```

### 체크 주기 알람

Git pre-commit hook으로 강제:

```bash
# .git/hooks/pre-commit
#!/bin/sh
# 최근 커밋에 Task 참조 없으면 경고
grep -qE "Task [0-9]+\.[0-9]+" <(git diff --cached --name-only) || \
  echo "⚠️  WARN: 커밋에 Task 참조 없음. 계획서 체크리스트 업데이트 잊지 마세요."
```

### "체크하지 않은 것은 없는 것" 원칙

- Task 끝냈는데 체크박스 업데이트 안 함 → **존재하지 않는 것으로 간주**
- 다음 Phase 시작 시 **이전 Phase 트래커에 빈칸 있으면 새 Phase 시작 금지**
- Quality Gate 6단계 중 하나라도 체크 없으면 **해당 Phase 미완료**

### Daily Sync (본인이 1인이든 팀이든)

매일 작업 시작/종료 시:

- [ ] 계획서 열어서 **현재 Phase Status** 확인
- [ ] 오늘 목표 Task 1-3개 선정
- [ ] 어제의 Task 체크박스 업데이트 여부 확인
- [ ] 트래커 테이블에서 뒤처진 리뷰 항목 있는지 점검

---

## 🔬 Phase Completion Protocol (모든 Phase 공통)

각 Phase는 Quality Gate 통과 전 **6단계 리뷰 & 검증**을 반드시 거친다. 테스트 통과만으로는 불충분 — 코드 품질, 여러 관점의 검토, 시스템 건강성까지 확인.

각 Phase의 Quality Gate 하단 `🔬 Review & Verification` 섹션에서 이 6단계 체크리스트를 모두 통과해야 다음 Phase 진행 가능.

### Step 1: 🔍 Self Code Review (solo)

자신이 쓴 코드를 다른 사람 코드처럼 재검토. 가장 먼저, 가장 빠르게.

- [ ] 모든 신규 파일을 처음 보는 것처럼 다시 읽었는가
- [ ] 변수/함수 이름이 의도를 명확히 표현하는가
- [ ] 불필요한 추상화/일반화 없는가 (YAGNI 원칙)
- [ ] 에러 처리가 경계(사용자 입력, 외부 시스템)에만 있는가
- [ ] 주석이 WHY에만 달려있고 WHAT에 달려있지 않은가
- [ ] 중복 로직이 있으면 적절히 추출했는가 (DRY)
- [ ] Git 커밋 메시지가 설명적인가 (의도 기술)
- [ ] 매직 넘버/문자열이 상수로 빠졌는가

### Step 2: 👥 /team Multi-Agent Review (parallel specialized reviewers)

`/team` 스킬로 **전문 리뷰어 에이전트 팀을 병렬 실행**하여 여러 관점에서 동시에 코드 검토. Self Review로는 놓칠 부분을 잡는 핵심 단계.

**실행 방법**: Phase 완료 후 `/team` 스킬 실행, 아래 리뷰어 팀 구성.

팀 멤버 (각자 독립 프롬프트, 병렬 실행):

| 리뷰어                          | 역할          | 검토 포커스                                              |
| ------------------------------- | ------------- | -------------------------------------------------------- |
| 🏛️ **architecture-reviewer**    | 아키텍처 감사 | 레이어 경계, SOLID, 프로토콜 준수, 결합도                |
| 🔒 **security-reviewer**        | 보안 감사     | 시크릿 노출, 입력 검증, Keychain 사용, 샌드박스          |
| ⚡ **performance-reviewer**     | 성능 감사     | 불필요 재렌더링, I/O 병목, 메모리 누수, 알고리즘         |
| 🧪 **test-quality-reviewer**    | 테스트 품질   | 커버리지 공백, 엣지 케이스 누락, flaky 가능성, mock 남용 |
| 🎨 **ux-reviewer** (UI Phase만) | UX/접근성     | VoiceOver, 다크모드, 키보드 내비, 에러 메시지            |
| 📖 **docs-reviewer**            | 문서/주석     | DocC 누락, README 갱신, API 시그니처 문서화              |

**체크리스트**:

- [ ] `/team` 실행하여 해당 Phase 변경사항 리뷰 지시
- [ ] 각 리뷰어로부터 독립적인 리포트 수집
- [ ] 리포트를 종합하여 **치명적(must-fix) / 권고(nice-to-have) / 논의(discuss)** 로 분류
- [ ] Must-fix 항목 **모두** 해결
- [ ] Nice-to-have 항목 판단하여 반영 또는 TODO 이슈로 기록
- [ ] Discuss 항목 Notes & Learnings 섹션에 기록
- [ ] 리뷰 결과 JSON/Markdown을 `docs/reviews/phase-N.md`에 보관

**/team 실행 예시 프롬프트**:

```
Phase N 완료. 다음 변경사항을 병렬 리뷰해주세요.
- 변경 파일 목록: [git diff --name-only phase-N-start..HEAD]
- 이번 Phase 목표: [Phase Goal 복붙]
- Architecture Decisions: docs/plans/PLAN_maestro.md 참조

팀:
  1. architecture-reviewer: 아키텍처 준수 감사
  2. security-reviewer: 보안 취약점 스캔
  3. performance-reviewer: 성능 위험 요소 분석
  4. test-quality-reviewer: 테스트 품질 평가
  5. (UI Phase면) ux-reviewer 추가
  6. docs-reviewer: 문서/주석 완결성

각자 독립적으로 must-fix / nice-to-have / discuss 분류하여 보고.
```

### Step 3: ✨ /simplify Skill Review

`/simplify` 스킬 실행하여 코드 단순화 기회를 기계적으로 스캔. /team이 "옳음"을 보장한다면 /simplify는 "간결함"을 보장.

- [ ] 해당 Phase의 diff에 대해 `/simplify` 실행
- [ ] 제안된 단순화 중 합리적인 것 모두 반영
- [ ] 재사용 가능한 유틸리티가 있으면 공통 모듈로 추출
- [ ] 과도한 방어 코드/조기 최적화 제거
- [ ] 실행 후 모든 테스트가 여전히 통과하는지 확인
- [ ] simplify 결과를 Notes & Learnings 섹션에 기록

### Step 4: 🧩 Integration Verification

단위 테스트를 넘어 end-to-end 동작 검증.

- [ ] 이전 Phase의 기능과 새 기능이 **함께** 동작하는지
- [ ] 실제 사용 시나리오 1개 이상 수동 실행
- [ ] UI가 있으면 Xcode에서 앱을 실제 실행하여 확인
- [ ] Console.app 로그에 예상치 못한 경고/에러 없는지
- [ ] 메모리 사용량 비정상 증가 없는지 (Instruments)
- [ ] 체감 가능한 성능 저하 없는지

### Step 5: 🔄 Regression Check

이전 Phase 산출물이 깨지지 않았는지 확인.

- [ ] 전체 테스트 스위트 재실행 (`swift test`)
- [ ] 이전 Phase Quality Gate의 Manual Test 랜덤 1-2개 재실행
- [ ] 기존 기능의 성능 벤치마크 유지 (있다면)
- [ ] 빌드 시간이 크게 늘지 않았는지 (이전 대비 +20% 이내)
- [ ] 이전 Phase에서 작성한 테스트 여전히 통과

### Step 6: 📐 Architecture Compliance

Architecture Decisions 섹션 기준 준수 확인.

- [ ] 결정한 아키텍처 원칙 위반 없는가
- [ ] 신규 의존성이 "Dependencies" 섹션에 문서화되었는가
- [ ] 레이어 경계 지켜졌는가 (`MaestroCore` → `Maestro` 단방향)
- [ ] Non-Goals 영역 침범하지 않았는가
- [ ] Decisions Log에 중요 결정 기록되었는가

### Phase별 리뷰 트래커

각 Phase 완료 시 아래 표의 해당 행에 체크 표시. 6단계 모두 통과해야 해당 Phase "Complete" 로 마킹 가능.

| Phase | 🔍 Self | 👥 /team | ✨ /simplify | 🧩 Integration | 🔄 Regression | 📐 Arch | 리뷰 리포트                                      |
| ----- | :-----: | :------: | :----------: | :------------: | :-----------: | :-----: | :----------------------------------------------- |
| P1    |   ✅    |    ✅    |      ✅      |       ✅       |      ✅       |   ✅    | [docs/reviews/phase-1.md](../reviews/phase-1.md) |
| P2    |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-2.md                          |
| P3    |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-3.md                          |
| P4    |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-4.md                          |
| P5    |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-5.md                          |
| P6    |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-6.md                          |
| P7    |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-7.md                          |
| P8    |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-8.md                          |
| P9    |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-9.md                          |
| P10   |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-10.md                         |
| P11   |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-11.md                         |
| P12   |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-12.md                         |
| P13   |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-13.md                         |
| P14   |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-14.md                         |
| P15   |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-15.md                         |
| P16   |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-16.md                         |
| P17   |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-17.md                         |
| P18   |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-18.md                         |
| P19   |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-19.md                         |
| P20   |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-20.md                         |
| P21   |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-21.md                         |
| P22   |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-22.md                         |
| P23   |    ☐    |    ☐     |      ☐       |       ☐        |       ☐       |    ☐    | docs/reviews/phase-23.md                         |

### Phase 완료 순서 (권장)

```
코드 작성 → 테스트 통과
    ↓
Step 1: Self Review (10-20분)
    ↓
Step 2: /team Review (30-60분, 병렬이라 벽시계 시간 짧음)
    ↓ must-fix 반영
Step 3: /simplify (15-30분)
    ↓ 단순화 반영
Step 4: Integration (10-30분, 수동)
    ↓
Step 5: Regression (5분, 자동 테스트)
    ↓
Step 6: Architecture Compliance (5-10분, 체크리스트)
    ↓
docs/reviews/phase-N.md 저장
    ↓
위 트래커 표 해당 행 모두 체크
    ↓
✅ Phase Complete → 다음 Phase 시작
```

---

## 🧑‍🎼 Execution Strategy (권장 실행 전략)

**"시기별로 다른 방식"** — 초반 순차 → 중반 부분 병렬 → 후반 완전 병렬. 리뷰는 처음부터 끝까지 `/team` 병렬.

### 시기별 가이드

```
┌────────────────┬──────────────┬─────────────────────────────────┐
│  구간          │   실행       │   리뷰                          │
├────────────────┼──────────────┼─────────────────────────────────┤
│ M1-M3 (P1-P10) │ 🔴 순차      │ 🟢 /team 6인 (첫 Phase부터)     │
│                │ (9주)        │                                  │
├────────────────┼──────────────┼─────────────────────────────────┤
│ M4-M5 (P11-P15)│ 🟡 부분 병렬 │ 🟢 /team 6인 + 통합 리뷰 1회 추가│
│                │ (5주)        │                                  │
├────────────────┼──────────────┼─────────────────────────────────┤
│ M6-M8 (P16-P23)│ 🟢 병렬      │ 🟢 중첩 /team (executor + review)│
│                │ (6주)        │                                  │
└────────────────┴──────────────┴─────────────────────────────────┘
```

### 왜 초기는 순차인가

- **아키텍처 DNA가 확정되는 시기** — 한번 정한 패턴이 23 Phase 전체에 전파됨
- P2(도메인) → P3(영속성) → P4(어댑터) 강한 의존성 체인
- 병렬화가 오히려 Git 충돌과 스타일 드리프트 유발
- 첫 5 Phase는 직접 쌓아야 "뭐가 어떻게 돌아가는지" 체감 가능

### 왜 후기는 병렬 가능한가

- 코어 인프라 완성 후 **독립 트랙** 많음
- P16(Cmd+K) ↔ P18(메뉴) ↔ P19(설정) 서로 영향 없음
- P22 내부에서도 i18n / a11y / 성능벤치 3개 병렬화 가능

### 🔄 재평가 체크포인트 (Phase 6-7)

Phase 6-7 완료 시점에 다음 질문으로 방식 재검토:

- [ ] 아키텍처 패턴이 안정됐는가? (어댑터 프로토콜 변경 없어짐?)
- [ ] 코드베이스 탐색이 익숙해졌는가?
- [ ] 병렬 실행 시 충돌 가능성 판단 가능해졌는가?

모두 YES면 Phase 11부터 부분 병렬 전환. NO면 Phase 11도 순차 유지.

### 🎭 중첩 /team 패턴 (후기 Phase용)

```
       🎼 사용자 (메인 오케스트레이터)
                │
        /team 외부 (실행 레이어)
       ┌────────┼────────┬────────┐
       ▼        ▼        ▼        ▼
   Executor  Executor  Executor  Executor
   Phase 16  Phase 17  Phase 18  Phase 19
       │        │        │        │
       └────────┴────────┴────────┘
            각 Phase 완료
                │
        /team 내부 (리뷰 레이어, 병렬)
       ┌────┬────┬────┬────┬────┐
       ▼    ▼    ▼    ▼    ▼    ▼
     arch  sec perf test  ux  docs
       └────┴────┴────┴────┴────┘
            6명의 독립 리뷰
                │
           must-fix 반영
                │
     📋 docs/reviews/phase-N.md 저장
```

**외부 /team (실행용)과 내부 /team (리뷰용)은 완전히 독립**. 동시에 최대 4 executor × 6 reviewer = 28 에이전트 활동 가능.

### ⚠️ 병렬 실행 시 주의 사항

| 위험                              | 대책                                                              |
| --------------------------------- | ----------------------------------------------------------------- |
| **Git 머지 충돌**                 | Phase별 git worktree 분리 (`isolation: "worktree"`)               |
| **컨텍스트 윈도우 포화**          | 리뷰어에게 diff만 전달, 전체 코드베이스 금지                      |
| **스타일/네이밍 드리프트**        | 병렬 완료 후 **통합 리뷰 1회** 추가 (전체 diff → 1인 수석 리뷰어) |
| **테스트 격리 깨짐**              | 각 executor가 자기 테스트만 수정, 공유 mock 변경은 사전 합의      |
| **에이전트 간 아키텍처 드리프트** | 매일 아침 Integration Check (Main에 rebase + 전체 테스트)         |

### 📅 하루 리듬 (권장)

```
🌅 오전 시작:
  1. 계획서 열어서 현재 Phase Status + Daily Sync 체크리스트 확인
  2. 오늘 목표 Task 1-3개 선정 (Phase의 남은 체크박스 중)
  3. (병렬 시기면) 오늘 실행할 병렬 트랙 결정

🌞 집중 작업 세션 (3-4시간):
  1. TDD Red → Green → Refactor
  2. Task 완료마다 체크박스 업데이트 + 커밋 (Task N.M 참조)
  3. 한 Phase 끝나면 즉시 /team 리뷰 6인 소환 (병렬)

🌇 오후 리뷰 세션:
  1. /team 리뷰 결과 수집 → must-fix 반영
  2. Integration Verification (실제 앱 실행)
  3. docs/reviews/phase-N.md 저장
  4. Phase별 리뷰 트래커 체크

🌙 종료 전:
  1. 오늘 진행 상황 Notes & Learnings에 2줄 기록
  2. 다음 작업 준비 (내일 첫 Task 선정)
  3. git push
```

### 📊 추적 지표

매 Milestone 종료 시 자가 평가:

- ✅ **계획 대비 실제 시간** (Time Tracking 표 갱신)
- ✅ **리뷰 커버리지** (Phase별 트래커 완료율)
- ✅ **Must-fix 반영률** (제안 대비 수용)
- ✅ **기술 부채 증가량** (TODO/FIXME 수)
- ✅ **데모 가능 상태** (매 Milestone 종료 시 1분 영상)

---

## 📖 Backstory — 여기까지 어떻게 왔나

### 출발점: ControlKim (v0 프로토타입)

2026년 초, 사용자(`gimgyeong-won`)는 **ControlKim** 이라는 Next.js 기반 웹앱을 만들었음. 위치: `/Users/gimgyeong-won/Desktop/kax/control-kim/`.

핵심 아이디어는 **"폴더마다 Claude 세션 하나, 웹 터미널(xterm.js)로 상호작용, 컨트롤 타워로 @멘션 라우팅"**. 동작하는 프로토타입이었지만 몇 가지 한계 발견:

1. **@멘션 가로채기가 불안정** — xterm 에코 버퍼 파싱, 한글 IME 깨짐, Claude TUI와 충돌
2. **Next.js 서버 스핀업 시간** — 앱 실행마다 2-10초 콜드스타트
3. **Claude 종속적** — Cursor, Aider 같은 다른 에이전트 참여 불가
4. **웹앱 느낌** — Electron으로 감싸도 결국 Chromium in app

### 진화 과정 (대화를 통한 설계 결정)

사용자와 Claude의 장시간 대화에서 하나씩 결정이 내려짐:

| 단계 | 질문                            | 결론                                                            |
| ---- | ------------------------------- | --------------------------------------------------------------- |
| 1    | 현재 구조 분석은?               | 기술적으로 동작하나 SSE 폭발/IME 취약성 존재                    |
| 2    | 프레임워크 대안?                | Letta 가깝지만 여전히 한 에이전트 중심                          |
| 3    | 내 설계에 맞는 프레임워크는?    | **없음** — BYOA 공용 지휘소는 빈 포지션                         |
| 4    | 터미널을 하나로 묶을 수 없나?   | 폴더별 쉘 + Claude 탭 병행, 스플릿 뷰                           |
| 5    | @멘션 가로채기 제거?            | Cmd+K 팔레트로 명시적 전송 전환                                 |
| 6    | Claude 외 다른 에이전트도?      | Adapter 패턴으로 CLI 프로파일화                                 |
| 7    | 양방향 보고 루프?               | Message Envelope 프로토콜 (inbox/outbox/threads)                |
| 8    | PTY 없이 슬래시 명령어?         | `claude -p` headless + 파일 스캔 자동 탐색                      |
| 9    | 네이티브 앱으로?                | 처음엔 Electron 최적화, 최종 **SwiftUI 결정**                   |
| 10   | 클로드 데스크탑에 붙일 수 없나? | Anthropic 앱은 클로즈드. **"닮은 앱"을 직접 만드는 것**         |
| 11   | 다른 코딩 에이전트도?           | **이게 핵심 해자** — 벤더 중립 (Letta/Cursor/Anthropic 못 만듦) |
| 12   | 프로젝트 이름?                  | **Maestro** — 오케스트라 지휘자 비유                            |

### ControlKim에서 배운 교훈 (Maestro에 반영됨)

| 교훈                                   | Maestro 반영                                           |
| -------------------------------------- | ------------------------------------------------------ |
| PTY 에코 버퍼 파싱은 지옥              | PTY는 사용자용 쉘 탭에만, 에이전트는 Process + Pipe    |
| Next.js 서버는 데스크톱 앱에 과잉      | SwiftUI 네이티브 (서버 없음, IPC 불필요)               |
| @멘션 가로채기 = 사용자 혼란           | Cmd+K 팔레트로 명시적 전송                             |
| xterm.js의 TUI를 재구현하려 하지 말 것 | headless JSON 응답 + 자체 UI 렌더링                    |
| JSON 파일 기반 저장은 의외로 잘 됨     | 그대로 유지 (`~/Library/Application Support/Maestro/`) |
| 한 Claude 세션에 올인 = 벤더 락인      | Adapter 패턴으로 BYOA                                  |
| 그래프/토론 기능은 매력적이고 유효함   | 유지 & 강화                                            |
| 사용자가 지휘자 역할을 원함            | 자율 에이전트 패턴 거부, HITL 유지                     |

### 왜 "새 프로젝트"인가 (ControlKim을 왜 계승 안 하나)

**유지보수 리팩토링보다 재설계가 더 효율적인 케이스**:

1. 아키텍처 DNA 자체가 다름 (Claude 전용 → 벤더 중립)
2. 기술 스택 완전 교체 (Next.js/React → SwiftUI/Swift)
3. PTY 중심 → Process 중심 패러다임 전환
4. Electron → 네이티브
5. 이름/브랜딩도 새 카테고리에 맞게 변경 필요

**ControlKim은 "레퍼런스 구현"으로 보존**. 구현 패턴 참고용으로 유용하지만 직접 마이그레이션은 안 함.

---

## 📘 Glossary — Maestro 전용 용어

미래의 당신(or AI)이 용어로 혼란스럽지 않도록 핵심 어휘 정리.

| 용어                              | 의미                                                                                                       | 같이 안 쓰는 것                              |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| **Agent** (에이전트)              | 특정 폴더에 배정된 AI CLI 세션 인스턴스. 이름(예: `cpo`, `ai-news`) + 어댑터(예: Claude) + 세션 ID 를 가짐 | "subagent" — 우리는 이 용어 안 씀            |
| **Adapter**                       | 특정 CLI(claude/aider/gemini...)와 통신하는 Swift 모듈. `AgentAdapter` 프로토콜 구현체                     | "plugin" — 기능이 아니라 "번역기"에 가까움   |
| **Session**                       | 한 에이전트의 지속적 대화 맥락. CLI가 제공하는 `session_id` 와 매핑                                        | -                                            |
| **MessageEnvelope**               | 에이전트 간 주고받는 "편지". `from/to/threadId/body/inReplyTo` 필드                                        | "message" 단독으론 안 씀 — 항상 "envelope"   |
| **Thread**                        | 연관된 envelope 들의 묶음. JSONL로 `threads/<id>.jsonl` 에 저장                                            | "conversation" — UI에서만 표기용             |
| **Discussion**                    | 3명 이상 에이전트가 한 주제로 턴 주고받는 구조화 대화. Thread의 특수형                                     | "debate" — 같은 의미로 쓰지 않음             |
| **Moderator**                     | 토론에서 다음 발언자 결정하는 역할. `ModeratorStrategy` 프로토콜                                           | -                                            |
| **Control Tower** (컨트롤 타워)   | 메인 UI — 사용자가 지시 내리고 보고 받는 공간. 특별한 "control" 에이전트가 여기 상주                       | "dashboard" — 단순 표시가 아닌 상호작용 공간 |
| **BYOA** (Bring Your Own Agent)   | 사용자가 CLI를 직접 설치. Maestro는 번들링 안 함                                                           | -                                            |
| **Inbox / Outbox**                | 각 에이전트의 받은편지함 / 보낼편지함 디렉토리. 파일 기반 메시지 큐                                        | -                                            |
| **Dispatch**                      | control → agent 로 메시지 전송하는 액션                                                                    | "send" — 기술적 의미가 약함                  |
| **Relay**                         | A → B → C 로 메시지 전달되는 체인                                                                          | -                                            |
| **Report**                        | agent → control 로 돌아오는 응답. `replyTo` 필드로 라우팅                                                  | "response" — 일반 대화 응답은 report 아님    |
| **Headless**                      | PTY 없이 `claude -p` 처럼 one-shot CLI 실행                                                                | "background" — 혼동됨                        |
| **Shell Tab**                     | 사용자가 직접 쉘 명령 쓰는 탭 (SwiftTerm 기반). **PTY 유일 사용처**                                        | -                                            |
| **Slash Command** (슬래시 명령어) | `/review`, `/deploy` 같은 사용자 정의 단축 명령. 파일 스캔 + `/help` 프로빙으로 자동 탐색                  | "shortcut" — 다른 의미                       |
| **CLI Detection** (CLI 감지)      | 시스템 PATH에서 `claude`/`aider` 실행파일 찾기 + 버전 파싱                                                 | -                                            |
| **Phase**                         | 계획서의 실행 단위 (23개). 각 Phase = 1-7일 분량                                                           | "sprint" — 애자일 용어 회피                  |
| **Milestone**                     | Phase 묶음 (8개). 각 Milestone = 데모 가능 상태                                                            | -                                            |
| **Quality Gate**                  | Phase 완료 전 통과해야 할 검증 관문                                                                        | -                                            |
| **6단계 Review**                  | Self → /team → /simplify → Integration → Regression → Architecture                                         | -                                            |
| **/team 리뷰어**                  | architecture / security / performance / test-quality / ux / docs (+ a11y/legal 특수)                       | -                                            |
| **Phase Completion Protocol**     | 6단계 리뷰 정의 섹션. 모든 Phase의 Quality Gate 하단에 참조                                                | -                                            |
| **Envelope Protocol**             | 메시지 전달의 파일 기반 규약. inbox/outbox/threads 트리플                                                  | "MCP" — 관련 없음, 별개 개념                 |
| **Schema Version**                | 데이터 파일 포맷의 버전. `Migrator` 체인으로 업그레이드                                                    | -                                            |

---

## 🎯 Vision & Goals

### One-line Vision

> **"AI 코딩 에이전트들이 함께 일하는 네이티브 지휘소"** — 벤더 중립, 로컬 우선, 사람이 지휘하는 멀티 에이전트 워크스페이스.

### Why This Exists

현재 AI 도구 생태계는 **벤더 종속적**. Claude Desktop은 Claude만, Cursor는 Cursor만, Aider는 Aider만. 사용자는 **어느 한 도구의 세계**에 갇힘.

Maestro는 이 문제를 해결:

- **BYOA (Bring Your Own Agent)**: 사용자가 설치한 어떤 CLI 에이전트든 "팀원"으로 영입
- **사람 지휘 + AI 실행**: 자율 에이전트 아닌, 사람이 조율하는 오케스트라 모델
- **폴더 = 영속 인격**: 각 에이전트는 장기 기억을 유지하는 독립 개체
- **로컬 우선**: 클라우드 의존 없음, 파일시스템이 DB

### Success Criteria

- [ ] Claude, Aider 등 **최소 2개 벤더**의 CLI가 한 UI 안에서 함께 작동
- [ ] 에이전트끼리 **지시 → 수행 → 보고** 왕복 루프 동작
- [ ] **3명 이상의 에이전트가 참여하는 토론** (서로 다른 벤더 섞기 가능)
- [ ] **즉각 실행** (서버 스핀업 없이 1초 이내 UI 표시)
- [ ] **네이티브 macOS 경험** (메뉴바, 단축키, 알림 통합)
- [ ] **Keychain 기반 안전한 시크릿 저장** (API 키 평문 ❌)
- [ ] **자동 업데이트** (Sparkle 프레임워크 통합)
- [ ] **모든 사용자 데이터가 로컬 파일** (`~/Library/Application Support/Maestro/`)
- [ ] **슬래시 명령어 자동 탐색** (CLI 업데이트 시 즉시 반영)
- [ ] **테스트 커버리지 ≥80%** (도메인 로직)
- [ ] **한글/영어 국제화** 완료 (모든 사용자 노출 문자열 String Catalog 경유)
- [ ] **VoiceOver 핵심 경로** 완주 가능 (폴더 추가 → 지시 → 응답 수신)
- [ ] **크래시 리포트** 로컬 캡처 + 다음 실행 시 사용자에게 표시
- [ ] **데이터 마이그레이션** 프레임워크로 무결한 버전 업그레이드
- [ ] **베타 테스터 ≥3명** 피드백 반영 후 v1.0 출시
- [ ] **개인정보/이용약관/오픈소스 라이선스** 문서 공개

### Non-Goals (명시적 제외)

- ❌ Windows / Linux 지원 (v1은 macOS 전용)
- ❌ 클라우드 동기화 (Keychain 외 외부 서비스 없음)
- ❌ 자율 에이전트 모드 (사용자가 늘 지휘봉)
- ❌ 자체 LLM 제공 (Maestro는 CLI를 "호출만" 함, 모델을 실행하지 않음)
- ❌ 코드 에디터 대체 (VS Code/Xcode 대체 아님, 워크스페이스 **밖**에서 지휘)

---

## 🏗️ Architecture Decisions

| 결정                                 | 근거                                                                               | Trade-offs                                         |
| ------------------------------------ | ---------------------------------------------------------------------------------- | -------------------------------------------------- |
| **SwiftUI + Swift 전체**             | macOS 네이티브 감각, 5-10MB 번들, 즉각 실행, Apple 생태계 통합                     | 크로스플랫폼 포기, Swift 학습 필요                 |
| **PTY를 사람 쉘에만 사용**           | 에이전트 오케스트레이션은 Process + Pipe 충분. TUI 파싱 지옥 회피                  | Claude TUI의 자동 편의 기능 못 씀 → 직접 구현 필요 |
| **Adapter = CLI 프로파일**           | 번들링 불필요. 사용자가 `brew install claude` 등으로 직접 설치                     | CLI가 없으면 해당 Adapter 비활성화                 |
| **파일 기반 저장**                   | JSON/JSONL. `~/Library/Application Support/Maestro/`. 사용자가 직접 편집/백업 가능 | DB의 트랜잭션/인덱스 장점 없음                     |
| **Keychain for secrets**             | API 키는 macOS Keychain에 저장                                                     | Keychain API 호출 복잡도                           |
| **Envelope Protocol**                | `inbox/`, `outbox/`, `threads/` 세 디렉토리로 메시지 왕복                          | 동기 호출보다 약간 복잡                            |
| **Swift Concurrency (async/await)**  | 현대적, 안전, 읽기 쉬움                                                            | iOS 13+ / macOS 12+ 필요 (문제 없음)               |
| **SwiftPM (Package.swift)**          | 의존성 관리 표준, Xcode 통합                                                       | CocoaPods 생태계 포기 (불필요)                     |
| **OSLog 기반 로깅**                  | macOS Console.app에서 바로 확인, 제로 런타임 비용                                  | 구조화된 원격 전송 어려움 (로컬 전용이라 OK)       |
| **Sparkle for auto-update**          | macOS 앱 표준, Anthropic도 사용                                                    | Mac App Store와 병행 어려움 (App Store 포기 OK)    |
| **SwiftTerm for shell panels**       | xterm.js의 Swift 포팅, 검증됨                                                      | 쉘 탭은 v1.1로 미뤄도 됨                           |
| **Combine + SwiftUI**                | 파일 감시, SSE 유사 스트림에 적합                                                  | AsyncStream과 혼용 필요                            |
| **코드 서명 + 노타리제이션**         | macOS 14+에서 필수 (GateKeeper)                                                    | Apple Developer 계정 연간 $99                      |
| **Swift 6 Strict Concurrency**       | 빌드 시 레이스 컨디션 예방 (`Sendable` 검사). 3-4개월 프로젝트에서 채무 방지       | 초기 몇 주 에러 밀림 (러닝 곡선)                   |
| **Swift String Catalog (xcstrings)** | Xcode 15+ 표준 i18n. 플루럴/타입세이프/자동 검출                                   | 구형 `.strings` 도구 사용 불가                     |
| **로컬 크래시 리포터**               | Apple 방식(`NSSetUncaughtExceptionHandler`, signal)으로 크래시 캡처. 외부 서비스 X | Sentry 급 편의성 없음 — 사용자가 진단 번들 전송    |
| **Schema-versioned migrations**      | 데이터 포맷 변경 시 `SchemaVersion` + `Migrator` 체인 실행                         | 앱 버전 하나 건너뛰면 릴레이 마이그레이션 필요     |
| **베타 채널 = unsigned DMG 직배**    | TestFlight 못 씀 (App Store 아님). GitHub Release로 직접                           | 베타 테스터에게 `xattr -d` 안내 필요               |
| **접근성 기본 탑재**                 | VoiceOver/Dynamic Type/High Contrast 1급 시민 — 출시 전 P22에서 전수 검증          | 초기 컴포넌트 설계 시 a11y 고려 부담               |
| **MIT 라이선스**                     | 어댑터 에코시스템 활성화를 위해 관대하게                                           | 상용 포크 가능성 (목적 달성에 더 중요함)           |

---

## 📦 Dependencies

### Required Before Starting

- [ ] **Apple Developer Account** ($99/년) — 노타리제이션용
- [ ] **Xcode 15+** — Swift 6.0, macOS 14 SDK (Phase 1 개발 환경: Xcode 26 + Swift 6.2.1 확인됨)
- [ ] **macOS 14+** (개발 머신)
- [ ] Claude CLI 설치 (`claude-code`) — 1차 개발 검증용
- [ ] Aider 설치 (`pip install aider-chat`) — 2차 검증용

### External Swift Packages

- **swift-argument-parser** — CLI 인자 파싱
- **SwiftTerm** (Phase 20) — 터미널 에뮬레이터
- **Sparkle** (Phase 21) — 자동 업데이트
- **swift-log** — 로깅 추상화
- **swift-collections** — OrderedSet 등 추가 컬렉션

### External CLI Dependencies (사용자가 설치)

- `claude` (Claude Code) — v2.x+
- `aider` — 0.80+
- `gemini` (Google Gemini CLI) — v1+ (Phase 9+)
- 기타 사용자 선택

---

## 🧪 Test Strategy

### Testing Approach

**TDD 원칙**: 모든 Phase에서 테스트를 **먼저** 작성하고 구현으로 통과시킴.

### Test Pyramid

| Test Type             | Coverage Target | Framework              | Purpose                              |
| --------------------- | :-------------: | ---------------------- | ------------------------------------ |
| **Unit Tests**        |      ≥80%       | XCTest                 | 도메인 모델, Adapter 로직, 순수 함수 |
| **Integration Tests** |      ≥70%       | XCTest                 | CLI 호출, 파일 I/O, 메시지 라우팅    |
| **UI Tests**          |   핵심 플로우   | XCUITest               | 컨트롤 타워, 토론, 디스패치 플로우   |
| **Snapshot Tests**    |    주요 화면    | swift-snapshot-testing | UI 회귀 방지                         |

### Test File Organization

```
Tests/
├── MaestroCoreTests/           # 도메인 로직 (플랫폼 독립)
│   ├── Models/
│   ├── Adapters/
│   ├── Envelope/
│   └── Persistence/
├── MaestroAppTests/             # SwiftUI 컴포넌트
│   ├── Views/
│   ├── ViewModels/
│   └── __Snapshots__/
├── MaestroIntegrationTests/     # 외부 CLI/파일시스템
│   ├── ClaudeAdapter/
│   ├── AiderAdapter/
│   └── FileWatcher/
└── MaestroUITests/              # E2E
    └── Flows/
```

### Coverage Requirements by Milestone

- **M1 (기반)**: 도메인 모델 ≥90%, 파일 레이어 ≥80%
- **M2 (첫 에이전트)**: Claude Adapter ≥80%, 채팅 뷰모델 ≥75%
- **M3 (BYOA)**: Aider Adapter ≥80%, 레지스트리 ≥85%
- **M4 (컨트롤 타워)**: 라우팅 ≥85%, UI 핵심 플로우 E2E 1개 이상
- **M5 (토론)**: 토론 엔진 ≥85%
- **M6 (파워유저)**: 커맨드 팔레트 ≥80%
- **M7 (제품화)**: 온보딩 E2E, 업데이트 통합 테스트

### Validation Commands

```bash
# Swift 빌드
swift build --configuration debug

# 유닛 + 통합 테스트
swift test --parallel

# 커버리지
swift test --enable-code-coverage
xcrun llvm-cov report .build/debug/MaestroPackageTests.xctest/Contents/MacOS/MaestroPackageTests \
  -instr-profile=.build/debug/codecov/default.profdata \
  -ignore-filename-regex="Tests|.build"

# Lint
swiftlint --strict

# Format check
swift-format lint --recursive Sources Tests

# UI 테스트 (Xcode 필요)
xcodebuild test -scheme Maestro -destination 'platform=macOS'
```

---

## 🚀 Implementation Phases

> **📢 중요 — 모든 Phase Quality Gate는 "🔬 Review & Verification" 6단계를 포함한다.**
>
> 각 Phase Quality Gate 끝에 `**🔬 Review & Verification** (→ Phase Completion Protocol 참조)` 블록이 포함되어 있으며, [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통)의 6단계를 모두 통과해야 한다:
>
> 1. 🔍 Self Code Review
> 2. 👥 **/team Multi-Agent Review** (architecture/security/performance/test-quality/ux/docs 병렬)
> 3. ✨ /simplify Skill Review
> 4. 🧩 Integration Verification
> 5. 🔄 Regression Check
> 6. 📐 Architecture Compliance
>
> 완료 시 **Phase별 리뷰 트래커** 표의 해당 행에 체크하고, `docs/reviews/phase-N.md`에 리뷰 리포트를 저장한다.

### Milestone 1: 기반 (Foundation) — 4주

---

### Phase 1: 프로젝트 부트스트랩 + CI/CD

**Goal**: SwiftPM 프로젝트 생성, SwiftUI 앱 셸, CI 파이프라인 구축. 빈 창 하나가 뜨는 상태.
**Estimated Time**: 3-4일
**Actual Time**: ~3시간 (scaffolding 특성상 빠름)
**Status**: ✅ Complete (2026-04-25)
**Commits**: `902eec3` (initial), + must-fix follow-up
**Review Report**: [docs/reviews/phase-1.md](../reviews/phase-1.md)

#### Tasks

**🔴 RED: Write Failing Tests First**

- [x] **Test 1.1**: `AppLaunchTests` — 앱이 MaestroApp struct로 시작하는지
  - File: `Tests/MaestroCoreTests/AppLaunchTests.swift` (경로 수정: MaestroApp → MaestroCore)
  - 테스트 방식: `MaestroConfig` 경유 (SwiftUI App은 직접 테스트 불가)
- [x] **Test 1.2**: `MainWindowTests` — 기본 윈도우 제목과 최소 크기
  - File: `Tests/MaestroCoreTests/MainWindowTests.swift`

**🟢 GREEN: Implement**

- [x] **Task 1.3**: `Package.swift` 생성 (executable + library 분리)
  - `Maestro` (executable), `MaestroCore` (library), `MaestroAdapters` (library)
- [x] **Task 1.4**: `MaestroApp.swift` with `@main` + `WindowGroup`
- [x] **Task 1.5**: `ContentView.swift` placeholder
- [x] ~~**Task 1.6**: `Info.plist`, `Entitlements.plist`~~ → **Phase 21로 이연** (SPM 자동 생성으로 충분, Xcode 프로젝트 래핑 시 재도입)
- [x] **Task 1.7**: GitHub Actions 워크플로 (`.github/workflows/ci.yml`)
  - build/test/coverage + SwiftLint lint 작업
- [x] **Task 1.8**: `.swiftlint.yml` 설정
- [x] **Task 1.9**: `README.md` 초기 버전
- [x] **Task 1.10**: `.gitignore` (macOS/Xcode/SwiftPM/서명 자산 전반)

**🔵 REFACTOR**

- [x] **Task 1.11**: 디렉토리 구조 최종 정리
  ```
  Maestro/
  ├── Package.swift
  ├── Sources/
  │   ├── Maestro/           # executable
  │   ├── MaestroCore/        # 도메인 로직
  │   └── MaestroAdapters/    # 에이전트 어댑터
  ├── Tests/
  ├── Resources/
  └── docs/
  ```

#### Quality Gate ✋

**TDD Compliance**:

- [x] Red → Green → Refactor 순서 지킴
- [x] 모든 테스트 작성 후 구현 시작

**Build & Tests**:

- [x] `swift build` 경고 없이 성공
- [x] `swift test` 100% 통과 (9/9)
- [ ] GitHub Actions CI 녹색 — **GitHub 푸시 후 확인 예정** (현재 로컬 레포만)

**Code Quality**:

- [ ] `swiftlint --strict` 경고 0 — **swiftlint 미설치. CI에서 검증, 로컬 설치는 optional.**
- [ ] `swift-format lint` 통과 — **swift-format 미설치. 동일.**

**Manual Testing**:

- [x] Xcode / `swift run` 으로 앱 실행 → 창 표시 확인
- [x] 창 크기 조정 가능 (windowResizability)
- [x] 타이틀 "Maestro" 표시

**Validation Commands**:

```bash
swift build --configuration debug
swift test --parallel
swiftlint --strict           # CI에서만 강제
swift-format lint --recursive Sources Tests  # CI에서만 강제
```

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [x] Step 1: 🔍 Self Code Review 완료
- [x] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / test-quality / docs — 4명 병렬) + must-fix 9건 반영
- [x] Step 3: ✨ `/simplify` 리뷰 + 제안 반영 (`import Foundation` 제거)
- [x] Step 4: 🧩 Integration Verification (swift run → 창 확인)
- [x] Step 5: 🔄 Regression Check (최초 Phase, 비교 대상 없음 — trivially pass)
- [x] Step 6: 📐 Architecture Compliance (레이어 경계, Swift 6, Sendable 등 전부 ✅)
- [x] `docs/reviews/phase-1.md` 리뷰 리포트 저장
- [x] **Phase별 리뷰 트래커** P1 행 모두 체크

---

### Phase 2: 도메인 모델 (Session, Envelope, AgentProfile)

**Goal**: 모든 기능의 핵심 데이터 구조 정의. 순수 Swift, 외부 의존성 없음.
**Estimated Time**: 4-5일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 2.1**: `MessageEnvelopeTests` — 봉투 생성/검증/직렬화
  - `from`, `to`, `threadId`, `inReplyTo`, `body`, `createdAt` 필드
  - JSON 라운드트립 (Codable)
  - 필수 필드 누락 시 에러
- [ ] **Test 2.2**: `SessionTests` — Session 생성, 상태 전이
  - `id`, `folderPath`, `adapterId`, `createdAt`, `lastActivityAt`
- [ ] **Test 2.3**: `AgentProfileTests` — 프로파일 동등성, 해시
- [ ] **Test 2.4**: `ThreadTests` — 스레드 트리 구조 (부모-자식)
- [ ] **Test 2.5**: `DiscussionTests` — 토론 상태 머신

**🟢 GREEN**

- [ ] **Task 2.6**: `MessageEnvelope.swift` (struct, Codable, Hashable)
- [ ] **Task 2.7**: `Session.swift` + `SessionStatus` enum
- [ ] **Task 2.8**: `AgentProfile.swift` — 어댑터 ID, 실행 커맨드, 감지 규칙
- [ ] **Task 2.9**: `Thread.swift` + 부모-자식 관계
- [ ] **Task 2.10**: `Discussion.swift` + `DiscussionTurn` + 상태머신
- [ ] **Task 2.11**: `MessageType` enum (`task`, `question`, `report`, `fyi`)
- [ ] **Task 2.12**: ID 타입 안전성 (`EnvelopeID`, `ThreadID`, `SessionID` — phantom types)

**🔵 REFACTOR**

- [ ] **Task 2.13**: `Codable` 구현 통일 (커스텀 coding keys, 날짜 포맷)
- [ ] **Task 2.14**: Factory 메서드 추가 (`MessageEnvelope.task(from:to:body:)`)
- [ ] **Task 2.15**: 문서 주석 (DocC) 추가

#### Quality Gate ✋

**TDD**:

- [ ] 모든 모델 테스트 먼저 작성
- [ ] 커버리지 ≥90% (순수 데이터 구조라서 높아야 함)

**Build & Tests**:

- [ ] `MaestroCore` 타겟 단독으로 빌드됨 (앱 의존성 없음)
- [ ] 100% 테스트 통과
- [ ] JSON 라운드트립 검증

**Code Quality**:

- [ ] Lint/Format 통과
- [ ] DocC 경고 0

**Manual Testing**:

- [ ] Swift REPL에서 모델 생성/직렬화 시연 가능

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / performance / test-quality / docs) + must-fix 반영
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-2.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P2 행 모두 체크

---

### Phase 3: 파일 영속성 레이어 + Keychain

**Goal**: JSON/JSONL 기반 저장소 추상화, 원자적 쓰기, Keychain 래퍼.
**Estimated Time**: 5일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 3.1**: `FileStoreTests` — 읽기/원자적 쓰기/잠금
- [ ] **Test 3.2**: `JSONLAppenderTests` — append-only 동시성 안전
- [ ] **Test 3.3**: `JSONLTailerTests` — 증분 읽기, 파일 감시
- [ ] **Test 3.4**: `KeychainStoreTests` — 저장/조회/삭제 (실제 Keychain 사용)
- [ ] **Test 3.5**: `AppSupportPathsTests` — `~/Library/Application Support/Maestro/` 구조
- [ ] **Test 3.6**: `FileWatcherTests` — DispatchSource 기반 파일/디렉토리 감시

**🟢 GREEN**

- [ ] **Task 3.7**: `FileStore<T: Codable>` — 제네릭 JSON 저장소 (atomic write via temp + rename)
- [ ] **Task 3.8**: `JSONLAppender` — 동시성 안전 append (fcntl 락)
- [ ] **Task 3.9**: `JSONLTailer` — AsyncStream 기반 증분 이벤트 스트림
- [ ] **Task 3.10**: `KeychainStore` — Security 프레임워크 래퍼
- [ ] **Task 3.11**: `AppSupportPaths` — 경로 상수 중앙 관리
  ```
  ~/Library/Application Support/Maestro/
  ├── config.json
  ├── agents/              # 폴더별 에이전트 레지스트리
  │   └── <folder-hash>.json
  ├── inbox/<agent>/
  ├── outbox/<agent>/
  ├── threads/<thread-id>.jsonl
  └── logs/
  ```
- [ ] **Task 3.12**: `FileWatcher` — 디렉토리/파일 변경 이벤트 Combine publisher

**🔵 REFACTOR**

- [ ] **Task 3.13**: 에러 타입 통일 (`PersistenceError` enum)
- [ ] **Task 3.14**: 테스트용 `InMemoryFileStore` mock

#### Quality Gate ✋

- [ ] 원자적 쓰기 보장 (크래시 중간에도 파일 손상 없음)
- [ ] Keychain 저장/조회 실제 동작 확인
- [ ] JSONLTailer가 1GB 파일에서도 O(1) append 감지
- [ ] 동시성 레이스 조건 없음 (TSan 통과)

**Validation Commands**:

```bash
swift test --parallel
swift test --sanitize=thread  # 스레드 안정성 검증
```

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / performance / test-quality / docs) + must-fix 반영
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-3.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P3 행 모두 체크

---

### Phase 4: AgentAdapter 프로토콜 + CLI 감지

**Goal**: 모든 에이전트가 따를 공통 프로토콜 정의 + 시스템 PATH에서 CLI 자동 감지.
**Estimated Time**: 4-5일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 4.1**: `AgentAdapterProtocolTests` — 프로토콜 컨트랙트
- [ ] **Test 4.2**: `CLIDetectorTests` — PATH 검색, 버전 추출, 설치 여부
- [ ] **Test 4.3**: `AdapterRegistryTests` — 어댑터 등록/조회/활성화
- [ ] **Test 4.4**: `MockAdapter` 구현체 + 그걸로 레지스트리 테스트

**🟢 GREEN**

- [ ] **Task 4.5**: `AgentAdapter` 프로토콜

  ```swift
  protocol AgentAdapter: Sendable {
    static var id: String { get }                    // "claude", "aider"
    static var displayName: String { get }
    static var iconName: String { get }

    func detect() async -> AdapterDetection            // 설치 여부 + 버전
    func createSession(folderPath: URL) async throws -> Session
    func destroySession(_ id: SessionID) async throws
    func sendMessage(_ env: MessageEnvelope, in session: Session) async throws -> MessageEnvelope
    func streamMessage(_ env: MessageEnvelope, in session: Session) -> AsyncThrowingStream<ResponseChunk, Error>
    func listSlashCommands(in session: Session) async -> [SlashCommand]
  }
  ```

- [ ] **Task 4.6**: `CLIDetector` — `which`, `--version` 파싱
- [ ] **Task 4.7**: `AdapterRegistry` — 런타임 어댑터 관리
- [ ] **Task 4.8**: `AdapterDetection` struct (installed, version, path)

**🔵 REFACTOR**

- [ ] **Task 4.9**: 프로토콜 기본 구현 (default implementations)
- [ ] **Task 4.10**: 테스트용 `MockAdapter` 공개 API

#### Quality Gate ✋

- [ ] 프로토콜이 Claude와 Aider 모두에 맞는지 종이 설계 검증
- [ ] CLIDetector가 실제 `claude --version`, `aider --version` 파싱 성공
- [ ] MockAdapter로 전체 플로우 단위 테스트 가능

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / performance / test-quality / docs) + must-fix 반영
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-4.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P4 행 모두 체크

---

### Phase 5: 로깅/옵저버빌리티 (OSLog + 진단)

**Goal**: 3-4개월 개발 내내 쓸 로깅 인프라. 디버깅/문제 추적.
**Estimated Time**: 3일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 5.1**: `LoggerTests` — 카테고리별 로깅, 레벨 필터
- [ ] **Test 5.2**: `DiagnosticsBundleTests` — 사용자 진단 번들 생성

**🟢 GREEN**

- [ ] **Task 5.3**: `MaestroLogger` — OSLog 래퍼 (카테고리 enum)
- [ ] **Task 5.4**: 로깅 카테고리 정의 (`.adapter`, `.persistence`, `.ui`, `.orchestration`)
- [ ] **Task 5.5**: `DiagnosticsBundle` — 설정/로그/레지스트리 모아서 ZIP 생성
- [ ] **Task 5.6**: 전역 에러 핸들러 + OSLog 기록
- [ ] **Task 5.7**: `signpost` 기반 성능 계측 (Instruments 연동)

**🔵 REFACTOR**

- [ ] **Task 5.8**: 기존 `print` 구문을 Logger로 교체 (Phase 1-4)

#### Quality Gate ✋

- [ ] Console.app에서 Maestro 로그 필터링 확인
- [ ] Instruments에서 signpost 이벤트 보임
- [ ] 진단 번들이 정상 생성됨

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / performance / test-quality / docs) + must-fix 반영
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-5.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P5 행 모두 체크

---

### Milestone 2: 첫 에이전트 (2주)

---

### Phase 6: Process 래퍼 + Streaming 인프라

**Goal**: CLI를 안전하게 실행하고 출력을 스트리밍하는 공용 인프라.
**Estimated Time**: 4일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 6.1**: `ProcessRunnerTests` — 기본 실행, 종료 코드, stdout/stderr 분리
- [ ] **Test 6.2**: `ProcessStreamerTests` — AsyncStream으로 라인 단위 출력
- [ ] **Test 6.3**: `ProcessRunnerTests.timeout` — 타임아웃 처리
- [ ] **Test 6.4**: `ProcessRunnerTests.cancel` — Task 취소 시 프로세스 종료

**🟢 GREEN**

- [ ] **Task 6.5**: `ProcessRunner` — `Foundation.Process` async/await 래퍼
- [ ] **Task 6.6**: `ProcessStreamer` — 라인 버퍼링 + AsyncStream
- [ ] **Task 6.7**: 환경 변수 sanitization (OAuth 토큰 제거 등)
- [ ] **Task 6.8**: 작업 디렉토리 설정 지원
- [ ] **Task 6.9**: 취소/타임아웃 처리

**🔵 REFACTOR**

- [ ] **Task 6.10**: SIGTERM → SIGKILL 단계적 종료
- [ ] **Task 6.11**: 에러 메시지 개선 (실패 시 stderr 포함)

#### Quality Gate ✋

- [ ] `echo "hello"` 실행 + 출력 캡처 성공
- [ ] 100ms 타임아웃 테스트 통과
- [ ] Task 취소 시 좀비 프로세스 없음

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / performance / test-quality / docs) + must-fix 반영
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-6.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P6 행 모두 체크

---

### Phase 7: Claude Adapter

**Goal**: 첫 번째 실제 어댑터. Claude CLI와 end-to-end 통신.
**Estimated Time**: 5일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 7.1**: `ClaudeAdapterTests.detect` — 버전 파싱
- [ ] **Test 7.2**: `ClaudeAdapterTests.sendMessage` — 모의 CLI 응답 처리
- [ ] **Test 7.3**: `ClaudeAdapterTests.slashCommands` — `/help` 프로빙 파싱
- [ ] **Test 7.4**: `ClaudeAdapterTests.session` — session_id 관리, `--resume` 분기
- [ ] **Test 7.5**: `ClaudeAdapterIntegrationTests` — 실제 `claude` CLI 호출

**🟢 GREEN**

- [ ] **Task 7.6**: `ClaudeAdapter.swift`
  - `claude -p <prompt> --resume <id> --output-format json`
- [ ] **Task 7.7**: JSON 응답 파싱 (`type`, `content`, `usage`, `session_id`)
- [ ] **Task 7.8**: 세션 파일 감지 (`~/.claude/projects/.../<id>.jsonl`)
- [ ] **Task 7.9**: 스트리밍 모드 (`--output-format stream-json`)
- [ ] **Task 7.10**: 슬래시 명령어 스캔 (`~/.claude/commands/`, 플러그인)

**🔵 REFACTOR**

- [ ] **Task 7.11**: 에러 매핑 (CLI 에러 → Swift 에러 타입)
- [ ] **Task 7.12**: 재시도 정책 (네트워크 에러 등)

#### Quality Gate ✋

- [ ] 실제 Claude CLI로 "안녕" → 응답 받기 성공
- [ ] 슬래시 명령어 ≥10개 감지
- [ ] 세션 재개 시 이전 대화 기억 확인

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / performance / test-quality / docs) + must-fix 반영
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (실제 Claude CLI와 연동 smoke test)
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-7.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P7 행 모두 체크

---

### Phase 8: 기본 채팅 UI

**Goal**: 단일 에이전트와의 대화 화면. 마크다운 렌더링, 스트리밍 표시.
**Estimated Time**: 5일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 8.1**: `ChatViewModelTests` — 메시지 전송/수신, 상태 전이
- [ ] **Test 8.2**: `ChatViewSnapshotTests` — 기본 렌더링
- [ ] **Test 8.3**: `MarkdownRenderingTests` — 코드 블록, 목록, 링크

**🟢 GREEN**

- [ ] **Task 8.4**: `ChatView.swift` (SwiftUI)
- [ ] **Task 8.5**: `ChatViewModel.swift` (@Observable)
- [ ] **Task 8.6**: `MessageBubbleView` — 사용자 vs 어시스턴트
- [ ] **Task 8.7**: `MarkdownRenderer` — SwiftUI `Text` 기반 (AttributedString)
- [ ] **Task 8.8**: 코드 블록 syntax highlight (간단한 모노스페이스 + 배경)
- [ ] **Task 8.9**: 스트리밍 타이핑 효과 (점진적 업데이트)
- [ ] **Task 8.10**: 입력창 (멀티라인, Cmd+Enter 전송)
- [ ] **Task 8.11**: 자동 스크롤 (새 메시지 시)

**🔵 REFACTOR**

- [ ] **Task 8.12**: 접근성 라벨 추가 (VoiceOver)
- [ ] **Task 8.13**: 다크/라이트 모드 자동 대응

#### Quality Gate ✋

- [ ] 실제 Claude에 메시지 전송 → UI에 스트리밍 응답 표시
- [ ] 마크다운 렌더링 시각 확인
- [ ] 스냅샷 테스트 통과

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / performance / test-quality / **ux** / docs) + must-fix 반영 _(UI Phase이므로 ux-reviewer 필수)_
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (실제 앱 실행 → Claude 대화)
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-8.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P8 행 모두 체크

---

### Milestone 3: BYOA 증명 (2주)

---

### Phase 9: Aider Adapter

**Goal**: 두 번째 벤더 어댑터 성공. BYOA 컨셉 증명.
**Estimated Time**: 5일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 9.1**: `AiderAdapterTests.detect`
- [ ] **Test 9.2**: `AiderAdapterTests.sendMessage` — Aider 출력 포맷 파싱
- [ ] **Test 9.3**: `AiderAdapterIntegrationTests` — 실제 aider 호출

**🟢 GREEN**

- [ ] **Task 9.4**: `AiderAdapter.swift`
  - `aider --message "..." --no-auto-commits --no-pretty`
- [ ] **Task 9.5**: Aider 세션 관리 (대화 히스토리 직접 저장)
- [ ] **Task 9.6**: 출력 파서 (Aider는 JSON 모드 없음 → stdout 패턴 매칭)

**🔵 REFACTOR**

- [ ] **Task 9.7**: 공통 로직을 `BaseAdapter` 추상 클래스로 추출
- [ ] **Task 9.8**: 에러 메시지 표준화

#### Quality Gate ✋

- [ ] Claude와 Aider를 한 UI에서 번갈아 사용 가능
- [ ] 각자 자기 세션 유지 (섞이지 않음)
- [ ] 둘 다 채팅 UI에서 동일하게 작동

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / performance / test-quality / docs) + must-fix 반영 _(Aider adapter 특유의 stdout 파싱 robustness 중점 검토)_
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (Claude ↔ Aider 전환 실제 확인)
- [ ] Step 5: 🔄 Regression Check (Claude adapter 여전히 동작)
- [ ] Step 6: 📐 Architecture Compliance (Adapter 프로토콜 준수)
- [ ] `docs/reviews/phase-9.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P9 행 모두 체크

---

### Phase 10: 레지스트리 + 폴더 관리 UI

**Goal**: 여러 폴더를 등록하고, 각 폴더마다 기본 에이전트 선택.
**Estimated Time**: 5일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 10.1**: `FolderRegistryTests` — 추가/삭제/업데이트
- [ ] **Test 10.2**: `FolderViewModelTests`
- [ ] **Test 10.3**: `FolderPickerTests` — macOS NSOpenPanel 통합

**🟢 GREEN**

- [ ] **Task 10.4**: `FolderRegistry` — `folders.json` 저장소
- [ ] **Task 10.5**: `SidebarView` — 폴더 목록 표시, 상태 뱃지
- [ ] **Task 10.6**: "+ 폴더 추가" 버튼 → NSOpenPanel
- [ ] **Task 10.7**: 폴더별 에이전트 선택 팝업
- [ ] **Task 10.8**: 폴더 설정 시트 (`⌘,` 단축키)

**🔵 REFACTOR**

- [ ] **Task 10.9**: 레지스트리 변경 시 UI 자동 새로고침 (Combine)
- [ ] **Task 10.10**: 폴더 삭제 시 confirm 다이얼로그

#### Quality Gate ✋

- [ ] 3개 이상 폴더 동시 등록 가능
- [ ] 각 폴더 클릭 시 해당 에이전트로 채팅 전환
- [ ] 앱 재시작 후 폴더 목록 유지

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / performance / test-quality / **ux** / docs) + must-fix 반영
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-10.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P10 행 모두 체크

---

### Milestone 4: 컨트롤 타워 (3주)

---

### Phase 11: 메시지 봉투 + 라우팅 (inbox/outbox/threads)

**Goal**: 에이전트 간 메시지 왕복 프로토콜 구현. UI 없이 백엔드만.
**Estimated Time**: 5일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 11.1**: `EnvelopeRouterTests` — inbox에 봉투 drop → 타겟 어댑터 호출
- [ ] **Test 11.2**: `ThreadLoggerTests` — 스레드별 JSONL 기록
- [ ] **Test 11.3**: `RouterTests.reply` — 응답이 원래 스레드에 귀속
- [ ] **Test 11.4**: `RouterTests.concurrentDispatch` — 동시 여러 봉투 처리

**🟢 GREEN**

- [ ] **Task 11.5**: `EnvelopeRouter` — 디렉토리 감시 + 디스패치
- [ ] **Task 11.6**: `ThreadLogger` — 모든 메시지를 `threads/<id>.jsonl`에 기록
- [ ] **Task 11.7**: `InboxWatcher` — 각 agent의 inbox/ 감시 (FileWatcher 활용)
- [ ] **Task 11.8**: Reply 메시지 자동 생성 (`inReplyTo` 자동 채움)

**🔵 REFACTOR**

- [ ] **Task 11.9**: 메시지 처리 큐 (백프레셔 대응)
- [ ] **Task 11.10**: 실패 시 DLQ (dead letter queue) — `failed/` 디렉토리

#### Quality Gate ✋

- [ ] CLI에서 inbox에 봉투 drop → Claude 응답 → outbox 파일 생성 확인
- [ ] threads/\*.jsonl이 올바르게 누적
- [ ] 동시 10개 dispatch 처리 성공

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / **performance** / test-quality / docs) + must-fix 반영 _(동시성/레이스 컨디션 집중 검토)_
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (inbox → outbox → threads 전체 플로우)
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance (Envelope 프로토콜 준수)
- [ ] `docs/reviews/phase-11.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P11 행 모두 체크

---

### Phase 12: 컨트롤 타워 UI

**Goal**: 메인 화면. 사이드바(폴더+에이전트 상태) + 메인 패널(선택된 대화) + 보고함.
**Estimated Time**: 5-6일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 12.1**: `ControlTowerViewModelTests`
- [ ] **Test 12.2**: `OrchestrationStatusTests` — 진행 중/완료/에러 상태
- [ ] **Test 12.3**: `ControlTowerViewSnapshotTests`

**🟢 GREEN**

- [ ] **Task 12.4**: `ControlTowerView` — 3-컬럼 레이아웃 (Sidebar / Main / Inspector)
- [ ] **Task 12.5**: `AgentStatusBadge` — 🟢 active / 🟡 idle / 🔴 error
- [ ] **Task 12.6**: `OrchestrationStatusBar` — 상단 "● A → B (진행중)" 표시
- [ ] **Task 12.7**: `InboxPanel` — 우측 보고함 (받은 메시지 모음)
- [ ] **Task 12.8**: `ThreadView` — 스레드 트리 시각화

**🔵 REFACTOR**

- [ ] **Task 12.9**: 컴포넌트 분리 및 ViewModel 추출
- [ ] **Task 12.10**: 레이아웃 반응형 (창 크기 변경 대응)

#### Quality Gate ✋

- [ ] 사이드바에서 폴더 클릭 시 대화 창 전환
- [ ] 보고함에 새 메시지 시 뱃지 카운트 증가
- [ ] 상단 상태 바 실시간 업데이트

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / performance / test-quality / **ux** / docs) + must-fix 반영
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (실제 앱에서 여러 폴더 동시 대화)
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-12.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P12 행 모두 체크

---

### Phase 13: @dispatch + 양방향 보고 루프

**Goal**: 컨트롤 타워에서 특정 에이전트에 지시 → 수행 → 자동 보고 전체 플로우.
**Estimated Time**: 5일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 13.1**: `DispatchServiceTests.sendAndReceive` — 왕복 루프
- [ ] **Test 13.2**: `DispatchServiceTests.expectReply` — 응답 대기 + 타임아웃
- [ ] **Test 13.3**: `DispatchServiceTests.relay` — A → B → C 릴레이
- [ ] **Test 13.4**: `ReplyParserTests` — `<REPLY_TO=...>` 태그 추출

**🟢 GREEN**

- [ ] **Task 13.5**: `DispatchService` — 고수준 API
  ```swift
  func dispatch(to: AgentID, body: String, expectReply: Bool) async throws -> MessageEnvelope?
  ```
- [ ] **Task 13.6**: 시스템 프롬프트 확장 (태그 포맷 요구)
- [ ] **Task 13.7**: `ReplyParser` — 응답에서 REPLY 태그 추출
- [ ] **Task 13.8**: 컨트롤 타워 UI에 "보내기" 버튼 (에이전트 선택 + 메시지 + 전송)
- [ ] **Task 13.9**: 응답 수신 시 인박스에 알림 표시
- [ ] **Task 13.10**: 타임아웃 UI (5분 경과 시 ⚠️)

**🔵 REFACTOR**

- [ ] **Task 13.11**: 디스패치 히스토리 UI (과거 지시 목록)
- [ ] **Task 13.12**: 릴레이 체인 시각화

#### Quality Gate ✋

- [ ] 컨트롤 타워에서 "CPO에게 Q3 보고해" 전송 → 응답 자동 도착
- [ ] 릴레이 (A→B→C) 동작 확인
- [ ] 타임아웃 시 적절한 UI 피드백

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / performance / test-quality / **ux** / docs) + must-fix 반영 _(dispatch 신뢰성 & 에러 UX 중점)_
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (컨트롤 → CPO → CMO 릴레이 end-to-end)
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-13.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P13 행 모두 체크

---

### Milestone 5: 토론 엔진 (2주)

---

### Phase 14: 토론 엔진

**Goal**: 3명 이상의 에이전트가 한 주제로 턴을 주고받는 로직.
**Estimated Time**: 5일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 14.1**: `DiscussionEngineTests.roundRobin`
- [ ] **Test 14.2**: `DiscussionEngineTests.moderator` — 다음 발언자 선택
- [ ] **Test 14.3**: `DiscussionEngineTests.pauseResume` — 사용자 개입
- [ ] **Test 14.4**: `DiscussionEngineTests.termination` — 종료 조건

**🟢 GREEN**

- [ ] **Task 14.5**: `Discussion` 모델 확장 (참가자, 규칙, 상태)
- [ ] **Task 14.6**: `DiscussionEngine` — 턴 관리 상태머신
- [ ] **Task 14.7**: `ModeratorStrategy` 프로토콜 (라운드로빈/랜덤/LLM 선택)
- [ ] **Task 14.8**: `LLMModerator` — Claude를 moderator로 사용
- [ ] **Task 14.9**: 각 턴마다 `DispatchService` 통해 발언자 호출
- [ ] **Task 14.10**: 종료 조건 (턴 제한, 종료 선언, 사용자 중단)

**🔵 REFACTOR**

- [ ] **Task 14.11**: 뮤텍스로 동시 advance 방지
- [ ] **Task 14.12**: 토론 상태 저장/복원

#### Quality Gate ✋

- [ ] Claude + Aider + Claude 3인 토론 정상 진행
- [ ] 사용자가 "끼어들기" 가능
- [ ] 종료 후 전체 로그가 thread에 남음

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / performance / test-quality / docs) + must-fix 반영 _(상태머신 완결성, 동시성 집중)_
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (Claude + Aider + Claude 3인 토론 완주)
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-14.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P14 행 모두 체크

---

### Phase 15: 토론 UI (Slack 스타일 스레드)

**Goal**: 토론을 카카오톡/Slack 느낌으로 렌더링. 참여자 뱃지, 타이핑 인디케이터.
**Estimated Time**: 5일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 15.1**: `DiscussionViewModelTests`
- [ ] **Test 15.2**: `DiscussionViewSnapshotTests`

**🟢 GREEN**

- [ ] **Task 15.3**: `DiscussionListView` — 진행 중/완료 토론 목록
- [ ] **Task 15.4**: `DiscussionDetailView` — 스레드 말풍선 뷰
- [ ] **Task 15.5**: `ParticipantAvatar` — 어댑터별 아이콘 + 색
- [ ] **Task 15.6**: 타이핑 인디케이터 (●●● 애니메이션)
- [ ] **Task 15.7**: 사용자 끼어들기 입력창 ("🎤 잠깐 끼어들기")
- [ ] **Task 15.8**: "새 토론 시작" 다이얼로그 (제목, 참가자 선택, 규칙)

**🔵 REFACTOR**

- [ ] **Task 15.9**: 긴 토론에서 무한 스크롤 성능 최적화
- [ ] **Task 15.10**: 토론 내보내기 (Markdown)

#### Quality Gate ✋

- [ ] 3명 이상 참여 토론 시각적으로 구분됨
- [ ] 실시간 진행 상황 자연스럽게 업데이트
- [ ] 토론 재방문 시 과거 로그 즉시 로드

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / **performance** / test-quality / **ux** / docs) + must-fix 반영 _(긴 대화 렌더링 성능 중점)_
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (토론 100+ 턴 렌더링 부드러움)
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-15.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P15 행 모두 체크

---

### Milestone 6: 파워유저 UX (2주)

---

### Phase 16: 커맨드 팔레트 (Cmd+K) + 단축키 시스템

**Goal**: @dispatch 가로채기 대체. 전역 명령 진입점.
**Estimated Time**: 4-5일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 16.1**: `CommandPaletteViewModelTests` — 명령 필터링, 퍼지 매칭
- [ ] **Test 16.2**: `KeyboardShortcutTests` — 단축키 충돌 감지

**🟢 GREEN**

- [ ] **Task 16.3**: `CommandPaletteView` (플로팅 모달)
- [ ] **Task 16.4**: 전역 단축키 `Cmd+K` 등록
- [ ] **Task 16.5**: 명령 카테고리:
  - 폴더 전환 (`⌘1`~`⌘9`)
  - 에이전트로 보내기 (`@agent 내용`)
  - 토론 시작
  - 설정 열기
  - 최근 지시 재실행
- [ ] **Task 16.6**: 퍼지 매칭 (SwiftUI 내장 없음 → 간단 구현)
- [ ] **Task 16.7**: 최근/자주 쓰는 명령 추적

**🔵 REFACTOR**

- [ ] **Task 16.8**: 확장 가능한 CommandProvider 프로토콜 (플러그인)
- [ ] **Task 16.9**: 단축키 커스터마이징 UI (Phase 19에서 노출)

#### Quality Gate ✋

- [ ] Cmd+K로 어디서든 즉시 팔레트 열림
- [ ] 키보드만으로 모든 주요 액션 가능
- [ ] 100+ 명령 있어도 지연 없음

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / performance / test-quality / **ux** / docs) + must-fix 반영
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (Cmd+K → 폴더 전환/전송/토론 시작)
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-16.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P16 행 모두 체크

---

### Phase 17: 슬래시 명령어 + 스킬 자동 탐색

**Goal**: `~/.claude/commands/`, 플러그인, 스킬 실시간 감시 + UI 자동 반영.
**Estimated Time**: 4일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 17.1**: `SlashCommandRegistryTests` — 파일 스캔 + 캐시
- [ ] **Test 17.2**: `SlashCommandWatcherTests` — 변경 실시간 반영
- [ ] **Test 17.3**: `BuiltinProberTests` — `/help` 파싱 + 캐싱

**🟢 GREEN**

- [ ] **Task 17.4**: `SlashCommandRegistry` — 모든 소스 통합 (file/builtin/plugin)
- [ ] **Task 17.5**: `SlashCommandWatcher` — `~/.claude/**` 감시
- [ ] **Task 17.6**: `BuiltinProber` — `claude -p "/help"` 캐싱 (24h TTL)
- [ ] **Task 17.7**: 커맨드 팔레트에 슬래시 섹션 통합
- [ ] **Task 17.8**: 인수 입력 폼 (frontmatter의 `argument-hint` 활용)
- [ ] **Task 17.9**: 스킬 탐색 (`~/.claude/skills/*/SKILL.md`)

**🔵 REFACTOR**

- [ ] **Task 17.10**: 캐시 무효화 전략 정리
- [ ] **Task 17.11**: 소스별 아이콘/섹션

#### Quality Gate ✋

- [ ] `~/.claude/commands/new.md` 추가 시 5초 이내 UI 반영
- [ ] Claude Code 버전 업그레이드 시 내장 명령어 재프로빙
- [ ] 20+ 슬래시 명령어 중 원하는 거 즉시 검색

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / performance / test-quality / docs) + must-fix 반영 _(파일 감시 누수/캐시 무효화 집중)_
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (`.md` 추가/삭제 실시간 반영 확인)
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-17.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P17 행 모두 체크

---

### Phase 18: 네이티브 메뉴 + 메뉴바 앱

**Goal**: macOS 느낌. 표준 메뉴 (File/Edit/View/Window), 메뉴바 아이콘.
**Estimated Time**: 3-4일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 18.1**: `MenuCommandsTests` — 메뉴 액션 핸들러

**🟢 GREEN**

- [ ] **Task 18.2**: `CommandGroup`들 정의 (File, Edit, Maestro, Window, Help)
- [ ] **Task 18.3**: 표준 액션 (New Folder ⌘N, Close ⌘W, Preferences ⌘,)
- [ ] **Task 18.4**: 메뉴바 `MenuBarExtra` — 아이콘 + 요약 정보
- [ ] **Task 18.5**: 메뉴바에서 "최근 활동" 미리보기
- [ ] **Task 18.6**: Dock 뱃지 (진행 중 디스패치 카운트)
- [ ] **Task 18.7**: 시스템 알림 (UNUserNotificationCenter) — 보고 도착 시

**🔵 REFACTOR**

- [ ] **Task 18.8**: 알림 설정 (사용자 on/off 토글, Phase 19에서 노출)

#### Quality Gate ✋

- [ ] 모든 표준 macOS 단축키 작동
- [ ] 메뉴바에서 앱 창 열지 않고도 상태 확인 가능
- [ ] 알림이 집중 모드 규칙 존중

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / performance / test-quality / **ux** / docs) + must-fix 반영 _(Apple HIG 준수 확인)_
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (메뉴바/Dock/알림 3중 통합)
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-18.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P18 행 모두 체크

---

### Milestone 7: 제품화 (2주)

---

### Phase 19: 설정 UI + 온보딩 + Keychain 통합

**Goal**: 첫 실행 가이드, 설정 화면, API 키 안전 저장.
**Estimated Time**: 5일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 19.1**: `OnboardingViewModelTests` — 단계별 진행
- [ ] **Test 19.2**: `PreferencesStoreTests` — 설정 저장/복원
- [ ] **Test 19.3**: `APIKeyStorageTests` — Keychain 통합 (Phase 3 연계)

**🟢 GREEN**

- [ ] **Task 19.4**: `OnboardingView` — 3단계
  1. 환영 + 개념 설명
  2. CLI 감지 결과 (설치된/미설치 에이전트 목록 + 설치 가이드)
  3. 첫 폴더 추가
- [ ] **Task 19.5**: `PreferencesView` — Tab 기반
  - General: 실행/업데이트/알림
  - Agents: 어댑터 활성화, API 키 입력
  - Shortcuts: 단축키 커스터마이징
  - Advanced: 로그, 진단, 데이터 위치
- [ ] **Task 19.6**: API 키 입력 필드 (SecureField) → Keychain 저장
- [ ] **Task 19.7**: "데이터 폴더 Finder에서 열기" 버튼
- [ ] **Task 19.8**: "진단 번들 생성" 버튼 (Phase 5 활용)

**🔵 REFACTOR**

- [ ] **Task 19.9**: 첫 실행 감지 (`UserDefaults` 플래그)
- [ ] **Task 19.10**: 설정 변경 실시간 적용

#### Quality Gate ✋

- [ ] 처음 앱 실행 시 온보딩 3단계 완주 가능
- [ ] API 키가 Keychain에만 저장 (파일 검색 시 평문 없음)
- [ ] 모든 설정 변경이 재시작 없이 반영

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / **security** / performance / test-quality / **ux** / docs) + must-fix 반영 _(Keychain 사용 보안 검증 최우선)_
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (새 사용자 온보딩 시뮬레이션)
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance (시크릿 파일 저장 금지)
- [ ] `docs/reviews/phase-19.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P19 행 모두 체크

---

### Phase 20: 쉘 터미널 패널 (SwiftTerm)

**Goal**: 사용자가 직접 쉘 명령 쓸 수 있는 탭 (선택 기능).
**Estimated Time**: 5일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 20.1**: `ShellSessionTests` — PTY 스폰, 리사이즈
- [ ] **Test 20.2**: `ShellTabViewModelTests`

**🟢 GREEN**

- [ ] **Task 20.3**: SwiftTerm 패키지 통합
- [ ] **Task 20.4**: `ShellSession` — Swift의 `Process` + PTY 유틸리티
- [ ] **Task 20.5**: `ShellTabView` — SwiftTerm 래핑
- [ ] **Task 20.6**: 폴더별 다중 탭 지원 (Claude / Shell / 로그)
- [ ] **Task 20.7**: 탭 드래그 순서 변경, Cmd+1~9 전환
- [ ] **Task 20.8**: 탭 분할 (수평/수직)

**🔵 REFACTOR**

- [ ] **Task 20.9**: 레이아웃 저장/복원 (`layouts.json`)

#### Quality Gate ✋

- [ ] `vim`, `htop`, `git log` 등 TUI 앱 정상 동작
- [ ] 한글 IME 완벽 입력
- [ ] 여러 탭 동시 실행해도 성능 이상 없음

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / **performance** / test-quality / **ux** / docs) + must-fix 반영 _(PTY 리소스 누수 집중)_
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (vim/htop/git 실사용 테스트)
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance (쉘은 사용자용만)
- [ ] `docs/reviews/phase-20.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P20 행 모두 체크

---

### Phase 21: 패키징 / 서명 / 노타리제이션 / 자동업데이트

**Goal**: 사용자가 .dmg 더블클릭 → 설치 → 자동 업데이트까지. 상용 배포 가능.
**Estimated Time**: 5일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 21.1**: `UpdateCheckerTests` (mock URL)
- [ ] **Test 21.2**: `DMGBuildScriptTests` (dry run)

**🟢 GREEN**

- [ ] **Task 21.3**: Xcode 프로젝트 `.xcodeproj` 생성 (SwiftPM 외 Xcode 빌드용)
- [ ] **Task 21.4**: Apple Developer 인증서 설정, 서명 자동화
- [ ] **Task 21.5**: 노타리제이션 스크립트 (`xcrun notarytool`)
- [ ] **Task 21.6**: `create-dmg` 기반 DMG 빌드 스크립트
- [ ] **Task 21.7**: Sparkle 통합 — `appcast.xml` 생성
- [ ] **Task 21.8**: 자동 업데이트 UI (백그라운드 확인, 알림, 재시작)
- [ ] **Task 21.9**: EdDSA 서명 키 생성 (Sparkle 보안)
- [ ] **Task 21.10**: GitHub Actions에 릴리즈 워크플로 추가
  - 태그 푸시 → 빌드 → 서명 → 노타리제이션 → DMG → appcast 업데이트

**🔵 REFACTOR**

- [ ] **Task 21.11**: 릴리즈 노트 자동 생성 (git log → Markdown)
- [ ] **Task 21.12**: 버전 증가 자동화

#### Quality Gate ✋

- [ ] GateKeeper 경고 없이 DMG 설치 가능
- [ ] 첫 실행 시 `xattr -d com.apple.quarantine` 불필요
- [ ] 자동 업데이트 end-to-end 검증 (이전 버전 설치 → 새 버전 감지 → 업데이트)
- [ ] GitHub Actions에서 push → DMG 파일 산출 성공

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / **security** / performance / test-quality / **ux** / docs) + must-fix 반영 _(코드 서명/노타리제이션 보안 설정 최우선)_
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (실제 이전 버전 설치 → 자동 업데이트 성공)
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-21.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P21 행 모두 체크

---

### Milestone 8: 출시 준비 (Launch Readiness) — 3주

P21(패키징) 완료 후 앱이 "설치는 되는" 상태. M8에서 **실사용 수준 품질**로 끌어올리고 공식 출시.

---

### Phase 22: 국제화(i18n) + 접근성(a11y) + 성능 벤치마크

**Goal**: 한글/영어 동시 지원, VoiceOver 전 경로 통과, 성능 기준선 확립. 출시 품질 보장.
**Estimated Time**: 5-6일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 22.1**: `LocalizationTests` — 모든 사용자 노출 문자열이 `String(localized:)` 통해 참조
- [ ] **Test 22.2**: `AccessibilityTests` — VoiceOver 레이블, heading 구조
- [ ] **Test 22.3**: `PerformanceBenchmarkTests` — 앱 시작, 디스패치, 대용량 스레드 렌더링
- [ ] **Test 22.4**: `DarkModeSnapshotTests` — 모든 주요 화면 다크/라이트 스냅샷

**🟢 GREEN**

- [ ] **Task 22.5**: `Localizable.xcstrings` (String Catalog) 생성
- [ ] **Task 22.6**: 모든 `"..."` 사용자 문자열을 `String(localized:)` 로 교체
- [ ] **Task 22.7**: 한글 ko / 영어 en 번역 완성
- [ ] **Task 22.8**: 숫자/날짜 포맷 로케일 처리 (`Date.FormatStyle`, `Decimal`)
- [ ] **Task 22.9**: VoiceOver 레이블 전 화면 추가 (`.accessibilityLabel`, `.accessibilityHint`)
- [ ] **Task 22.10**: Dynamic Type 대응 (`.font(.body)` 등 의미 기반)
- [ ] **Task 22.11**: High Contrast 모드 대응
- [ ] **Task 22.12**: 키보드만으로 전체 앱 사용 가능 검증 (Focus management)
- [ ] **Task 22.13**: 성능 벤치마크 스크립트 (`scripts/bench.sh`)
  - 앱 콜드 스타트 시간 (< 1000ms)
  - 디스패치 왕복 시간 (< 30s with Claude)
  - 1000턴 토론 스크롤 성능 (60fps 유지)
  - 메모리 풋프린트 (idle < 200MB, 10폴더 < 500MB)
- [ ] **Task 22.14**: 기준선 기록 (`docs/benchmarks/baseline.json`)

**🔵 REFACTOR**

- [ ] **Task 22.15**: 누락된 문자열 Xcode 경고 해결
- [ ] **Task 22.16**: 접근성 감사 리포트 작성 (`docs/audits/a11y-v1.md`)

#### Quality Gate ✋

- [ ] 시스템 언어 영어로 변경 시 UI 영어로 정상 표시
- [ ] VoiceOver로 핵심 플로우(폴더 추가, 메시지 전송, 토론 시작) 완주 가능
- [ ] 벤치마크 모두 목표 달성
- [ ] 다크/라이트 모드 스냅샷 회귀 없음

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / security / **performance** / test-quality / **ux** / **a11y-specialist** / docs) + must-fix 반영 _(a11y-specialist 리뷰어 추가 필수)_
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (VoiceOver 수동 체크, 언어 전환 수동 체크)
- [ ] Step 5: 🔄 Regression Check
- [ ] Step 6: 📐 Architecture Compliance
- [ ] `docs/reviews/phase-22.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P22 행 모두 체크

---

### Phase 23: 베타 테스트 + 법무 + 런칭 준비

**Goal**: 실사용자 피드백 수집, 법적 요건 충족, 런칭 인프라 구축. v1.0 출시 완료.
**Estimated Time**: 5-7일
**Status**: ⏳ Pending

#### Tasks

**🔴 RED**

- [ ] **Test 23.1**: `FeedbackSubmissionTests` — 앱 내 피드백 폼 동작
- [ ] **Test 23.2**: `CrashReporterTests` — 크래시 핸들러가 로그를 Diagnostics에 포함
- [ ] **Test 23.3**: `DataMigrationTests` — v0.x → v1.0 데이터 형식 이동 (가상)
- [ ] **Test 23.4**: `PrivacyPolicyAcknowledgementTests` — 동의 플래그 저장

**🟢 GREEN**

- [ ] **Task 23.5**: 앱 내 **피드백 제출** 기능 (메뉴 → Help → Send Feedback)
  - 시스템 정보 자동 첨부 (macOS 버전, 앱 버전, 감지된 CLI 목록)
  - 진단 번들 첨부 옵션
- [ ] **Task 23.6**: **크래시 리포터** — Apple의 `NSSetUncaughtExceptionHandler` + signal handlers로 스택트레이스 캡처, 다음 실행 시 로컬 표시
- [ ] **Task 23.7**: **데이터 마이그레이션 프레임워크** — `SchemaVersion` 개념, `Migrator` 프로토콜, 앱 시작 시 자동 실행
- [ ] **Task 23.8**: **개인정보처리방침** (Privacy Policy) 작성 — 로컬 전용, 외부 전송 없음 명시
- [ ] **Task 23.9**: **이용약관** (Terms of Service) 작성 — AS-IS, 보증 없음, MIT 라이선스
- [ ] **Task 23.10**: **라이선스 화면** — 번들된 오픈소스 라이선스 목록 (Sparkle, SwiftTerm 등)
- [ ] **Task 23.11**: **랜딩 페이지** — `docs/website/` 정적 HTML (GitHub Pages) — 다운로드 링크, 스크린샷, 핵심 기능 소개
- [ ] **Task 23.12**: **비공개 베타** 실행 (TestFlight는 Mac App Store 필요, 우리는 DMG 직배)
  - 3-5명 지인/커뮤니티에게 v0.9 DMG 공유
  - 피드백 수집 (GitHub Issues 또는 폼)
  - 최소 1주 테스트
- [ ] **Task 23.13**: **공개 베타** — GitHub Releases에 v0.9 태그, README에 "Public Beta" 뱃지
- [ ] **Task 23.14**: **출시 블로그 글** — Medium/Substack/개인 블로그에 "Why Maestro?" 에세이
- [ ] **Task 23.15**: **릴리즈 v1.0.0** — 태그 푸시, Sparkle appcast 업데이트, 공지

**🔵 REFACTOR**

- [ ] **Task 23.16**: 베타 피드백 기반 급한 버그 fix (별도 서브 phase)
- [ ] **Task 23.17**: 문서 최종 정리 (README, CONTRIBUTING, ARCHITECTURE)

#### Quality Gate ✋

- [ ] 최소 3명의 베타 테스터가 앱 정상 사용 완료 보고
- [ ] 심각한 크래시/데이터 손실 0건
- [ ] 크래시 리포터가 테스트 크래시 포착 + 다음 실행 시 표시
- [ ] Privacy Policy / ToS / License 문서 GitHub Pages에 공개
- [ ] GitHub Releases v1.0.0 태그 생성 + DMG 다운로드 가능
- [ ] 최소 1개 외부 커뮤니티(HN/Reddit/X)에 런칭 공지 완료

**🔬 Review & Verification** (→ [Phase Completion Protocol](#-phase-completion-protocol-모든-phase-공통) 6단계 적용):

- [ ] Step 1: 🔍 Self Code Review 완료
- [ ] Step 2: 👥 `/team` 멀티 리뷰 (architecture / **security** / performance / test-quality / **ux** / **legal-reviewer** / docs) + must-fix 반영 _(legal-reviewer: Privacy/ToS 텍스트 감수)_
- [ ] Step 3: ✨ `/simplify` 리뷰 + 제안 반영
- [ ] Step 4: 🧩 Integration Verification (신규 macOS 머신에 DMG 설치 end-to-end)
- [ ] Step 5: 🔄 Regression Check (최종)
- [ ] Step 6: 📐 Architecture Compliance (최종)
- [ ] `docs/reviews/phase-23.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** P23 행 모두 체크

---

## ⚠️ Risk Assessment

| Risk                                            | Probability | Impact | Mitigation Strategy                                                                                |
| ----------------------------------------------- | :---------: | :----: | -------------------------------------------------------------------------------------------------- |
| **Swift 학습 곡선**                             |     중      |   중   | Phase 1 여유 있게. Swift by Tutorials / Stanford CS193p 참고. 초반 페어 프로그래밍                 |
| **CLI 출력 포맷 변경** (Claude/Aider 업데이트)  |     중      |   중   | Adapter별 버전 감지 + 폴백 파서. 정기 통합 테스트 (매주 실행)                                      |
| **macOS 버전 호환성** (Sonoma vs Sequoia)       |     낮      |   중   | CI에서 두 버전 모두 테스트. minimum 14.0 명시                                                      |
| **노타리제이션 실패**                           |     낮      |   높   | Phase 21에 충분한 시간. Apple Developer 문서 숙지. 테스트 빌드 초반부터                            |
| **자동 업데이트 불안정**                        |     중      |   높   | Sparkle 공식 샘플 그대로 시작. rollout 속도 느리게                                                 |
| **사용자 CLI 환경 다양성**                      |     높      |   중   | 견고한 감지 로직 (PATH 풀 스캔, 여러 경로 시도). 친절한 에러 메시지                                |
| **SwiftUI 성능 이슈** (긴 토론 렌더링)          |     중      |   중   | LazyVStack, 가상화, 메시지 당 ID 안정적                                                            |
| **장기 프로젝트 피로**                          |     중      |   높   | Milestone 단위 데모. 매 2주 "보여줄 거 하나" 규칙                                                  |
| **의존성 업데이트 브레이킹 변경**               |     낮      |   중   | `Package.resolved` 커밋. Dependabot PR 주 1회 리뷰                                                 |
| **Keychain API 복잡도**                         |     낮      |   중   | Apple 공식 샘플 기반. 오픈소스 래퍼 참고 (`KeychainAccess` 등)                                     |
| **한글/유니코드 엣지 케이스**                   |     중      |   낮   | Phase 8 UI 테스트에 한글 테스트 케이스 필수                                                        |
| **디스크 공간 누수** (토론/스레드 무한 누적)    |     중      |   낮   | Phase 19 설정에 "30일 경과 자동 삭제" 옵션                                                         |
| **Swift 6 Strict Concurrency 컴파일 에러 연쇄** |     중      |   중   | Phase 1부터 `Sendable` 준수로 설계. 문제 커지기 전 즉시 해결. Xcode strict concurrency 옵션 활성화 |
| **베타 사용자 수 부족** (테스터 3명 미만)       |     중      |   중   | 커뮤니티(r/MachineLearning, HN) 사전 티저. Phase 23 전 2주 모집                                    |
| **크래시 리포트 누락/무한 루프**                |     낮      |   높   | 크래시 핸들러 자체 테스트 필수 (의도적 크래시 트리거). 2차 크래시 방지 가드                        |
| **데이터 마이그레이션 버그**                    |     낮      |   높   | 각 버전 업그레이드마다 마이그레이션 테스트 필수. 실패 시 자동 백업 후 롤백                         |
| **법무/저작권 문제** (번들된 OSS 라이선스 누락) |     낮      |   높   | Phase 23에서 전체 의존성 라이선스 감사. `swift package show-dependencies` 활용                     |
| **VoiceOver로 도달 불가 영역**                  |     중      |   중   | Phase 22에서 전수 감사. 개발 중에도 주요 컴포넌트마다 a11y 레이블 필수                             |
| **i18n 누락 문자열**                            |     중      |   낮   | String Catalog 자동 검출 + Phase 22 감사. "hardcoded string" lint 규칙                             |
| **앱 이름 "Maestro" 상표권 충돌**               |     중      |   높   | 사전 USPTO/KIPRIS 검색. 충돌 시 대안 준비 (Concord, Bridgehead 등 이미 후보 있음)                  |
| **macOS 15/16 업그레이드로 SwiftUI API 변경**   |     중      |   중   | CI에서 `@available` 체크. 베타 SDK 주기적 컴파일 확인                                              |

---

## 🔄 Rollback Strategy

### Milestone 단위 롤백

**M1 실패**: 프로젝트 scaffolding만 남음. 아키텍처 재검토.
**M2 실패**: Claude Adapter만 떼어내고 다른 Adapter 전략 재검토.
**M3 실패**: 멀티벤더 전략 포기, Claude 전용 앱으로 스코프 축소.
**M4 실패**: 컨트롤 타워 없이 단순 멀티 채팅 앱으로 출시 고려.
**M5 실패**: 토론 기능 v2로 연기.
**M6 실패**: Cmd+K 없이 메뉴로만, v1 출시.
**M7 실패**: 공식 배포 대신 GitHub Releases의 unsigned DMG로 기술 베타.
**M8 실패**: i18n/a11y 축소판으로 v1.0 한국어 전용 출시. 베타 없이 v1.1에 반영.

### Phase 단위 롤백

각 Phase 시작 전 `git tag phase-<N>-start` 찍어두고 실패 시 `git reset --hard`로 복구.

---

## 📊 Progress Tracking

### Milestone 진행 상황

| Milestone       | Phases |   Status   | 완료일 |
| --------------- | :----: | :--------: | :----: |
| M1: 기반        |  P1-5  | ⏳ Pending |   -    |
| M2: 첫 에이전트 |  P6-8  | ⏳ Pending |   -    |
| M3: BYOA 증명   | P9-10  | ⏳ Pending |   -    |
| M4: 컨트롤 타워 | P11-13 | ⏳ Pending |   -    |
| M5: 토론 엔진   | P14-15 | ⏳ Pending |   -    |
| M6: 파워유저 UX | P16-18 | ⏳ Pending |   -    |
| M7: 제품화      | P19-21 | ⏳ Pending |   -    |
| M8: 출시 준비   | P22-23 | ⏳ Pending |   -    |

**Overall Progress**: 0% (0 / 23 phases)

### Time Tracking

| Phase     |        Estimated         | Actual |      Variance       |
| --------- | :----------------------: | :----: | :-----------------: |
| P1        |          3-4일           | ~3시간 | -2.5일(scaffolding) |
| P2        |          4-5일           |   -    |          -          |
| P3        |           5일            |   -    |          -          |
| P4        |          4-5일           |   -    |          -          |
| P5        |           3일            |   -    |          -          |
| P6        |           4일            |   -    |          -          |
| P7        |           5일            |   -    |          -          |
| P8        |           5일            |   -    |          -          |
| P9        |           5일            |   -    |          -          |
| P10       |           5일            |   -    |          -          |
| P11       |           5일            |   -    |          -          |
| P12       |          5-6일           |   -    |          -          |
| P13       |           5일            |   -    |          -          |
| P14       |           5일            |   -    |          -          |
| P15       |           5일            |   -    |          -          |
| P16       |          4-5일           |   -    |          -          |
| P17       |           4일            |   -    |          -          |
| P18       |          3-4일           |   -    |          -          |
| P19       |           5일            |   -    |          -          |
| P20       |           5일            |   -    |          -          |
| P21       |           5일            |   -    |          -          |
| P22       |          5-6일           |   -    |          -          |
| P23       |          5-7일           |   -    |          -          |
| **Total** | **~105-115일 (약 20주)** |   -    |          -          |

---

## 📝 Notes & Learnings

### Implementation Notes

(Phase 진행하며 기록)

### Blockers Encountered

(이슈 발생 시 기록)

### Improvements for Future Plans

(회고에서 기록)

### Decisions Log

| Date       | Decision                              | Rationale                                                                     |
| ---------- | ------------------------------------- | ----------------------------------------------------------------------------- |
| 2026-04-25 | Maestro로 이름 확정                   | 오케스트라 지휘자 비유, 기억하기 쉬움                                         |
| 2026-04-25 | SwiftUI/macOS 전용 v1                 | 네이티브 감각 우선, 크로스플랫폼은 v2+                                        |
| 2026-04-25 | CLI 번들링 안 함                      | 사용자가 brew로 직접 설치 (BYOA 진정성)                                       |
| 2026-04-25 | PTY는 쉘 탭에만                       | 오케스트레이션은 Process + Pipe로 충분                                        |
| 2026-04-25 | 23 phases / 약 5개월 (20주)           | 완벽한 구현 + i18n/a11y/베타/법무 포함                                        |
| 2026-04-25 | Swift 6 Strict Concurrency from day 1 | 3-4개월 프로젝트에 동시성 부채 쌓이지 않도록                                  |
| 2026-04-25 | 로컬 크래시 리포터 (외부 서비스 X)    | 프라이버시 우선, 오프라인 가능, 진단 번들로 사용자 수동 전송                  |
| 2026-04-25 | MIT 라이선스                          | 어댑터 에코시스템 성장 유도                                                   |
| 2026-04-25 | 6단계 Phase Completion Protocol       | Self + /team + /simplify + Integration + Regression + Architecture Compliance |
| 2026-04-25 | Per-phase 리뷰 리포트 `docs/reviews/` | 사후 회고 + 패턴 축적                                                         |

---

## 📚 References

### Swift/SwiftUI 학습

- [Apple Swift Book](https://docs.swift.org/swift-book/)
- [Stanford CS193p](https://cs193p.sites.stanford.edu/) (SwiftUI)
- [Swift by Sundell](https://www.swiftbysundell.com/)
- [Hacking with Swift](https://www.hackingwithswift.com/)

### 도구/프레임워크

- [SwiftTerm (GitHub)](https://github.com/migueldeicaza/SwiftTerm)
- [Sparkle](https://sparkle-project.org/)
- [swift-argument-parser](https://github.com/apple/swift-argument-parser)
- [swift-log](https://github.com/apple/swift-log)

### 레퍼런스 구현 (ControlKim 전작)

- `/Users/gimgyeong-won/Desktop/kax/control-kim/` — PoC / 기능 검증된 프로토타입
- 재사용 가능한 패턴:
  - `terminalRouting.ts` (Swift로 포팅)
  - `jsonlTail` 증분 읽기 패턴
  - envelope 봉투 개념
  - 세션 재사용 로직

### Apple 문서

- [Code Signing Guide](https://developer.apple.com/documentation/security/code_signing_services)
- [Notarization](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Keychain Services](https://developer.apple.com/documentation/security/keychain_services)

### AI Agent 관련

- [Claude Code Docs](https://docs.anthropic.com/claude/docs/claude-code)
- [Aider Docs](https://aider.chat/docs/)
- [Model Context Protocol](https://modelcontextprotocol.io/)

---

## ✅ Final Checklist

**Before marking plan COMPLETE**:

- [ ] All **23 phases** completed with quality gates passed
- [ ] 모든 Phase의 **6단계 리뷰 & 검증** 통과 (Self / /team / /simplify / Integration / Regression / Architecture)
- [ ] 모든 `docs/reviews/phase-N.md` 리뷰 리포트 저장
- [ ] **Phase별 리뷰 트래커** 표 전체 체크 완료
- [ ] 2+ vendor agents working (Claude + Aider minimum)
- [ ] Full end-to-end: dispatch → reply → relay → discussion
- [ ] macOS installer (.dmg) signed + notarized
- [ ] Auto-update working (Sparkle appcast live)
- [ ] Test coverage: domain ≥90%, app ≥75%, E2E critical flows
- [ ] Onboarding tested with fresh macOS user (친구/가족)
- [ ] Performance benchmarks 전부 목표 달성 (앱 시작 <1s, 디스패치 <30s, 1000턴 토론 60fps)
- [ ] Security: API 키 Keychain 전용, 로그에 시크릿 없음
- [ ] Accessibility (P22): VoiceOver 핵심 경로 완주, Dynamic Type, High Contrast
- [ ] i18n (P22): 한글/영어 모든 노출 문자열 완성
- [ ] 크래시 리포터 동작 검증 (의도적 크래시 → 다음 실행 시 표시)
- [ ] 베타 (P23): 최소 3명 외부 테스터 피드백 반영
- [ ] 법무 (P23): Privacy Policy / ToS / OSS 라이선스 문서 공개
- [ ] Documentation: README, CONTRIBUTING, ARCHITECTURE.md
- [ ] 공개 랜딩 페이지 (GitHub Pages) 배포
- [ ] 첫 공개 릴리즈 v1.0.0 태그 + 공지 블로그

---

**Plan Status**: ⏳ Pending (승인 대기)
**Next Action**: 사용자 승인 후 Phase 1 시작
**Blocked By**: None
