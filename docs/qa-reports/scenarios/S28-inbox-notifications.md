# S28 — Inbox 시스템 알림

**상태**: ✅ PASS (코드 레벨)
**검증 방식**: Source review
**대상**: `Sources/MaestroCore/NotificationService.swift`, `Sources/MaestroCore/InboxNotificationBridge.swift`, `Sources/Maestro/Menu/UserNotificationCenterService.swift`, `Sources/Maestro/ControlTower/ControlTowerEnvironment+Bootstrap.swift`

---

## 권한 요청 (런치 시점)

`ControlTowerEnvironment+Bootstrap.swift:136-138`:

```swift
func requestNotificationAuthorization() async {
    _ = await notificationService.requestAuthorization()
}
```

- 부팅 시퀀스에서 호출됨 (`MaestroApp.swift` 의 bootstrap 시퀀스 `:444`):
  `await requestNotificationAuthorization()` → `await detectInstalledAdapters()` → `startInboxNotificationBridge()` → `installCrashReporter(...)`
- 또한 사용자가 onboarding/preferences UI 의 "알림 권한 요청" 액션을 누르면 `MaestroApp.swift:127` 의 `onRequestNotificationPermission` 핸들러도 같은 메서드 호출

`UserNotificationCenterService.requestAuthorization()` (`UserNotificationCenterService.swift:13-20`):

- `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])`
- 실패 시 silently `false` — 알림은 nice-to-have (`:7-8` 주석 명시)

## Bridge 동작 (`InboxNotificationBridge.swift`)

`start()` (`:36-43`):

1. **baseline seed** — 시작 시점의 기존 inbox 항목 id 들을 `seenIDs` 에 채움 (`:39`). 부팅 직후 backlog 알림 폭발 차단.
2. 백그라운드 Task 시작 → `driveLoop` (`:50-55`).
3. 1초 polling.

`emitForNewItems()` (`:57-81`):

- `notificationsEnabled == false` 면 emit 건너뜀, 단 `seenIDs` 는 갱신 (`:58-62`) — 토글 ON 시 backlog 가 다시 안 터지도록 한 합리적 처리.
- 새로운 envelope 마다 `notificationService.notify(...)` 호출.

## 알림 payload 구성 (`InboxNotificationBridge.swift:67-78`)

- **title** (`:67-69`): `"받은 메시지: \(item.from.rawValue) → \(item.to.rawValue)"` → `DisplayTextSanitizer.sanitize` 거침
- **body** (`:70`): `item.preview` (DisplayTextSanitizer 거침)
- **id** (`:73`): `"inbox-\(item.id.rawValue)"` — OS dedupe 키
- **badge** (`:76`): `inboxStore.totalUnread` — 누적 미확인 카운트

→ NotificationService 인터페이스 명세대로 sanitized title/body 만 전달. raw envelope body 누설 X.

## OS 전달 (`UserNotificationCenterService.notify`, `:22-37`)

- `UNMutableNotificationContent` 구성: title, body, badge (NSNumber), sound = `.default`
- `UNNotificationRequest(identifier:, content:, trigger: nil)` → 즉시 발사
- `try? await center.add(...)` — 실패 silent (sandbox/권한 거부 등)

## 보안

- title/body 모두 `DisplayTextSanitizer.sanitize` 통과 — bidi/zero-width/제어문자 제거 (S04 와 같은 방어선)
- badge 수치는 sanitization 불필요 (Int)

## NoopNotificationService (테스트용, `NotificationService.swift:37-51`)

- `sent: [AppNotification]` 배열에 기록만, 권한 항상 `true` 반환 — 테스트 더블

---

## Verdict

- ✅ 부팅 시점에 `requestAuthorization` 호출 (1회 + 사용자 명시적 재요청 가능)
- ✅ 새 envelope 도착 → UNUserNotification 발사 (sender + body preview + badge)
- ✅ baseline seed 로 backlog 폭발 차단
- ✅ `notificationsEnabled` 토글 OFF 시에도 seenIDs 추적 — 토글 ON backlog 폭발 방지
- ✅ DisplayTextSanitizer 통한 spoofing 방어
- ⚠️ 1초 polling — `withObservationTracking` 대신 polling 선택은 단순/디버깅 용이지만 idle 시 CPU 낭비 (작음). UI 와 동일 actor 라 critical 아님.
