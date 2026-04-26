# S01: 온보딩 (첫 실행 3-step)

**상태**: ✅ PASS (with cosmetic i18n issue noted)
**실행**: 2026-04-26 02:16 KST

## Action

clean App Support → cold launch → step 1 → 다음 → step 2 → 다음 → step 3 → 시작

## Observe

- **Step 1**: "Maestro 에 오신 걸 환영합니다 — Maestro 는 여러 AI 코딩 에이전트(Claude, Aider 등)를 화면에서 오케스트레이션하는 macOS 앱입니다." 페이지 인디케이터 (3 dots, 첫 dot 강조).
- **Step 2**: "에이전트 감지" — 감지됨: ✓ claude (녹색 체크) — PATH augment 동작 증명.
- **Step 3**: "첫 폴더 추가" — "작업할 폴더를 한 개 추가해 보세요. 나중에 사이드바에서 더 추가할 수 있습니다." + [폴더 추가] 버튼 + 이전/시작 버튼.
- "시작" 클릭 후 메인 UI 진입. 사이드바에 Control 폴더 자동 생성 (claude badge).

## Verdict

✅ **PASS** — 3-step 흐름 / 페이지 인디케이터 / 이전/다음/건너뛰기 / 시작 모두 정상.

## ⚠️ 비차단 이슈

- 윈도우 제목이 `window.main.title` 라는 literal 문자열로 표시됨. `String(localized:)` 키가 catalog 에 등록 안 됐거나 LocalizationValue 초기화에 버그. → **§ Active Issue I-01** 생성.
