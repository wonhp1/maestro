# S20 — 에이전트 상태 dot

**상태**: ✅ PASS (코드 레벨)
**검증 방식**: Source review (S07 에서 이미 GUI 상 orange/red/green 확인됨)
**대상**: `Sources/MaestroCore/AgentStatus.swift`, `Sources/Maestro/ControlTower/AgentStatusBadge.swift`, `Sources/Maestro/Folders/SidebarView.swift`

---

## AgentStatus enum (`AgentStatus.swift:19-58`)

```
case offline
case idle(lastActivityAt: Date?)
case active(operation: String?)
case error(message: String, occurredAt: Date)
```

`symbolColor` (`:26-33`) → `AgentStatusColor`:

- `.offline` → `.gray`
- `.idle` → `.yellow`
- `.active` → `.green`
- `.error` → `.red`

`localizedDescription` (`:36-51`): 한국어 ("오프라인" / "대기 (마지막 활동: …)" / "동작 중 — \(op)" / "에러: \(message)").

`AgentStatusColor` (`:61-63`) — Core 가 SwiftUI 의존 회피 위해 별도 토큰 enum.

## SwiftUI 매핑 (`AgentStatusBadge.swift`)

`Circle().fill(color(for: status.symbolColor))` 8x8 dot — `:13-15`.
`color(for:)` switch (`:28-35`):

- `.gray` → `Color.gray`
- `.yellow` → `Color.yellow`
- `.green` → `Color.green`
- `.red` → `Color.red`

`.help(status.localizedDescription)` + `.accessibilityLabel(...)` 로 hover/접근성 지원.

## 사이드바 통합 (`SidebarView.swift:271-273`)

```
if let status {
    AgentStatusBadge(status: status)
}
```

`FolderRow` 가 `statusStore?.status(for: folder.id)` (`:165`) 결과를 받아 표시.

상태 전이 trigger:

- `ChatSessionStore` (`:32, :40`) → 세션 생성 성공 시 `setIdle`, 실패 시 `setError`
- `DispatchService` (`:9`) → dispatch 시작/종료 시 setActive/setIdle/setError
- `ControlTowerDispatchObserver` (`:10`) → 옵저버 분기

---

## Verdict

- ✅ 4 가지 상태 색상 정의 (gray/yellow/green/red) — 코드와 S07 GUI 검증 일치
- ✅ `AgentStatusBadge` 가 SidebarView 의 FolderRow 에 통합
- ✅ 한국어 localizedDescription + accessibility 라벨
