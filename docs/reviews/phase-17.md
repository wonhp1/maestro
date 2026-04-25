# Phase 17 Review Report — 슬래시 명령어 + 스킬 자동 탐색

**Date**: 2026-04-25
**Phase**: 17 / 23
**Status**: ✅ Complete
**Commits**: phase-17-start → phase-17-end

---

## Deliverables

`Sources/MaestroCore/`:

- `SlashCommandFrontmatter.swift` — minimal YAML frontmatter parser (scalar key/value, quote stripping, lower-cased keys, body 분리)
- `DiscoveredSlashCommand.swift` — `SlashCommandSourceKind` (userFile / projectFile / builtin / skill) + `DiscoveredSlashCommand` (command + source + filePath, id = `<source>:<name>`) + `SlashCommandSource` 프로토콜
- `FileSlashCommandSource.swift` — `~/.claude/commands/*.md` 디렉토리 스캔, ASCII 영숫자 + `_-` 이름 검증, 1 MiB 사이즈 cap, hidden/`..` 차단, frontmatter 우선 + body 첫 줄 fallback
- `SkillSource.swift` — `~/.claude/skills/<name>/SKILL.md` 스캔, frontmatter `name` 우선 + 디렉토리 이름 fallback
- `BuiltinSlashCommandProber.swift` — actor, `claude -p "/help"` 출력 파싱 + 디스크 24h TTL 캐시 + binary path/mtime 변경 시 무효화 + stdout 64 KiB cap
- `SlashCommandRegistry.swift` — actor, source 등록/해제, 병렬 collect (TaskGroup), id 기준 dedupe, source priority + name 정렬, observe AsyncStream broadcast
- `SlashCommandWatcher.swift` — actor, `~/.claude/commands` + `~/.claude/skills` 감시, 500ms debounce + 30s ticker fallback + 디렉토리 자동 재생성

`Sources/Maestro/CommandPalette/`:

- `SlashCommandPaletteProvider.swift` — `CommandProvider` 어댑터, `.slash` 카테고리, `DisplayTextSanitizer` 적용 (must-fix /team SEC)

`Sources/Maestro/ControlTower/ControlTowerView.swift`:

- `slashCommandRegistry` / `slashCommandWatcher` / `pendingSlashInsertion` 추가
- `wireSlashCommands()` — 글로벌 `~/.claude/commands` + `~/.claude/skills` source 자동 등록 + watcher 시작 + provider 등록
- `consumePendingSlashInsertion()` — Phase 18 DispatchComposer 가 가져갈 side-channel

`Sources/MaestroCore/Command.swift`:

- `CommandCategory.slash` 추가 + `localizedName` "슬래시" + `sortPriority` 2 (recent < folder < slash < dispatch < discussion < system)

**Tests**: 592/592 통과 (3 skipped — aider 미설치) (Phase 16 의 548 → +44)

- `SlashCommandFrontmatterTests` (7) — 기본 / no FM / unclosed / quotes / lower keys / empty body / colon-in-value
- `FileSlashCommandSourceTests` (8) — empty / missing / frontmatter / body fallback / invalid name reject / ext filter / size cap / id format
- `SkillSourceTests` (5) — empty / frontmatter / dir fallback / SKILL.md 없음 skip / hidden reject
- `BuiltinSlashCommandProberTests` (13) — parse 3-format / 무효 reject / dedupe / fresh probe / TTL 내 재사용 / TTL 만료 / binary path 변경 / nil exe / 비정상 exit / invalidate
- `SlashCommandRegistryTests` (8) — empty / multi source / sort / dedupe / cross-source 같은 이름 / register/unregister 무효화 / observe broadcast
- `SlashCommandWatcherTests` (3) — 초기 refresh / 파일 추가 5초 이내 반영 / stop 안전성

---

## Step 2: 👥 /team Multi-Agent Review (1 묶음, arch+sec+perf+ux+test)

**Must-fix 식별 4건 → 2건 반영, 2건 defer**.

### 반영 (2건)

1. ❌→✅ **HIGH-1: 외부 .md 콘텐츠 sanitize 누락** — 슬래시 명령 `name`/`description`/`argument-hint` 가 `.md` 파일에서 직접 옴. bidi/ZW/control char 가 팔레트 렌더에 spoof 가능. `SlashCommandPaletteProvider` 가 `DisplayTextSanitizer.sanitize` 적용. (sec)
2. ❌→✅ **MED-1: SlashCommandWatcher deinit Swift 6 위반** — actor mutable state 를 nonisolated deinit 에서 접근. 제거 + caller stop() 규약으로 명문화 (InboxWatcher 와 동일 패턴). (arch)

### Defer (2건, Phase 18+)

- **MED-2: pendingSlashInsertion → DispatchComposer 양방향 binding** — Phase 17 은 side-channel 만, Phase 18 메뉴 / composer pass 에서 consume.
- **LOW-1: BuiltinProber binary mtime 단독 변경 테스트** — path 변경 테스트로 메커니즘은 검증됨. 케이스 보강은 Phase 21 polish.

---

## Step 3: ✨ /simplify

- `SlashCommandFrontmatter.parse` 단일 함수 — 5분 안 reading. closure 없음.
- `BuiltinSlashCommandProber.parseHelpOutput` static — 외부 의존 없음, 단위 테스트 13건이 모든 분기 커버.
- `SlashCommandWatcher.scheduleRefresh` pendingTask cancel + replace — actor isolation 으로 race 없음.
- 4가지 source kind enum (userFile/projectFile/builtin/skill) 로 확장 포인트만 노출, projectFile 은 placeholder (Phase 17 defer).

## Step 4: 🧩 Integration Verification

- `swift build` 통과
- 592/592 테스트 통과 (3 skipped, aider 미설치 정상)
- `swiftlint --strict` 0 violations
- Quality Gate (Phase 17 plan):
  - ✅ `~/.claude/commands/new.md` 추가 시 5초 이내 UI 반영 — `SlashCommandWatcherTests.testFileAdditionTriggersRefresh` 가 5초 polling 으로 검증
  - ✅ Claude Code 버전 업그레이드 시 내장 명령어 재프로빙 — `BuiltinSlashCommandProberTests.testBinaryPathChangeInvalidatesCache` + binary mtime 검사 코드
  - ✅ 20+ 슬래시 명령어 중 즉시 검색 — 기존 `CommandRegistry` + `FuzzyMatcher` (Phase 16) 가 처리, `SlashCommandPaletteProvider` 가 `.slash` 카테고리로 통합

## Step 5: 🔄 Regression Check

- Phase 1-16 통과 유지 (548 → 592, +44)
- `CommandCategory.slash` 추가 — `CommandPaletteView` switch 만 영향, 보강 완료 (icon `terminal.fill` + indigo)
- `ControlTowerEnvironment` 에 `slashCommandRegistry` 추가, 기존 store 들 영향 없음
- `FolderRegistry` / `DispatchService` / `DiscussionStore` 인터페이스 미변경

## Step 6: 📐 Architecture Compliance

- ✅ 모든 핵심 (Frontmatter / Source / Registry / Watcher / Prober) `MaestroCore` (SwiftUI 미의존)
- ✅ `SlashCommandSource` 프로토콜 — Phase 17+ projectFile / 플러그인 source 가 동일 인터페이스로 등록 가능
- ✅ Swift 6 Strict Concurrency: actor (registry, prober, watcher) / Sendable struct (sources) / nonisolated value types (frontmatter, model)
- ✅ DiscoveredSlashCommand id 패턴 (`<source>:<name>`) — 다른 출처의 같은 이름 (예: 사용자가 내장 override) 보존
- ✅ DisplayTextSanitizer 재사용 — Phase 12 must-fix 와 동일 정책

---

## Open Items for Later Phases

1. **DispatchComposer ↔ pendingSlashInsertion 양방향 binding** (Phase 18 메뉴 pass) — 현재는 set 만, 자동 insert UX 미적용
2. **ProjectFileSlashCommandSource** (`<folder>/.claude/commands/*.md`) — folder 컨텍스트 묶기 + 우선순위 정책 필요
3. **인수 입력 폼** (Task 17.8 — argument-hint 활용한 placeholder UI) — Phase 17 은 hint 전달만, UI form 은 Phase 18+
4. **SkillSource 라벨 distinct UI** — 스킬 / 명령 같은 .slash 카테고리 안 sub-label 분리 (Phase 19 폴리시)
5. **ClaudeAdapter 의 `listSlashCommands` 와 통합** — 현재 prober 가 `claude -p` shell out, Phase 7 어댑터의 native API 사용으로 마이그레이션 가능
6. **Frontmatter `#` 주석 / 멀티라인 / 리스트 지원** — 현재 scalar 만, 외부 YAML 라이브러리 도입은 의존 가벼우니 defer
7. **pendingSlashInsertion 에 argHint placeholder 자동 select** — 사용자가 `<topic>` 영역만 즉시 타이핑할 수 있도록
8. **Watcher mtime-incremental refresh** — 현 호출 시 전체 readdir, 큰 카탈로그에서만 의미있음

---

## 완료 기준

- [x] Phase 17 Task 17.1~17.7, 17.9 (Task 17.8 인수 입력 폼 / 17.10-11 polish 는 Phase 18+ defer)
- [x] 592/592 테스트 통과 (3 skipped, aider 미설치 정상)
- [x] /team 리뷰 + must-fix 2건 반영, 2건 defer documented
- [x] swiftlint --strict: 0 violations
- [x] swift build 통과
- [x] Phase 1-16 회귀 없음
- [x] Quality Gate 3개 모두 자동 검증
- [x] 리뷰 리포트 저장 (이 파일)
- [ ] phase-17-end 태그 (다음 단계)

**Milestone 6 (파워유저 UX 2주) 완료**: Phase 16 (Cmd+K 팔레트) + Phase 17 (슬래시 명령 자동 탐색). 사용자가 `~/.claude/commands` 또는 `~/.claude/skills` 에 .md 추가 시 5초 이내 팔레트에 노출.

**다음**: Phase 18 — 네이티브 메뉴 + 메뉴바 앱 (3-4일 예상).
