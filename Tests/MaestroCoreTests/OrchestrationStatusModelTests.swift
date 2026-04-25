import Foundation
@testable import MaestroCore
import XCTest

@MainActor
final class OrchestrationStatusModelTests: XCTestCase {
    private struct DispatchIDs {
        let envelope: EnvelopeID
        let from: AgentID
        let to: AgentID
    }

    private func makeIDs() -> DispatchIDs {
        DispatchIDs(
            envelope: EnvelopeID.new(),
            from: AgentID(rawValue: "alice"),
            to: AgentID(rawValue: "bob")
        )
    }

    func testRecordStartCreatesRunningEntry() {
        let model = OrchestrationStatusModel()
        let ids = makeIDs(); let eid = ids.envelope; let from = ids.from; let to = ids.to

        model.recordStart(envelopeId: eid, from: from, to: to)
        XCTAssertEqual(model.entries.count, 1)
        XCTAssertEqual(model.entries[0].state, .running)
        XCTAssertTrue(model.hasRunning)
    }

    func testRecordStartReplacesExistingForSameEnvelope() {
        let model = OrchestrationStatusModel()
        let ids = makeIDs(); let eid = ids.envelope; let from = ids.from; let to = ids.to
        model.recordStart(envelopeId: eid, from: from, to: to)
        model.recordStart(envelopeId: eid, from: from, to: to)
        XCTAssertEqual(model.entries.count, 1, "duplicate start should replace, not append")
    }

    func testRecordCompletionUpdatesState() {
        let model = OrchestrationStatusModel(autoExpire: 60)  // expire 길게 — 테스트 동안 안 사라짐
        let ids = makeIDs(); let eid = ids.envelope; let from = ids.from; let to = ids.to
        model.recordStart(envelopeId: eid, from: from, to: to)
        model.recordCompletion(envelopeId: eid)
        XCTAssertEqual(model.entries[0].state, .completed)
        XCTAssertFalse(model.hasRunning)
    }

    func testRecordFailureCarriesMessage() {
        let model = OrchestrationStatusModel(autoExpire: 60)
        let ids = makeIDs(); let eid = ids.envelope; let from = ids.from; let to = ids.to
        model.recordStart(envelopeId: eid, from: from, to: to)
        model.recordFailure(envelopeId: eid, message: "timeout")
        if case .failed(let msg) = model.entries[0].state {
            XCTAssertEqual(msg, "timeout")
        } else {
            XCTFail("expected .failed state")
        }
    }

    func testCompletionForUnknownEnvelopeIsNoOp() {
        let model = OrchestrationStatusModel()
        model.recordCompletion(envelopeId: EnvelopeID.new())
        XCTAssertTrue(model.entries.isEmpty)
    }

    func testPurgeExpiredRemovesOldFinishedEntries() {
        let model = OrchestrationStatusModel(autoExpire: 0.05)
        let ids = makeIDs(); let eid = ids.envelope; let from = ids.from; let to = ids.to
        model.recordStart(envelopeId: eid, from: from, to: to)
        model.recordCompletion(envelopeId: eid)

        let later = Date().addingTimeInterval(1.0)
        model.purgeExpired(now: later)
        XCTAssertTrue(model.entries.isEmpty)
    }

    func testPurgeExpiredKeepsRunning() {
        let model = OrchestrationStatusModel(autoExpire: 0.05)
        let ids = makeIDs(); let eid = ids.envelope; let from = ids.from; let to = ids.to
        model.recordStart(envelopeId: eid, from: from, to: to)
        let later = Date().addingTimeInterval(1.0)
        model.purgeExpired(now: later)
        XCTAssertEqual(model.entries.count, 1, "running entries should not expire")
    }
}
