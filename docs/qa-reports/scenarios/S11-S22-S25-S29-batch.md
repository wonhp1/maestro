# S11 / S15 / S16 / S17 / S22 / S25 / S29 — UX/Settings/Discussion 일괄

## S11: Discussion 시작 + list + detail

**상태**: ✅ PASS

- 사이드바 "새 토론" 클릭 → DiscussionStartSheet 표시 정상
- 헤더 + "여러 에이전트가 한 주제로 의견을 교환합니다. control 폴더가 결과를 종합해요."
- 주제 TextField + 참가자 (cto/cfo/cmo, control 자동 제외 ✓)
- "최소 2명 선택" 안내 + "0 선택" 카운터
- 발언 순서 segmented (라운드 로빈/랜덤)
- 최대 턴 수 slider 20 + "5-20 보통" hint
- 시작 버튼 disabled → 참가자 2개 체크 후 활성
- 시작 → 사이드바 "토론 1 진행 중" + 토론 행 (제목, 0/20) + orchestration bar "control → cto 진행 중"
- 1턴 후 cto → control 응답 보고함 도착, 자식 ChatView 에 표시
- 우클릭 → "토론 종료 + 제거" 정상 동작

## S15 + S16: Cmd+K 팔레트 + 슬래시 명령

**상태**: ⚠️ PARTIAL

- ✅ 팔레트 자체는 동작 (Window → 커맨드 팔레트 메뉴 클릭으로 열림)
- ✅ 폴더 전환 항목 (cfo/cmo/Control/cto, 단축키 ⌘1-4 표시)
- ✅ 슬래시 명령 자동 탐색 (`/changelog`, `/feature-planner`, `/find-hooks`, `/homepage-builder-kr` 등 ~/.claude/commands 모두)
- ❌ **단축키 ⌘K 자체로는 안 열림** (메뉴 클릭만)
- ❌ **항목 클릭/Enter 해도 액션 안 됨** (folder 전환 미발생)
- ❌ Esc 로 팔레트 닫기 안 됨 (sticky overlay)

→ **Active issue I-04** (HIGH): 팔레트 단축키 + 액션 + dismiss 미작동.

## S17: 단축키 (⌘1-9 / ⌘, / ⌘K)

**상태**: ❌ FAIL (메뉴 등록만 됨, 키 입력 미동작)

- 메뉴엔 ⌘1, ⌘K, ⌘, 표시
- 키보드로 직접 누르면: 메인 윈도우에 영향 X (팔레트만 가끔 열림)
- 메뉴 항목 마우스 클릭 시도 시: ⌘, → Settings 창 안 뜸 (또는 가려짐)

→ **Active issue I-05** (MED): ⌘1-9 폴더 전환 + ⌘, Preferences 단축키 미동작.

## S22: Preferences (4 탭)

**상태**: ❌ FAIL

- Maestro 메뉴 → "환경설정..." (⌘,) 또는 "Settings..." 클릭 → **창 안 뜸**
- ⌘, 단축키도 동작 X
- "환경설정..." 와 "Settings..." 두 메뉴 항목 동시 노출 (i18n 중복 — Korean + 영문 둘 다)

→ **Active issue I-06** (HIGH): Settings 창 자체가 안 열림. 핵심 UX 차단.

→ Bonus: **Active issue I-07** (cosmetic): Maestro 메뉴 항목 중복 (환경설정 + Settings).

## S25: 진단 번들 export + 피드백

**상태**: ⏭️ Skip (Settings 안 열려서 Advanced 탭 access X) / 피드백은 ✅

- Help → 피드백 보내기 → FeedbackComposer 정상:
  - "📨 피드백 보내기"
  - 설명: "외부 자동 전송 없음 안전"
  - 입력 + 미리보기 + 클립보드 복사 / GitHub Issues 열기
- Diagnostics 는 Settings (⌘,) Advanced 탭 안 — Settings 안 열리는 issue 의존, 확인 불가.

## S29: 폴더 영속성 (재시작 후 복원)

**상태**: ✅ PASS

- 4 폴더 등록 (Control + cfo + cmo + cto) 후 강제 종료 (`pkill -9 Maestro`)
- 재시작 → 4 폴더 모두 사이드바 복원, lastUsedAt 시간도 복원
- folders.json 갱신 정상

## S19: 표준 메뉴 (File/Edit/Maestro/Window/Help)

**상태**: ⚠️ PARTIAL

- ✅ Maestro 메뉴: About, 업데이트 확인 (실패 — I-02), 환경설정/Settings (액션 X — I-06), Services, Hide/Quit
- ✅ Window 메뉴: 커맨드 팔레트 항목 표시
- ✅ Help 메뉴: 도움말, 피드백 보내기 (정상)
- 다른 메뉴는 표준 macOS shell

## S18: 메뉴바 트레이

**상태**: ⏭️ Skip (이번 세션 검증 안 함 — 별도 시나리오로)
