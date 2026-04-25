# Phase 24 Review Report — Production Wiring

**Date**: 2026-04-25
**Phase**: 24 (post-23, "actually usable" tier)
**Status**: ✅ Complete

---

## Goal

원안 23-Phase 완료 후 실제 제품 사용을 막던 3대 gap 해결:

1. MockAdapter 가 production default → 실제 ClaudeAdapter/AiderAdapter 우선 wire-in
2. CLI 자동 감지 부재 → 부팅 시 병렬 detect → onboarding 표시
3. Inbox 도착 시 알림 부재 → InboxNotificationBridge 추가

## Deliverables

`Sources/MaestroAdapters/`:

- `AdapterSelector.swift` — actor, candidate dictionary + fallback. `select(preferred:enabled:)` 가 (1) preferred + enabled + detect 통과 → preferred, (2) 그 외 enabled 정렬 첫 detect 통과, (3) 모두 실패 → fallback. `detectAll()` 병렬 + `installedAdapterIDs()` 정렬

`Sources/MaestroCore/`:

- `InboxNotificationBridge.swift` — `@MainActor` 1s polling. `start()` 시 baseline = 현재 items, 이후 새 envelope 만 `NotificationService.notify()`. `notificationsEnabled` 토글 false 일 때 emit X + baseline 갱신 (toggle ON 시 backlog 안 터짐). title/body 모두 `DisplayTextSanitizer` 거침

`Sources/Maestro/ControlTower/ControlTowerView.swift`:

- `ControlTowerEnvironment.makeProduction()` — ClaudeAdapter / AiderAdapter try? init 후 candidates 맵, MockAdapter fallback. chatViewModelFactory 가 selector.select() 호출
- `adapterSelector` / `detectedAdapterIDs` 추가
- bootstrap 끝에 `detectInstalledAdapters()` 호출 — 결과 publish
- `startInboxNotificationBridge()` — preferences.notificationsEnabled 동기화
- ControlTowerView 가 `OnboardingViewModel.setDetectedAdapters()` 에 자동 전달

**Tests**: 702/702 통과 (3 skipped — aider 미설치) (Phase 23 의 692 → +10)

- `AdapterSelectorTests` (6) — preferred 선택 / preferred not detected fallback / 모두 미설치 fallback / preferred not in enabled / detectAll / installedAdapterIDs 정렬
- `InboxNotificationBridgeTests` (4) — baseline non-emit / 새 항목 트리거 / disabled 플래그 + toggle ON 후 새 항목만 / sanitize bidi 차단

---

## 보안

- `DisplayTextSanitizer` 적용 (bidi/ZW/control char 차단) — title/body 모두
- `AdapterSelector` 가 production fallback 으로 MockAdapter 사용 — 사용자 경험 보호 (CLI 미설치 시 혼란스러운 에러 대신 mock 응답)
- 시크릿 추가 0건

## 동시성

- `AdapterSelector` actor — detect 호출 직렬화
- `InboxNotificationBridge` `@MainActor` — InboxStore 와 같은 isolation
- ControlTowerEnvironment `chatViewModelFactory` `[selector]` capture — actor reference 공유 안전

## Quality Gates

- ✅ swift build 통과
- ✅ swiftlint --strict 0 violations
- ✅ 702/702 테스트 통과
- ✅ ClaudeAdapter / AiderAdapter detect 가 PATH 의 실제 binary 찾음 (이미 Phase 7/9 에서 검증)

## 사용 효과

이 변경 후:

1. **Claude Code 설치된 사용자** — 첫 폴더 추가 → 메시지 전송 → 실제 Claude 응답 (mock X)
2. **온보딩 2단계** — "에이전트 감지" 가 실제 detect 결과 (claude/aider 중 설치된 것) 표시
3. **inbox 새 메시지** — 시스템 알림 (집중모드 존중, OS 자동) + Dock 배지 (Phase 18 인프라)

---

## Open Items (Phase 25+)

이전 phase 의 deferred 들 중 아직 남은 것:

1. Discussion UI 사이드바 진입점 (Phase 14-15)
2. Shell 터미널 진입점 (Phase 20)
3. 슬래시 명령 → composer 자동 입력 (Phase 17)
4. CrashReporter.install() 부팅 시 자동 (Phase 23)
5. DataMigrator.migrateIfNeeded() 부팅 시 (Phase 23)
6. 앱 아이콘 추가 (Info.plist)
7. Help / Feedback 메뉴 wiring (Phase 23)
8. SwiftTerm 통합 (Phase 20.5)
9. Sparkle 자동 업데이트 UI (Phase 22+)
10. 모든 view 의 i18n / a11y 라벨 마이그레이션 (Phase 22)
