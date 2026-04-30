# S17: 인앱 OAuth 로그인 (Codex / Gemini)

**v0.9.2 ~ v0.9.8 신규 시나리오** — 사용자가 터미널 안 거치고 Maestro 안에서
Codex / Gemini OAuth 인증 완주.

## 사전 조건

- Maestro v0.9.6 이상 설치 (Codex / Gemini 라우팅 fix 포함)
- Codex CLI 설치 — `npm install -g @openai/codex` 또는 Maestro 자동 설치
- Gemini CLI 설치 — `npm install -g @google/gemini-cli` 또는 Maestro 자동 설치
- 두 CLI 모두 인증 미완료 (`~/.codex/auth.json` / `~/.gemini/oauth_creds.json` 없음)
- 기본 브라우저 동작 정상

## 절차 — Codex

1. Maestro 실행 → 사이드바 "+ 폴더 추가" → 폴더 선택
2. Vendor picker 에서 **Codex (OpenAI)** 클릭
3. **인증 banner 표시 확인**: "Codex 로그인이 필요합니다." + "Maestro 로 로그인" 버튼
4. 버튼 클릭
5. **버튼 텍스트 변화**: "로그인 진행 중..." (disabled)
6. **브라우저 자동 오픈** (~3-5초 내) → `https://auth.openai.com/oauth/authorize?...`
7. 브라우저에서 ChatGPT 계정 로그인 + Maestro 권한 승인
8. Maestro 의 polling 이 인증 감지 → "로그인 성공" 메시지
9. "추가" 버튼 활성 → 폴더 등록

## 절차 — Gemini

1. Maestro 실행 → "+ 폴더 추가" → 폴더 선택
2. Vendor picker 에서 **Gemini (Google)** 클릭
3. 인증 banner: "Gemini 로그인이 필요합니다." + "Maestro 로 로그인" 버튼
4. 버튼 클릭
5. **stdin Y\n 자동 주입** (v0.9.5) → Gemini CLI 가 prompt 통과
6. **브라우저 자동 오픈** → `https://accounts.google.com/o/oauth2/...`
7. Google 계정 로그인 + 권한 승인
8. polling 인증 감지 → "로그인 성공"
9. "추가" 활성 → 폴더 등록

## 기대 결과

- ✅ 버튼 클릭만으로 브라우저 자동 오픈 (수동 URL 복사 불필요)
- ✅ "로그인 진행 중..." 동안 버튼 disabled — 중복 클릭 방지
- ✅ 인증 완료 후 banner 사라지고 "추가" 활성
- ✅ Codex / Gemini 모두 동일 UX 경험
- ✅ 인증 중에도 다른 어댑터 탭 전환 가능 (sheet 차단 X)

## 검증된 에러 케이스 (v0.9.8)

| 시나리오                                           | 표시 메시지                                                                             | 동작                   |
| -------------------------------------------------- | --------------------------------------------------------------------------------------- | ---------------------- |
| 5분 안에 로그인 안 함                              | "5분 내 로그인 안 됨. 기존 브라우저 탭은 닫고 다시 시도하세요."                         | subprocess 종료        |
| 브라우저에서 사용자 X                              | "로그인 취소됨"                                                                         | subprocess 정상 종료   |
| **브라우저 자동 오픈 실패** (기본 브라우저 미설정) | "브라우저를 열 수 없습니다. URL 을 클립보드에 복사했어요 — 직접 붙여넣어 로그인하세요." | URL 클립보드 자동 복사 |
| CLI subprocess 실패 (예: stdin 처리 오류)          | "실패: codex exit 1: <stderr 끝 200자>"                                                 | subprocess 종료        |

## 회귀 방지

- v0.9.4: subprocess stdout 캡처 시 CLI 의 자체 브라우저 오픈 작동 안 함 → URL 추출 + `NSWorkspace.open` 보완
- v0.9.5: Gemini 의 interactive `[Y/n]:` prompt 에 stdin Y\n 자동 주입
- v0.9.8: `NSWorkspace.open` 반환값 확인 → 실패 시 즉시 사용자 안내 + URL 클립보드 복사

## 관련 코드

- `Sources/MaestroCore/InteractiveAuthHelper.swift`
- `Sources/Maestro/Folders/VendorPickerSheet.swift` (`authMissingBanner`, `performLogin`)
- `Sources/MaestroCore/EnvironmentChecker.swift` (`checkCodexAuth` / `checkGeminiAuth` polling source)
