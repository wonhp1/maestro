# S16: Multi-vendor Orchestration — Claude + Codex + Gemini 동시 운영

**v0.9.0 신규 시나리오** — 3개 어댑터 동시 폴더 등록 + control tower 라우팅.

## 사전 조건

- Maestro v0.9.0
- 4개 어댑터 모두 인증 완료 (Claude, Codex, Gemini, optional Aider)

## 절차

1. 폴더 3개 추가:
   - `~/sandbox/claude-folder` (Claude 어댑터)
   - `~/sandbox/codex-folder` (Codex 어댑터)
   - `~/sandbox/gemini-folder` (Gemini 어댑터)
2. 각 폴더에서 첫 메시지 보내서 정상 응답 확인
3. Control tower 진입 (Cmd+0)
4. 각 폴더 panel 이 sidebar 에 나열됨 확인
5. Control 의 chat 에 dispatch 명령:
   ```
   @claude-folder Tell me 'claude here'
   @codex-folder Tell me 'codex here'
   @gemini-folder Tell me 'gemini here'
   ```
6. 3개 동시 dispatch → 각 어댑터가 병렬 실행 → 응답 수신

## 기대 결과

- ✅ 3개 panel 이 모두 활성 상태
- ✅ Dispatch arrow visualization 이 control → 각 폴더로 그려짐
- ✅ 각 응답이 비동기로 도착 (어댑터별 latency 다름 — Gemini Flash 가 가장 빠름)
- ✅ Inbox 에 3개 응답 모두 수집됨
- ✅ Maestro CPU/메모리 사용량 60분 idle 후도 안정 (각 ptyPool 자동 정리)

## 차이점 (어댑터별)

| 어댑터 | 응답 시간 | Tool 사용               | 비용             |
| ------ | --------- | ----------------------- | ---------------- |
| Claude | ~5-10s    | yes (rich)              | API/Pro/Max      |
| Codex  | ~5-15s    | yes (command_execution) | ChatGPT Plus/Pro |
| Gemini | ~3-5s     | TBD                     | Free tier        |

## 검증

- ✅ 한 어댑터 실패해도 다른 어댑터 영향 X (격리)
- ✅ 같은 prompt 보내서 응답 비교 가능 — UI 가 어댑터별 다른 응답 명확히 구분
