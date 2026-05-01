# 🎼 Maestro

> **AI 코딩 에이전트 공용 지휘소** — Claude / Codex / Gemini / Aider 같은 서로 다른 AI CLI 에이전트들을 한 팀으로 지휘하는 macOS 네이티브 앱.

**Status**: ✅ v0.11.0 — 공개 베타 (GitHub Releases 배포)

## 🤖 지원 어댑터 (v0.9.0 기준)

| 어댑터              | 모델                       | 인증                                                     |
| ------------------- | -------------------------- | -------------------------------------------------------- |
| **Claude Code**     | Claude 4.5 등              | OAuth (Pro/Max) 또는 ANTHROPIC_API_KEY                   |
| **Codex (OpenAI)**  | GPT-5.5, GPT-5.3-codex 등  | OAuth (ChatGPT Plus/Pro) 또는 OPENAI_API_KEY             |
| **Gemini (Google)** | Gemini 3 Flash, 2.5 Pro 등 | OAuth (자동) 또는 GEMINI_API_KEY (무료 tier 일 1500 req) |
| **Aider**           | 모든 LLM (BYO model)       | adapter 별                                               |

---

## 🎯 무엇인가

기존 AI 도구는 벤더 종속적입니다:

- **Claude Desktop** → Claude만
- **Cursor** → Cursor 내장만
- **Aider** → 자기 파이프라인만

Maestro는 그 위에 얹히는 **중립 지휘소**:

- 🎼 사용자가 지휘봉 쥐고 여러 AI를 팀으로 굴림
- 🏢 폴더마다 "전담 AI 비서" (CPO, CTO, 디자이너 등 역할 부여)
- 💬 에이전트끼리 지시/보고/토론 가능
- 🔌 BYOA (Bring Your Own Agent) — 당신이 설치한 CLI면 뭐든 참여

## 🎨 누구를 위한 것인가

- AI 에이전트를 **1인 팀**처럼 다루고 싶은 개발자
- 하나의 벤더에 묶이기 싫은 얼리어답터
- macOS 네이티브 감각 선호

## 🏗️ 기술 스택

- **SwiftUI + Swift 6.0+** (macOS 14+ 전용, Strict Concurrency)
- **Swift Package Manager**
- **XCTest** (TDD)
- **SwiftTerm** (쉘 탭)
- **Sparkle** (자동 업데이트)
- **로컬 JSON/JSONL + Keychain** (데이터 저장)

## 🧭 시작하기

### 사용자 (설치해서 쓰고 싶으면)

**시스템 요구사항**: macOS 14 (Sonoma) 이상, Apple Silicon 또는 Intel.

#### 1. 다운로드

[**최신 Release 페이지**](https://github.com/wonhp1/maestro/releases/latest) 에서
`Maestro-X.Y.Z.dmg` 를 다운로드하세요.

#### 2. 설치

1. 다운로드한 DMG 파일 더블클릭 → 마운트
2. **Maestro.app** 을 `Applications` 폴더로 드래그
3. **첫 실행 시**: macOS 가 "확인되지 않은 개발자" 경고를 띄울 수 있어요.
   해결: `Applications` 폴더에서 **우클릭 → 열기** (한 번만 하면 끝).
   - 또는 시스템 설정 → 개인 정보 보호 및 보안 → "그래도 열기"
   - Maestro 는 Apple Developer ID 로 코드 서명 + 노타리 됐지만, 일부
     macOS 환경에서 첫 실행만 한 번 허락이 필요할 수 있습니다.

#### 3. 첫 실행 — 환경 설정

Maestro 가 자동으로 필요한 CLI (Node, Claude / Codex / Gemini / Aider 중 원하는
것) 를 검사하고, 없으면 **"환경 자동 설치"** 버튼 한 번으로 설치해줍니다.

> **사용자 구독 활용**: ChatGPT Plus/Pro, Claude Pro/Max, Gemini AI Pro
> 구독자는 본인 구독으로 OAuth 로그인하면 Maestro 안에서 GPT-5 / Claude / Gemini
> 사용. API 키 별도 결제 불필요.

#### 4. 자동 업데이트

새 버전이 나오면 Maestro 메뉴 → **"Check for Updates…"** 로 받을 수 있어요
(Sparkle 통합).

### 개발자 (이 프로젝트에 기여하려면)

```bash
git clone <repo>
cd maestro
swift build
swift test
```

**필독**: [CLAUDE.md](./CLAUDE.md) 와 [docs/plans/PLAN_maestro.md](./docs/plans/PLAN_maestro.md)

## 📐 핵심 설계 원칙

1. **BYOA** — CLI는 사용자가 설치, Maestro는 어댑터만
2. **HITL** — 사람이 지휘자, 자율 에이전트 X
3. **로컬 완결** — 서버 없음, 외부 동기화 없음
4. **벤더 중립** — 어떤 결정도 "다른 에이전트에 OK여야 함" 원칙

## 📚 문서

- 📋 [계획서 (PLAN_maestro.md)](./docs/plans/PLAN_maestro.md) — **단일 진실 원천**
- 🧭 [CLAUDE.md](./CLAUDE.md) — AI 어시스턴트용 컨텍스트
- 📝 리뷰 기록 → [docs/reviews/](./docs/reviews/)
- 🎯 성능 기준선 → [docs/benchmarks/](./docs/benchmarks/)
- ♿ 접근성 감사 → [docs/audits/](./docs/audits/)

## 🎬 로드맵 (23 Phases / 20주)

| Milestone       | Phases  | 기간 | 상태 |
| --------------- | :-----: | :--: | :--: |
| M1: 기반        |  P1-P5  | 4주  |  ⏳  |
| M2: 첫 에이전트 |  P6-P8  | 2주  |  ⏳  |
| M3: BYOA 증명   | P9-P10  | 2주  |  ⏳  |
| M4: 컨트롤 타워 | P11-P13 | 3주  |  ⏳  |
| M5: 토론 엔진   | P14-P15 | 2주  |  ⏳  |
| M6: 파워유저 UX | P16-P18 | 2주  |  ⏳  |
| M7: 제품화      | P19-P21 | 2주  |  ⏳  |
| M8: 출시 준비   | P22-P23 | 3주  |  ⏳  |

## 🪴 이전 작품

**ControlKim** — Next.js 기반 프로토타입. Maestro는 ControlKim의 경험을 바탕으로 **네이티브 + 벤더 중립** 방향으로 새로 설계됨.

## 📜 License

[MIT](./LICENSE) — 자유롭게 사용 / 수정 / 재배포. 책임 없음.

## 🛟 지원

- 🐛 버그 / 기능 요청 → [GitHub Issues](https://github.com/wonhp1/maestro/issues)
- 🔒 보안 취약점 → [SECURITY.md](./SECURITY.md) 의 절차 따라 비공개 신고
- 📋 [개인정보 처리방침](./PRIVACY.md) · [이용약관](./TERMS.md) · [Third-party Licenses](./LICENSES.md)

## 🙏 Credits

- 영감: Claude Desktop, Letta (MemGPT), ControlKim
- 의존성: SwiftTerm, Sparkle

---

**만든 이유**: AI 에이전트들은 이미 똑똑한데, 각자 자기 상자 안에 갇혀 있어요. Maestro는 그 상자들을 열고 서로 이야기하게 만듭니다.
