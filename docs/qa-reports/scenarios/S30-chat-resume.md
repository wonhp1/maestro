# S30 — 챗 세션 재개 (앱 재시작 후)

**상태**: ❌ FAIL — Session.id 디스크 미영속, 재시작 시 새 UUID 발급
**검증 방식**: Source review
**대상**: `Sources/MaestroCore/ChatSessionStore.swift`, `Sources/MaestroAdapters/ClaudeAdapter.swift`, `Sources/MaestroCore/FolderRegistration.swift`, `Sources/MaestroCore/AppSupportPaths.swift`

---

## 기대 동작

사용자가 폴더 X 에서 대화 → 앱 종료 → 재실행 → 같은 폴더 X 열기 → 이전 대화 컨텍스트가 이어져야 함 (Claude CLI `--resume <uuid>` 는 같은 UUID 만 적용되면 디스크의 `~/.claude/projects/<dir-hash>/<uuid>.jsonl` 을 자동 로드).

전제: Maestro 가 폴더당 Session.id (UUID) 를 디스크 저장 → 재시작 시 같은 UUID 로 `--resume`.

## 실제 동작

### 1. FolderRegistration 영속화 — OK

`FolderRegistration` (`FolderRegistration.swift:16-38`) 필드:

- `id: FolderID`, `displayName`, `path: URL`, `adapterId`, `createdAt`, `lastUsedAt?`
- **`session_id` / `Session` 참조 없음** — 폴더 메타에 세션 UUID 미포함.

`FolderRegistry` 가 `folders.json` 에 영속하지만 (`FolderRegistry.swift:176-179`), 영속되는 것은 폴더 메타 뿐.

### 2. Session 생성 — 매번 새 UUID

`ClaudeAdapter.createSession` (`ClaudeAdapter.swift:82-99`):

```swift
public func createSession(folderPath: URL) async throws -> Session {
    let sessionId = SessionID.new()  // ← 항상 새 UUID
    ...
    sessions[sessionId] = session   // ← in-memory dict 만
    ...
}
```

`SessionID.new()` (`Identifiers.swift:25-27`) → `UUID().uuidString` — 매 호출 새 ID.

### 3. ChatSessionStore — in-memory only

`ChatSessionStore` (`ChatSessionStore.swift:20-99`):

- `sessions: [FolderID: ChatViewModel]` — 메모리 dict (`:27`)
- `evictAll()` (`:92-98`) 외 영속 로직 없음
- `ensureSession(for:)` 가 캐시 미스면 `factory(folder)` → 새 `createSession` (위 1) 호출

### 4. AppSupportPaths.sessionsDir — 정의됐으나 미사용

`AppSupportPaths.swift:60` — `sessionsDir` 정의
`AppSupportPaths.swift:70-72` — `sessionFile(id: SessionID) -> URL` 헬퍼 정의

→ **호출처 grep 결과 (Sources/ 전체)**: `DiagnosticsExporter.swift:23` 에서 진단 번들 export 시 디렉토리 통째 ZIP 에 포함하는 것이 유일. **어떤 코드도 `sessionFile()` 에 write 또는 read 안 함**. 빈 디렉토리.

### 5. argv 빌더 — 첫 호출 분기

`ClaudeAdapter.buildArguments` (`ClaudeAdapter.swift:227-250`):

```swift
let isFirst = !initializedSessions.contains(session.id)
let sessionFlag = isFirst ? "--session-id" : "--resume"
```

`initializedSessions: Set<SessionID>` (`:43`) 도 in-memory only — 재시작 시 비워짐. 따라서 재시작 후 첫 메시지는 항상 `--session-id <새UUID>` 로 실행되어 Claude 가 **새 세션 파일 생성**.

## 결과

폴더 X 를 재시작 후 다시 열면:

1. `folders.json` 에서 X 메타 로드 (path, displayName) — OK
2. 사용자 dispatch → `ensureSession` → `factory(X)` → `ClaudeAdapter.createSession(folderPath: X.path)`
3. 새 UUID 발급, Claude 에 `--session-id <newUUID>` 로 spawn
4. 디스크에는 이전 실행에서 만든 `~/.claude/projects/<hash>/<oldUUID>.jsonl` 와 별개로 `<newUUID>.jsonl` 생성
5. **이전 대화 컨텍스트 유실** — Claude 모델 입장에서 새 대화

`destroySession` 의 주석은 의도가 일관 ("디스크 세션 파일은 그대로 둠 — 사용자가 `claude --resume` 으로 재개 가능", `ClaudeAdapter.swift:16`) 하지만 그 재개를 트리거할 매핑 (folderID → sessionID) 이 영속되지 않으므로 GUI 안에서는 도달 불가. CLI 에서 직접 `claude --resume <uuid>` 실행해야 회복.

## 비교: control-kim 레퍼런스 구현

(상위 프로젝트 CLAUDE.md 발췌)

> `~/.control-kim/registry.json` ─ `{ agents: { <name>: { dir, session_id, ... } } }`
> 같은 UUID 가 영원히 재사용됨 (`--session-id` on first launch, `--resume` thereafter — `findSessionFile` picks authoritatively)

→ Maestro 는 동일 패러다임을 의도했으나 (`AppSupportPaths.sessionsDir` 인프라 존재) **wire-in 누락**.

---

## Verdict

- ❌ Session.id 디스크 영속 미구현 — 폴더 재오픈 시 항상 신규 UUID
- ❌ Claude `--resume` 경로가 GUI 사이클 내에서만 유효 (앱 재시작 후 단절)
- ⚠️ `AppSupportPaths.sessionsDir` / `sessionFile(id:)` 인프라는 정의됐지만 read/write 호출처 0 — 절반 구현
- ⚠️ FolderRegistration 에 `lastSessionID: SessionID?` 같은 필드 추가 + ChatSessionStore 부팅 시 hydrate 필요

### 권장 수정 (issue I-NEW-2)

1. `FolderRegistration` 에 `lastSessionID: SessionID?` 추가 (folders.json v2 마이그레이션)
2. `ClaudeAdapter.createSession(folderPath:resumeID:)` 오버로드 — `resumeID` 주어지면 그대로 사용 + `initializedSessions.insert(resumeID)` 로 첫 호출부터 `--resume` 모드
3. `ControlTowerView` 의 `chatViewModelFactory` 에서 `folder.lastSessionID` 전달
4. `sendMessage` 성공 시 `FolderRegistry.update(id:, lastSessionID:)` 으로 영속

또는 (더 가벼운 대안) — `AppSupportPaths.sessionsDir/<folderID>.json` 에 `{sessionID, lastUsedAt}` 만 저장하는 sidecar.
