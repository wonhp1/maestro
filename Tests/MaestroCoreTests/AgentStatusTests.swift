import Foundation
@testable import MaestroCore
import XCTest

final class AgentStatusTests: XCTestCase {
    func testColorMapping() {
        XCTAssertEqual(AgentStatus.offline.symbolColor, .gray)
        XCTAssertEqual(AgentStatus.idle(lastActivityAt: nil).symbolColor, .yellow)
        XCTAssertEqual(AgentStatus.active(operation: nil).symbolColor, .green)
        XCTAssertEqual(
            AgentStatus.error(message: "x", occurredAt: Date()).symbolColor, .red
        )
    }

    func testLocalizedDescriptionMentionsOperation() {
        let status = AgentStatus.active(operation: "프롬프트 처리 중")
        XCTAssertTrue(status.localizedDescription.contains("프롬프트"))
    }

    func testLocalizedDescriptionForErrorContainsMessage() {
        let status = AgentStatus.error(message: "API 키 없음", occurredAt: Date())
        XCTAssertTrue(status.localizedDescription.contains("API 키"))
    }
}

@MainActor
final class AgentStatusStoreTests: XCTestCase {
    func testInitialStatusIsOffline() {
        let store = AgentStatusStore()
        let id = FolderID.new()
        XCTAssertEqual(store.status(for: id), .offline)
    }

    func testTransitionsThroughStates() {
        let store = AgentStatusStore()
        let id = FolderID.new()

        store.setIdle(id)
        if case .idle = store.status(for: id) { } else { XCTFail("expected idle") }

        store.setActive(id, operation: "load")
        if case .active(let op) = store.status(for: id) {
            XCTAssertEqual(op, "load")
        } else { XCTFail("expected active") }

        store.setError(id, message: "fail")
        if case .error(let msg, _) = store.status(for: id) {
            XCTAssertEqual(msg, "fail")
        } else { XCTFail("expected error") }

        store.setOffline(id)
        XCTAssertEqual(store.status(for: id), .offline)
    }

    func testActiveAndErrorFolderIDsLists() {
        let store = AgentStatusStore()
        let a = FolderID.new()
        let b = FolderID.new()
        let c = FolderID.new()
        store.setActive(a)
        store.setActive(b, operation: "x")
        store.setError(c, message: "no")

        XCTAssertEqual(Set(store.activeFolderIDs), Set([a, b]))
        XCTAssertEqual(store.errorFolderIDs, [c])
    }

    func testResetAllClearsStatuses() {
        let store = AgentStatusStore()
        let id = FolderID.new()
        store.setIdle(id)
        store.resetAll()
        XCTAssertEqual(store.status(for: id), .offline)
    }
}
