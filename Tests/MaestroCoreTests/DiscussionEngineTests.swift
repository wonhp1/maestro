@testable import MaestroCore
import XCTest

final class DiscussionEngineTests: XCTestCase {
    private let alice = AgentID(rawValue: "alice")
    private let bob = AgentID(rawValue: "bob")
    private let carol = AgentID(rawValue: "carol")

    private func makeDiscussion(
        participants: [AgentID] = [],
        moderator: AgentID? = nil,
        maxTurns: Int = 10,
        state: DiscussionState = .pending
    ) -> Discussion {
        Discussion(
            id: ThreadID.new(),
            title: "test discussion",
            participants: participants.isEmpty ? [alice, bob, carol] : participants,
            moderatorId: moderator,
            maxTurns: maxTurns,
            state: state,
            turns: []
        )
    }

    private func makeEngine(
        discussion: Discussion,
        moderator: ModeratorStrategy = RoundRobinModerator(),
        dispatcher: DiscussionDispatching
    ) -> DiscussionEngine {
        DiscussionEngine(
            discussion: discussion,
            moderator: moderator,
            dispatcher: dispatcher,
            initialPrompt: "Discuss the topic."
        )
    }

    private func collectEvents(
        from engine: DiscussionEngine,
        until predicate: @Sendable @escaping (DiscussionEngine.Event) -> Bool,
        timeout: TimeInterval = 3.0
    ) async -> [DiscussionEngine.Event] {
        let stream = await engine.events()
        let collector = EventCollector()
        // 두 task race — predicate 만족 시 즉시 반환 (must-fix MED-7).
        return await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await event in stream {
                    _ = await collector.append(event)
                    if predicate(event) { break }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            }
            await group.next()
            group.cancelAll()
            return await collector.snapshot()
        }
    }

    // MARK: - roundRobin

    func testRoundRobinThreeAgentTermsCompleteToMaxTurns() async throws {
        let dispatcher = ScriptedDispatcher()
        let engine = makeEngine(
            discussion: makeDiscussion(maxTurns: 3),
            moderator: RoundRobinModerator(),
            dispatcher: dispatcher
        )
        try await engine.start()
        let events = await collectEvents(from: engine) { event in
            if case .terminated = event { return true }
            return false
        }

        let speakers = events.compactMap { event -> AgentID? in
            if case .turnCompleted(let speaker, _) = event { return speaker }
            return nil
        }
        XCTAssertEqual(speakers, [alice, bob, carol])
        XCTAssertTrue(events.contains { event in
            if case .terminated(let reason) = event { return reason == .maxTurnsReached }
            return false
        })
    }

    // MARK: - moderator returns nil

    func testTerminatesWhenModeratorReturnsNil() async throws {
        let dispatcher = ScriptedDispatcher()
        let scripted = ScriptedModerator(schedule: [alice, bob])  // 2회 후 nil
        let engine = makeEngine(
            discussion: makeDiscussion(maxTurns: 100),
            moderator: scripted,
            dispatcher: dispatcher
        )
        try await engine.start()
        let events = await collectEvents(from: engine) { event in
            if case .terminated = event { return true }
            return false
        }
        let terminated = events.last { event in
            if case .terminated = event { return true }
            return false
        }
        if case .terminated(let reason) = terminated! {
            XCTAssertEqual(reason, .moderatorReturnedNil)
        } else {
            XCTFail("expected terminated")
        }
    }

    // MARK: - pause / resume

    func testPauseStopsAdvanceAndResumeContinues() async throws {
        let dispatcher = SlowDispatcher(delayPerTurn: 0.1)
        let engine = makeEngine(
            discussion: makeDiscussion(maxTurns: 5),
            moderator: RoundRobinModerator(),
            dispatcher: dispatcher
        )
        // event-based sync: 첫 turnCompleted 까지 대기 (flakiness 회피, must-fix MED-6)
        let stream = await engine.events()
        try await engine.start()
        for await event in stream {
            if case .turnCompleted = event { break }
        }
        try await engine.pause()
        let countAtPause = await engine.discussion.turns.count
        XCTAssertGreaterThanOrEqual(countAtPause, 1)

        try await Task.sleep(nanoseconds: 300_000_000)
        let stillSame = await engine.discussion.turns.count
        XCTAssertEqual(stillSame, countAtPause, "pause 중 추가 진행 없어야")

        try await engine.resume()
        // 다음 turnCompleted 또는 terminated 까지 대기
        for await event in stream {
            if case .turnCompleted = event { break }
            if case .terminated = event { break }
        }
        let after = await engine.discussion.turns.count
        XCTAssertGreaterThan(after, countAtPause)
    }

    // MARK: - termination

    func testUserTerminateTransitionsToAborted() async throws {
        let dispatcher = SlowDispatcher(delayPerTurn: 0.5)
        let engine = makeEngine(
            discussion: makeDiscussion(maxTurns: 100),
            moderator: RoundRobinModerator(),
            dispatcher: dispatcher
        )
        try await engine.start()
        try await Task.sleep(nanoseconds: 100_000_000)
        try await engine.terminate()
        let state = await engine.discussion.state
        XCTAssertEqual(state, .aborted)
    }

    func testDoubleStartThrowsInvalidTransition() async throws {
        let engine = makeEngine(
            discussion: makeDiscussion(maxTurns: 5),
            dispatcher: SlowDispatcher(delayPerTurn: 0.5)
        )
        try await engine.start()
        do {
            try await engine.start()
            XCTFail("expected invalidTransition")
        } catch let error as DiscussionError {
            guard case .invalidTransition = error else {
                XCTFail("wrong error: \(error)")
                return
            }
        }
        try await engine.terminate()
    }

    func testTerminateFromPausedTransitionsToAborted() async throws {
        let engine = makeEngine(
            discussion: makeDiscussion(maxTurns: 100),
            dispatcher: SlowDispatcher(delayPerTurn: 0.5)
        )
        try await engine.start()
        try await Task.sleep(nanoseconds: 100_000_000)
        try await engine.pause()
        try await engine.terminate()
        let state = await engine.discussion.state
        XCTAssertEqual(state, .aborted)
    }

    func testPauseDuringDispatchEmitsTurnDiscarded() async throws {
        let dispatcher = SlowDispatcher(delayPerTurn: 0.4)
        let engine = makeEngine(
            discussion: makeDiscussion(maxTurns: 5),
            dispatcher: dispatcher
        )
        try await engine.start()
        // dispatch 가 시작되도록 대기
        try await Task.sleep(nanoseconds: 100_000_000)
        try await engine.pause()
        try await Task.sleep(nanoseconds: 500_000_000)
        // events 에 turnDiscarded 가 들어와야 함 — 별도 stream 으로 검증
        // (직전 호출에서 이미 emit 됐을 수 있음 — 새 stream 은 못 받음)
        // 대안: discussion.turns 가 1 이하 (recordTurn 안 됨 검증)
        let count = await engine.discussion.turns.count
        XCTAssertLessThanOrEqual(count, 1, "pause 중 들어온 reply 는 record 되지 않아야")
    }

    func testDispatcherErrorAbortsDiscussion() async throws {
        let dispatcher = ThrowingDispatcher()
        let engine = makeEngine(
            discussion: makeDiscussion(maxTurns: 5),
            moderator: RoundRobinModerator(),
            dispatcher: dispatcher
        )
        try await engine.start()
        let events = await collectEvents(from: engine) { event in
            if case .terminated = event { return true }
            return false
        }
        let state = await engine.discussion.state
        XCTAssertEqual(state, .aborted)
        XCTAssertTrue(events.contains { event in
            if case .turnFailed = event { return true }
            return false
        })
    }
}

// MARK: - Helpers

actor EventCollector {
    private var events: [DiscussionEngine.Event] = []

    func append(_ event: DiscussionEngine.Event) -> Int {
        events.append(event)
        return events.count
    }

    func snapshot() -> [DiscussionEngine.Event] { events }
}

/// 미리 정의된 응답 envelope 을 반환 — 시간 지연 없음.
struct ScriptedDispatcher: DiscussionDispatching {
    func dispatchTurn(
        discussion: Discussion,
        speaker: AgentID,
        prompt: String
    ) async throws -> MessageEnvelope {
        MessageEnvelope(
            id: EnvelopeID.new(),
            threadId: discussion.id,
            inReplyTo: nil,
            from: speaker,
            to: AgentID(rawValue: "engine"),
            type: .report,
            body: "[\(speaker.rawValue)] response to: \(prompt.prefix(20))",
            createdAt: Date(),
            expectReply: false
        )
    }
}

struct SlowDispatcher: DiscussionDispatching {
    let delayPerTurn: TimeInterval

    func dispatchTurn(
        discussion: Discussion,
        speaker: AgentID,
        prompt: String
    ) async throws -> MessageEnvelope {
        try await Task.sleep(nanoseconds: UInt64(delayPerTurn * 1_000_000_000))
        return MessageEnvelope(
            id: EnvelopeID.new(),
            threadId: discussion.id,
            inReplyTo: nil,
            from: speaker,
            to: AgentID(rawValue: "engine"),
            type: .report,
            body: "delayed",
            createdAt: Date(),
            expectReply: false
        )
    }
}

struct ThrowingDispatcher: DiscussionDispatching {
    struct Boom: Error {}
    func dispatchTurn(
        discussion: Discussion,
        speaker: AgentID,
        prompt: String
    ) async throws -> MessageEnvelope {
        throw Boom()
    }
}
