# S04 / S12 — 폴더 편집 (이름/어댑터/삭제) + Control 어댑터 경고

**상태**: S04 ⚠️ PARTIAL · S12 ✅ PASS
**검증 방식**: Source review (no GUI run)
**대상**: `Sources/Maestro/Folders/FolderSettingsSheet.swift`, `Sources/MaestroCore/FolderViewModel.swift`, `Sources/Maestro/Folders/SidebarView.swift`, `Sources/MaestroCore/ControlAgentProvisioner.swift`

---

## S04: 폴더 이름 변경 / 어댑터 변경 / 삭제

### 진입 경로

- ⌘, 단축키 (hidden Button keyboardShortcut) — `SidebarView.swift:132-138`
- 컨텍스트 메뉴 "설정..." — `SidebarView.swift:175-179`

### 표시 이름 변경 ✅ PASS

- TextField + 저장 버튼 — `FolderSettingsSheet.swift:47-48`, `66-76`
- 저장 시 trim 후 이전 값과 다르면 `viewModel.rename(id:to:)` 호출 — `FolderSettingsSheet.swift:147-149`
- `FolderViewModel.rename(id:to:)` → `registry.update(id:displayName:)` + refresh — `FolderViewModel.swift:130-137`
- 에러 시 `FolderRegistrationError` 한국어 매핑 ("폴더 이름이 비어 있습니다." 등) — `FolderViewModel.swift:171-179`

### 어댑터 변경 ✅ PASS

- Picker `기본 어댑터` — `FolderSettingsSheet.swift:50-54`
- 선택지는 `detectionViewModel.sortedAdapterIDs` (live detect) 또는 fallback 으로 현재 어댑터만 — `FolderSettingsSheet.swift:83-89`
- 미설치 어댑터 선택 시 hintRow 노출 (orange triangle + 설치 명령) — `FolderSettingsSheet.swift:95-120`
- 저장 시 `AdapterID.validated(rawValue:)` 검증 → `viewModel.changeAdapter(id:to:)` — `FolderSettingsSheet.swift:151-159`
- 검증 실패 시 errorMessage 한국어 ("어댑터 ID 가 잘못되었습니다: ...") — `FolderSettingsSheet.swift:156`
- `changeAdapter` → `registry.update(id:adapterId:)` — `FolderViewModel.swift:140-147`

### 삭제 ✅ (일반 폴더)

- 경로 1: 컨텍스트 메뉴 "삭제" → `SidebarView.swift:170-173`
- 경로 2: 키보드 ⌫ → `SidebarView.swift:90-96`
- 경로 3: 메뉴 "선택 폴더 제거" → `MaestroMenuCommands.swift:26`
- 단일 alert 채널 (`SidebarAlert` enum) 로 confirm — `SidebarView.swift:36-46`, `63-83`
- 확인 시 `viewModel.deleteFolder(id:)` → `registry.remove(id:)` + refresh + 다른 폴더로 selection fallback — `FolderViewModel.swift:116-127`
- 메시지: "디스크의 실제 폴더는 삭제되지 않습니다." (file-system 안전 명시) — `SidebarView.swift:68`

### Control 폴더 삭제 ⚠️ PARTIAL

**No explicit guard** — `FolderRegistry.remove(id:)` (`FolderRegistry.swift:111-117`) 도, `FolderViewModel.deleteFolder` 도 control 폴더를 차단하지 않음. 사이드바 컨텍스트 메뉴에도 destructive "삭제" 가 그대로 노출 (`SidebarView.swift:170-173`).

다만 자동 복원 메커니즘이 있음:

- 앱 부팅 시 `ControlAgentProvisioner.provision(...)` 가 `controlFolderID` 존재 확인 후 없으면 재등록 — `ControlAgentProvisioner.swift:51-62`, 호출은 `ControlTowerView.swift:430-433`
- 즉, **런타임 중 control 삭제하면 즉시 사라지고**, 다음 앱 재시작 시 복원

→ S04 verdict: 일반 폴더 PASS / 영속 보장은 재시작 의존이라 ⚠️ PARTIAL.

→ **신규 issue 권장**: control 폴더 삭제 가드 (registry 또는 sidebar 단 어디서든 차단 + 한국어 안내)

---

## S12: Control 폴더 어댑터 변경 + 경고 ✅ PASS

- 조건: `ControlAgentProvisioner.isControlFolder(folder.id) && adapterId != "claude"` — `FolderSettingsSheet.swift:122-124`
- UI: 정보 아이콘 + 파란 배경 박스 — `FolderSettingsSheet.swift:127-139`
- 메시지 (정확 텍스트):
  > **Control 폴더에 Claude 외 어댑터 사용 중**
  > 폴더 목록 자동 주입은 Claude 전용이에요. 다른 어댑터는 일반 시스템 프롬프트만 사용됩니다 — 사용자가 직접 폴더 ID 를 알려줘야 합니다.
- 어댑터 변경 자체는 차단하지 않음 — 사용자에게 trade-off 만 알리는 informational warning. 의도된 동작 (Claude 외 어댑터로 강제 운영도 허용).

---

## Verdict

- ✅ **S04** rename/adapter 변경/일반 폴더 삭제: 모두 정상 구현
- ⚠️ **S04** Control 폴더 삭제 가드: 미구현 — 앱 재시작 시에만 자동 복원
- ✅ **S12** Control + non-claude 어댑터 경고: 정상 구현
