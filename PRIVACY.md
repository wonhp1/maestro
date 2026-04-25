# Maestro Privacy Policy

**Effective**: 2026-04-25
**Version**: 1.0

## 요약 (TL;DR)

Maestro 는 **로컬 전용 macOS 앱** 입니다. **사용자 데이터 / 메시지 / 폴더 내용 /
시크릿을 외부 서버로 전송하지 않습니다.** 모든 데이터는 본인 Mac 의
`~/Library/Application Support/Maestro/` + macOS Keychain 에만 저장됩니다.

## 1. 수집하는 정보

### 1.1 로컬 저장 (외부 전송 X)

- **폴더 메타데이터** (`folders.json`): 사용자가 등록한 작업 폴더 경로 + 표시 이름
- **세션 / 메시지 / 토론 로그** (`sessions/`, `threads/`, `inbox/`, `outbox/`):
  사용자와 AI 에이전트 간 메시지 envelope
- **설정** (`preferences.json`): 알림 on/off, 활성 어댑터, 디스패치 타임아웃 등
- **크래시 리포트** (`crashes/`): 스택 트레이스 (사용자 데이터 미포함)
- **API 키 / OAuth 토큰**: macOS Keychain 만 (디스크 평문 X)

### 1.2 외부 서버

Maestro 자체는 외부 서버를 호출하지 않습니다. 단:

- **AI 에이전트 호출** — Maestro 가 Claude Code / Aider 등 사용자 본인이 설치한
  CLI 를 spawn 합니다. 이 CLI 들은 각자 자신의 서비스 (Anthropic / OpenAI / 등)
  에 호출합니다. **이 호출의 데이터 정책은 각 서비스 의 약관 적용**.
- **자동 업데이트 (Phase 22+)** — Sparkle 이 `appcast.xml` URL 을 HTTPS GET 합니다.
  IP 주소 외 사용자 식별 정보 미전송. URL 호스팅 서버 (GitHub Pages 등) 의 access
  log 정책은 별도.

## 2. 사용자 데이터의 통제권

- **삭제**: `~/Library/Application Support/Maestro/` 폴더 삭제 → 모든 로컬 데이터 제거.
  Keychain 시크릿은 환경설정 → 에이전트 → API 키 비우기 또는 keychain access.app.
- **이동**: 폴더 그대로 다른 Mac 에 복사하면 그대로 동작.
- **내보내기**: 환경설정 → 고급 → "진단 번들 내보내기" — 시크릿 제외하고 전체 데이터를
  ZIP 으로 export.

## 3. 외부 공유 (사용자 자율)

- **피드백 제출** (Help → Send Feedback) — Maestro 는 시스템 정보 + 사용자 노트를
  payload 로 build 만 합니다. **자동 전송 X**. 사용자가 명시적으로 복사하여 GitHub
  Issues / 메일 등에 붙여넣어야 외부 공유됨.
- **진단 번들** — 사용자가 명시적으로 export 한 ZIP 을 외부에 공유할 책임은 사용자.
  ZIP 안에는 thread / envelope JSONL 이 있을 수 있으니 검토 후 공유.

## 4. 어린이 (Children)

Maestro 는 일반 개발자 도구 — 13세 미만 어린이를 대상으로 하지 않습니다.

## 5. 변경

본 정책 변경 시 GitHub repo (`PRIVACY.md` history) 에서 확인 가능. 중요한 변경은
앱 내 알림으로 안내.

## 6. 문의

GitHub Issues: https://github.com/wonhp1/maestro/issues
