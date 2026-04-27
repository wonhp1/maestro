# 🎼 Maestro

> **AI 코딩 에이전트 공용 지휘소** — Claude, Cursor, Aider 같은 서로 다른 AI CLI 에이전트들을 한 팀으로 지휘하는 macOS 네이티브 앱.

**Status**: ⏳ Phase 1 시작 전 (계획 완료)

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

> 🚧 아직 릴리즈 전. v1.0 목표: 2026-09.

릴리즈 후:

```bash
# Homebrew Cask (예정)
brew install --cask maestro

# 또는 직접 다운로드
# https://github.com/<user>/maestro/releases
```

**사전 요구사항**: 참여시킬 에이전트 CLI를 사용자가 직접 설치해야 함.

```bash
# 예: Claude
brew install claude

# 예: Aider
pip install aider-chat
```

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

MIT (예정)

## 🙏 Credits

- 영감: Claude Desktop, Letta (MemGPT), ControlKim
- 의존성: SwiftTerm, Sparkle

---

**만든 이유**: AI 에이전트들은 이미 똑똑한데, 각자 자기 상자 안에 갇혀 있어요. Maestro는 그 상자들을 열고 서로 이야기하게 만듭니다.
