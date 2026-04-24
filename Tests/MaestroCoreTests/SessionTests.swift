@testable import MaestroCore
import XCTest

/// Phase 2 / Test 2.2 — Session 의 생성/상태 전이.
final class SessionTests: XCTestCase {
    private func makeSession(status: SessionStatus = .active) -> Session {
        Session(
            id: SessionID(rawValue: "s-1"),
            agentId: AgentID(rawValue: "cpo"),
            adapterId: "claude",
            folderPath: URL(fileURLWithPath: "/tmp/cpo"),
            createdAt: Date(timeIntervalSince1970: 0),
            lastActivityAt: Date(timeIntervalSince1970: 0),
            status: status
        )
    }

    func testInitPopulatesAllFields() {
        let session = makeSession()
        XCTAssertEqual(session.id.rawValue, "s-1")
        XCTAssertEqual(session.agentId.rawValue, "cpo")
        XCTAssertEqual(session.adapterId, "claude")
        XCTAssertEqual(session.folderPath.path, "/tmp/cpo")
        XCTAssertEqual(session.status, .active)
    }

    // MARK: Status transitions

    func testActiveToIdleAllowed() {
        var session = makeSession(status: .active)
        XCTAssertNoThrow(try session.transition(to: .idle))
        XCTAssertEqual(session.status, .idle)
    }

    func testIdleToActiveAllowed() {
        var session = makeSession(status: .idle)
        XCTAssertNoThrow(try session.transition(to: .active))
        XCTAssertEqual(session.status, .active)
    }

    func testTerminatedIsTerminal() {
        var session = makeSession(status: .terminated)
        XCTAssertThrowsError(try session.transition(to: .active))
        XCTAssertThrowsError(try session.transition(to: .idle))
    }

    func testAnyToTerminatedAllowed() {
        for from in [SessionStatus.active, .idle] {
            var session = makeSession(status: from)
            XCTAssertNoThrow(try session.transition(to: .terminated))
        }
    }

    // MARK: Activity tracking

    func testTouchUpdatesLastActivity() {
        var session = makeSession()
        let before = session.lastActivityAt
        let later = before.addingTimeInterval(60)
        session.touch(at: later)
        XCTAssertEqual(session.lastActivityAt, later)
    }

    // MARK: Codable

    func testJSONRoundtrip() throws {
        let original = makeSession()
        let data = try JSONEncoder.maestro.encode(original)
        let decoded = try JSONDecoder.maestro.decode(Session.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
