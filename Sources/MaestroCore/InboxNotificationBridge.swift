import Foundation
import Observation

/// `InboxStore` 에 새 envelope 가 도착하면 `NotificationService` 로 시스템 알림 발행.
///
/// ## 동작
/// - `start()` — 1s polling 으로 `inboxStore.items` 변화 감지. 새 항목 (id 미관찰)
///   발견 시 `notify()` 호출.
/// - `notificationsEnabled` — false 면 emit X (PreferencesStore 와 동기 — 호출자가
///   현재 값 setter 로 전달).
///
/// ## 보안
/// - 알림 title/body 는 모두 `DisplayTextSanitizer` 거침 (외부 envelope body 로부터 옴).
/// - badge 는 unread count 그대로.
///
/// ## 동시성
/// `@MainActor` — InboxStore 와 같은 isolation. 1s polling 은 `Task.sleep` 협력적.
@MainActor
public final class InboxNotificationBridge {
    private let inboxStore: InboxStore
    private let notificationService: NotificationService
    private var seenIDs: Set<String> = []
    private var task: Task<Void, Never>?
    public var notificationsEnabled: Bool

    public init(
        inboxStore: InboxStore,
        notificationService: NotificationService,
        notificationsEnabled: Bool = true
    ) {
        self.inboxStore = inboxStore
        self.notificationService = notificationService
        self.notificationsEnabled = notificationsEnabled
    }

    public func start() {
        guard task == nil else { return }
        // 시작 시점의 기존 항목은 baseline — 알림 발행 X
        seenIDs = Set(inboxStore.items.map { $0.id.rawValue })
        task = Task { [weak self] in
            await self?.driveLoop()
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func driveLoop() async {
        while !Task.isCancelled {
            await emitForNewItems()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func emitForNewItems() async {
        guard notificationsEnabled else {
            // skip — 그래도 seenIDs 는 갱신해서 토글 ON 시 backlog 안 터짐
            seenIDs = Set(inboxStore.items.map { $0.id.rawValue })
            return
        }
        let current = inboxStore.items
        let unseenItems = current.filter { !seenIDs.contains($0.id.rawValue) }
        guard !unseenItems.isEmpty else { return }
        for item in unseenItems {
            let title = DisplayTextSanitizer.sanitize(
                "받은 메시지: \(item.from.rawValue) → \(item.to.rawValue)"
            )
            let body = DisplayTextSanitizer.sanitize(item.preview)
            await notificationService.notify(
                AppNotification(
                    id: "inbox-\(item.id.rawValue)",
                    title: title,
                    body: body,
                    badge: inboxStore.totalUnread
                )
            )
        }
        seenIDs = Set(current.map { $0.id.rawValue })
    }
}
