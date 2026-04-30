# S14: Codex 어댑터로 폴더 추가 + 첫 메시지

**v0.9.0 신규 시나리오** — OpenAI Codex CLI 어댑터의 end-to-end 동작 검증.

## 사전 조건

- Maestro v0.9.0 설치
- Codex CLI 설치 (`npm install -g @openai/codex`) — Maestro 가 자동 설치 가능
- ChatGPT Plus/Pro 구독 또는 OPENAI_API_KEY (OAuth: `codex login`)

## 절차

1. Maestro 실행
2. 사이드바 "+ 폴더 추가" 클릭
3. 폴더 picker 에서 `~/sandbox/test-codex` 같은 빈 폴더 선택
4. Vendor picker sheet 가 4개 어댑터 표시 — Claude / Aider / Codex (OpenAI) / Gemini (Google)
5. **Codex 행 클릭** → "추가" 버튼 활성/비활성 확인
   - Codex CLI 미설치 → "미설치" 표시 + "자동 설치" 버튼
   - 인증 미완료 → 주황 banner: "Codex 인증이 필요합니다. 터미널에서 `codex login` 실행하세요."
6. 자동 설치 (필요 시) → npm install -g @openai/codex 진행 → 자동 재검사
7. 인증 완료 후 "추가" 클릭 → 폴더 등록
8. 폴더 chat 영역 진입 → 첫 메시지 전송: "Hello, reply with 'codex-ok'"
9. 약 5-10초 후 응답 수신 — `agent_message` text chunk → UI 표시

## 기대 결과

- ✅ Vendor picker 에 Codex 노출 + description: "OpenAI 공식 CLI. ChatGPT Plus/Pro 구독으로 GPT-5/o1 사용 가능."
- ✅ 인증 banner 가 명확히 안내
- ✅ 첫 메시지 응답이 5-15초 내 도착
- ✅ Maestro 로그에 thread_id 캡처됨 (resume 흐름 준비)
- ✅ 두 번째 메시지는 같은 thread_id 로 resume — 컨텍스트 유지

## 검증된 에러 케이스

- ❌ 401 Unauthorized → 사용자 친화 메시지 ("OpenAI 인증 실패: 401 Unauthorized")
- ❌ codex CLI 미설치 → 자동 설치 버튼 노출
- ❌ malformed stdout → "Codex 응답을 읽을 수 없습니다" + stderr snippet 포함
