@testable import MaestroCore
import XCTest

@MainActor
final class InboxNotificationBridgeTests: XCTestCase {
    private func makeFolderID() -> FolderID {
        FolderID(rawValue: UUID().uuidString)
    }

    private func makeEnvelope(body: String = "hello") -> MessageEnvelope {
        MessageEnvelope.task(
            from: AgentID(rawValue: "alice"),
            to: AgentID(rawValue: "bob"),
            body: body
        )
    }

    func testInitialItemsAreBaselineNotEmitted() async throws {
        let store = InboxStore()
        let folder = makeFolderID()
        // 시작 전 이미 1개 존재 — baseline
        store.record(envelope: makeEnvelope(), folderID: folder)
        let service = NoopNotificationService()
        let bridge = InboxNotificationBridge(
            inboxStore: store, notificationService: service
        )
        bridge.start()
        defer { bridge.stop() }

        // 1.2초 대기 — 1s loop 한 번 돌만큼
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let sent = await service.sent
        XCTAssertTrue(sent.isEmpty, "baseline 항목은 알림 X")
    }

    func testNewItemTriggersNotification() async throws {
        let store = InboxStore()
        let folder = makeFolderID()
        let service = NoopNotificationService()
        let bridge = InboxNotificationBridge(
            inboxStore: store, notificationService: service
        )
        bridge.start()
        defer { bridge.stop() }

        // 시작 후 새 항목 추가
        store.record(envelope: makeEnvelope(body: "신규"), folderID: folder)

        // 최대 3초 polling
        var sent: [AppNotification] = []
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            sent = await service.sent
            if !sent.isEmpty { break }
        }
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(sent[0].title.contains("alice"))
        XCTAssertTrue(sent[0].body.contains("신규"))
        XCTAssertEqual(sent[0].badge, 1)
    }

    func testDisabledFlagSuppressesEmissionsButTracksBaseline() async throws {
        let store = InboxStore()
        let folder = makeFolderID()
        let service = NoopNotificationService()
        let bridge = InboxNotificationBridge(
            inboxStore: store,
            notificationService: service,
            notificationsEnabled: false
        )
        bridge.start()
        defer { bridge.stop() }

        store.record(envelope: makeEnvelope(), folderID: folder)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let sentDisabled = await service.sent
        XCTAssertTrue(sentDisabled.isEmpty)

        // 토글 ON 후 더 새 항목 추가 — 이전 baseline 은 backlog 안 터짐
        bridge.notificationsEnabled = true
        store.record(envelope: makeEnvelope(body: "after-enable"), folderID: folder)
        var sentAfter: [AppNotification] = []
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            sentAfter = await service.sent
            if !sentAfter.isEmpty { break }
        }
        XCTAssertEqual(sentAfter.count, 1, "토글 ON 후 새 항목만 알림")
        XCTAssertTrue(sentAfter[0].body.contains("after-enable"))
    }

    func testSanitizeAppliedToBody() async throws {
        let store = InboxStore()
        let folder = makeFolderID()
        let service = NoopNotificationService()
        let bridge = InboxNotificationBridge(
            inboxStore: store, notificationService: service
        )
        bridge.start()
        defer { bridge.stop() }

        store.record(
            envelope: makeEnvelope(body: "before\u{202E}after"),
            folderID: folder
        )
        var sent: [AppNotification] = []
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            sent = await service.sent
            if !sent.isEmpty { break }
        }
        XCTAssertFalse(sent.first?.body.contains("\u{202E}") ?? true,
                       "bidi 컨트롤 문자 sanitize")
    }
}
