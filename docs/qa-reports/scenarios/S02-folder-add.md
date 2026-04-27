# S02: 폴더 등록 (vendor picker + 자동 감지)

**상태**: ✅ PASS
**실행**: 2026-04-26 02:21 KST

## Action

사이드바 "폴더 추가" 클릭 → NSOpenPanel → ~/Desktop/sample/projects/cto 선택 → 폴더 선택 → vendor picker sheet → "추가" 클릭.

## Observe

**NSOpenPanel** 정상 표시 ("Maestro 에서 작업할 폴더를 선택하세요.").

**VendorPickerSheet**:

- 헤더: "어떤 에이전트를 사용할까요?" + 경로 `~/Desktop/sample/projects/cto`
- Aider:
  - "오픈소스 멀티 모델 (OpenAI / Claude / Gemini 등) 지원. git 자동 커밋 강점."
  - 빨간 ✗ 미설치
  - **자동 설치** 버튼 + `pip install aider-chat` + 도움말 → 링크
  - 라디오 disabled
- Claude Code (자동 선택, 강조):
  - "처음 쓰기 좋음" 파란 벳지
  - "Anthropic 의 공식 코딩 에이전트. 도구 사용이 강하고 처음 쓰기 좋아요."
  - 녹색 ✓ v2.1.118
  - "추가" 버튼 활성

추가 후:

- 사이드바에 cto (claude badge, 활성 dot) 행 추가
- 자동 선택 → 채팅 input 표시
- DispatchComposer 의 대상 picker 가 cto 로 갱신

**folders.json** 갱신 (새 entry 추가됨, adapterId="claude").

## Verdict

✅ **PASS** — Phase 2 + Phase 5 (친절 카피, 추천 벳지, 자동 설치 버튼) 모두 동작.
