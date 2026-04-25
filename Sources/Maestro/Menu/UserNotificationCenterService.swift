import Foundation
import MaestroCore
import UserNotifications

/// `UNUserNotificationCenter` 위에 얹은 운영용 `NotificationService` 구현.
///
/// - Sandbox / 권한 거부 / OS 호출 실패는 silently swallow. 알림은 nice-to-have.
/// - `requestAuthorization` 은 알림 1번 당 1회만 사실상 실행됨 — OS 캐시.
/// - badge 는 옵셔널: `nil` 이면 그대로 유지.
public final class UserNotificationCenterService: NotificationService {
    public init() {}

    public func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    public func notify(_ notification: AppNotification) async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        if let badge = notification.badge {
            content.badge = NSNumber(value: badge)
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
