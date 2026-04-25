@testable import MaestroCore
import XCTest

final class NotificationServiceTests: XCTestCase {
    func testNoopRecordsRequestAuthorization() async {
        let service = NoopNotificationService()
        let granted = await service.requestAuthorization()
        XCTAssertTrue(granted)
        let requested = await service.authorizedRequested
        XCTAssertTrue(requested)
    }

    func testNoopRecordsNotifications() async {
        let service = NoopNotificationService()
        let n1 = AppNotification(id: "a", title: "t1", body: "b1", badge: 1)
        let n2 = AppNotification(id: "b", title: "t2", body: "b2")
        await service.notify(n1)
        await service.notify(n2)
        let sent = await service.sent
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0].id, "a")
        XCTAssertEqual(sent[0].badge, 1)
        XCTAssertNil(sent[1].badge)
    }

    func testAppNotificationEquality() {
        let n1 = AppNotification(id: "x", title: "t", body: "b", badge: nil)
        let n2 = AppNotification(id: "x", title: "t", body: "b", badge: nil)
        let n3 = AppNotification(id: "y", title: "t", body: "b", badge: nil)
        XCTAssertEqual(n1, n2)
        XCTAssertNotEqual(n1, n3)
    }
}
