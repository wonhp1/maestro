# S15: Gemini 어댑터로 폴더 추가 + 첫 메시지

**v0.9.0 신규 시나리오** — Google Gemini CLI 어댑터 검증.

## 사전 조건

- Maestro v0.9.0 설치
- Gemini CLI 설치 (`npm install -g @google/gemini-cli`) — Maestro 자동 설치 가능
- Google 계정 OAuth (첫 실행 시 자동) 또는 GEMINI_API_KEY

## 절차

1. Maestro 실행 → "+ 폴더 추가" → 빈 폴더 선택
2. Vendor picker 에서 **Gemini (Google)** 선택
   - **추천 badge** 확인: "무료 tier 있음"
   - description: "Google 공식 CLI. 무료 tier (일 1,500 req) + 1M context 강점."
3. 인증 banner 확인 — `~/.gemini/oauth_creds.json` 있으면 통과, 없으면 안내
4. "추가" 클릭 → 폴더 등록
5. 첫 메시지: "Hello in 3 words"
6. **stream-json delta chunks** 수신 → UI 가 점진적 텍스트 표시 확인

## 기대 결과

- ✅ Gemini badge "무료 tier 있음" 노출
- ✅ delta=true chunk 마다 ResponseChunk(.text) 발행
- ✅ result event 에서 ResponseChunk(.completion) 수신
- ✅ 응답 시간 ~3-5초 (Flash 모델 기준)
- ✅ session_id + model 자동 캡처 → resolvedModel() 가 "gemini-3-flash-preview" 등 반환

## 큰 컨텍스트 검증 (1M context)

옵션: 큰 코드 파일 (수만 토큰) 에 대해 분석 요청 → Gemini 가 1M context 활용 확인.

## 검증된 에러 케이스

- ❌ trust 미신뢰 → `--skip-trust` 자동 적용으로 우회
- ❌ quota exceeded → 사용자 친화 메시지
