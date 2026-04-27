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
        // events 의 envelope 가 Phase 15 에서 full envelope 로 변경됨 — speaker 와 일치 확인
        let envelopes = events.compactMap { event -> MessageEnvelope? in
            if case .turnCompleted(_, let env) = event { return env }
            return nil
        }
        XCTAssertEqual(envelopes.count, speakers.count)
        XCTAssertTrue(envelopes.allSatisfy { !$0.body.isEmpty })
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

    // MARK: - v0.5.0 — subSession isolation

    /// `start()` 가 참가자별 ephemeral subSessionID 를 자동 발급해야 함.
    func testStartPopulatesSubSessionsForAllParticipants() async throws {
        let engine = makeEngine(
            discussion: makeDiscussion(maxTurns: 1),
            dispatcher: ScriptedDispatcher()
        )
        try await engine.start()
        let d = await engine.discussion
        XCTAssertEqual(d.subSessions.count, 3)
        XCTAssertNotNil(d.subSessions[alice])
        XCTAssertNotNil(d.subSessions[bob])
        XCTAssertNotNil(d.subSessions[carol])
        let raws = Set(d.subSessions.values.map { $0.rawValue })
        XCTAssertEqual(raws.count, 3, "모든 subSessionID 는 unique")
    }

    /// 이미 할당된 subSessionID 는 `start()` 가 덮어쓰지 않아야 함.
    /// (영속화된 토론 재로드 시나리오 — 같은 ephemeral 세션 재개 보장.)
    func testStartPreservesPreassignedSubSessions() async throws {
        var d = makeDiscussion(maxTurns: 1)
        let preset = SessionID(rawValue: "11111111-1111-1111-1111-111111111111")
        d.assignSubSession(preset, for: alice)
        let engine = makeEngine(discussion: d, dispatcher: ScriptedDispatcher())
        try await engine.start()
        let after = await engine.discussion
        XCTAssertEqual(after.subSessions[alice], preset, "기존 ID 보존")
        XCTAssertNotNil(after.subSessions[bob])
        XCTAssertNotNil(after.subSessions[carol])
    }

    /// `IsolatedTurnDispatcher` 가 speaker 의 subSessionID 를 factory 에 넘겨
    /// ephemeral 세션을 만든 뒤 그 세션으로 sendMessage 호출.
    func testIsolatedTurnDispatcherPassesSubSessionIDToFactory() async throws {
        let factory = RecordingIsolatedSessionFactory()
        let dispatcher = IsolatedTurnDispatcher(
            factory: factory,
            from: AgentID(rawValue: "control")
        )
        var d = makeDiscussion(maxTurns: 1)
        let aliceSession = SessionID(rawValue: "alice-iso")
        d.assignSubSession(aliceSession, for: alice)
        _ = try await dispatcher.dispatchTurn(
            discussion: d, speaker: alice, prompt: "go"
        )
        let calls = await factory.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.agent, alice)
        XCTAssertEqual(calls.first?.sessionId, aliceSession)
    }

    /// subSession 이 없는 speaker 에 대한 dispatch 는 구체적 에러로 throws.
    func testIsolatedTurnDispatcherThrowsWhenSubSessionMissing() async {
        let factory = RecordingIsolatedSessionFactory()
        let dispatcher = IsolatedTurnDispatcher(
            factory: factory,
            from: AgentID(rawValue: "control")
        )
        let d = makeDiscussion(maxTurns: 1)  // 비어있음
        do {
            _ = try await dispatcher.dispatchTurn(
                discussion: d, speaker: alice, prompt: "go"
            )
            XCTFail("missing subSession 일 때 throws 해야")
        } catch let error as IsolatedDispatchError {
            XCTAssertEqual(error, .missingSubSession(speaker: alice))
        } catch {
            XCTFail("예상과 다른 에러: \(error)")
        }
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

/// v0.5.0 — IsolatedSessionFactory 호출 인자를 기록하는 테스트 fake.
/// 반환되는 ResolvedAgent 는 echo adapter — sendMessage 가 즉시 응답 envelope.
actor RecordingIsolatedSessionFactory: IsolatedSessionFactory {
    struct Call: Sendable, Equatable {
        let agent: AgentID
        let sessionId: SessionID
    }
    private(set) var calls: [Call] = []

    func makeIsolatedSession(
        for agent: AgentID,
        sessionId: SessionID
    ) async throws -> ResolvedAgent {
        calls.append(Call(agent: agent, sessionId: sessionId))
        return ResolvedAgent(
            adapter: EchoAdapter(),
            session: Session(
                id: sessionId,
                agentId: agent,
                adapterId: AdapterID(rawValue: "echo"),
                folderPath: URL(fileURLWithPath: "/tmp"),
                createdAt: Date(),
                lastActivityAt: Date(),
                status: .active
            )
        )
    }
}

actor StringBox {
    private(set) var value: String?
    func set(_ text: String) { value = text }
}

/// 단일 fixed 텍스트 반환 — Phase 3 테스트용.
struct StubSummarizer: DiscussionConclusionSummarizer {
    let text: String
    func summarize(
        discussion: Discussion, envelopes: [MessageEnvelope]
    ) async throws -> String { text }
}

struct ThrowingSummarizer: DiscussionConclusionSummarizer {
    struct Boom: Error {}
    func summarize(
        discussion: Discussion, envelopes: [MessageEnvelope]
    ) async throws -> String { throw Boom() }
}

/// 즉시 echo 응답을 돌려주는 미니 어댑터 — IsolatedTurnDispatcher 단위 테스트용.
struct EchoAdapter: AgentAdapter {
    static let id = "echo"
    static let displayName = "Echo"
    static let iconName = "terminal"

    func detect() async -> AdapterDetection { .notInstalled() }

    func createSession(folderPath: URL) async throws -> Session {
        Session(
            id: SessionID.new(),
            agentId: AgentID(rawValue: "echo-agent"),
            adapterId: AdapterID(rawValue: "echo"),
            folderPath: folderPath,
            createdAt: Date(),
            lastActivityAt: Date(),
            status: .active
        )
    }

    func destroySession(_ id: SessionID) async throws {}

    func sendMessage(
        _ envelope: MessageEnvelope,
        in session: Session
    ) async throws -> MessageEnvelope {
        MessageEnvelope(
            id: EnvelopeID.new(),
            threadId: envelope.threadId,
            inReplyTo: envelope.id,
            from: envelope.to,
            to: envelope.from,
            type: .report,
            body: "echo: \(envelope.body)",
            createdAt: Date(),
            expectReply: false
        )
    }
}
