@testable import MaestroCore
import XCTest

/// Phase 2 / Test 2.2 — Session 의 생성/상태 전이/종료 원인.
final class SessionTests: XCTestCase {
    private func makeSession(
        status: SessionStatus = .active,
        exitCause: SessionExitCause? = nil
    ) -> Session {
        Session(
            id: SessionID(rawValue: "s-1"),
            agentId: AgentID(rawValue: "cpo"),
            adapterId: AdapterID(rawValue: "claude"),
            folderPath: URL(fileURLWithPath: "/tmp/cpo"),
            createdAt: Date(timeIntervalSince1970: 0),
            lastActivityAt: Date(timeIntervalSince1970: 0),
            status: status,
            exitCause: exitCause
        )
    }

    func testInitPopulatesAllFields() {
        let session = makeSession()
        XCTAssertEqual(session.id.rawValue, "s-1")
        XCTAssertEqual(session.agentId.rawValue, "cpo")
        XCTAssertEqual(session.adapterId.rawValue, "claude")
        XCTAssertEqual(session.folderPath.path, "/tmp/cpo")
        XCTAssertEqual(session.status, .active)
        XCTAssertNil(session.exitCause)
    }

    // MARK: Status transition matrix

    func testAllValidTransitions() throws {
        let validPairs: [(SessionStatus, SessionStatus)] = [
            (.active, .idle), (.active, .active), (.active, .terminated),
            (.idle, .active), (.idle, .idle), (.idle, .terminated),
        ]
        for (from, to) in validPairs {
            var s = makeSession(status: from)
            XCTAssertNoThrow(try s.transition(to: to), "허용되어야 함: \(from) → \(to)")
        }
    }

    func testAllInvalidTransitions() {
        let invalidPairs: [(SessionStatus, SessionStatus)] = [
            (.terminated, .active), (.terminated, .idle), (.terminated, .terminated),
        ]
        for (from, to) in invalidPairs {
            var s = makeSession(status: from)
            XCTAssertThrowsError(try s.transition(to: to), "거부되어야 함: \(from) → \(to)") { err in
                XCTAssertEqual(err as? SessionError, .invalidTransition(from: from, to: to))
            }
        }
    }

    // MARK: Exit cause

    func testTransitionToTerminatedSetsExitCause() throws {
        var s = makeSession()
        try s.transition(to: .terminated, cause: .userTerminated)
        XCTAssertEqual(s.exitCause, .userTerminated)
    }

    func testTransitionToTerminatedWithCrashCause() throws {
        var s = makeSession()
        let cause: SessionExitCause = .crashed(signal: 11, exitCode: nil)
        try s.transition(to: .terminated, cause: cause)
        XCTAssertEqual(s.exitCause, cause)
    }

    func testTransitionToTerminatedWithoutCauseDefaultsToUnspecified() throws {
        var s = makeSession()
        try s.transition(to: .terminated)
        XCTAssertEqual(s.exitCause, .unspecified)
    }

    func testTransitionAwayFromTerminalNotPossible() {
        var s = makeSession(status: .terminated, exitCause: .userTerminated)
        XCTAssertThrowsError(try s.transition(to: .active))
        XCTAssertEqual(s.exitCause, .userTerminated, "실패 시 cause 유지")
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
        let original = makeSession(exitCause: nil)
        let data = try JSONEncoder.maestro.encode(original)
        let decoded = try JSONDecoder.maestro.decode(Session.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testJSONRoundtripWithExitCause() throws {
        let original = makeSession(status: .terminated, exitCause: .crashed(signal: 9, exitCode: 1))
        let data = try JSONEncoder.maestro.encode(original)
        let decoded = try JSONDecoder.maestro.decode(Session.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
