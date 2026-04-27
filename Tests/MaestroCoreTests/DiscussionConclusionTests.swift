@testable import MaestroCore
import XCTest

/// v0.5.0 Phase 3 — 결론 자동 요약 + 사용자 편집 단위 테스트.
final class DiscussionConclusionTests: XCTestCase {
    private let alice = AgentID(rawValue: "alice")
    private let bob = AgentID(rawValue: "bob")
    private let carol = AgentID(rawValue: "carol")

    private func makeEngine(
        state: DiscussionState = .pending
    ) -> DiscussionEngine {
        let discussion = Discussion(
            id: ThreadID.new(),
            title: "test",
            participants: [alice, bob, carol],
            moderatorId: nil,
            maxTurns: 1,
            state: state,
            turns: []
        )
        return DiscussionEngine(
            discussion: discussion,
            moderator: RoundRobinModerator(),
            dispatcher: ScriptedDispatcher(),
            initialPrompt: "topic"
        )
    }

    func testSummarizeConclusionSetsAndBroadcasts() async throws {
        let engine = makeEngine()
        let summarizer = StubSummarizer(text: "전략은 신규 시장 진입.")
        let stream = await engine.events()
        let summary = try await engine.summarizeConclusion(
            envelopes: [], using: summarizer
        )
        XCTAssertEqual(summary, "전략은 신규 시장 진입.")
        let d = await engine.discussion
        XCTAssertEqual(d.conclusion, "전략은 신규 시장 진입.")
        let receiver = StringBox()
        let task = Task {
            for await event in stream {
                if case .conclusionUpdated(let text) = event {
                    await receiver.set(text)
                    break
                }
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let got = await receiver.value
        XCTAssertEqual(got, "전략은 신규 시장 진입.")
    }

    func testSummarizeConclusionPropagatesError() async {
        let engine = makeEngine()
        let summarizer = ThrowingSummarizer()
        do {
            _ = try await engine.summarizeConclusion(envelopes: [], using: summarizer)
            XCTFail("expected error")
        } catch is ThrowingSummarizer.Boom {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
        let d = await engine.discussion
        XCTAssertNil(d.conclusion, "에러 시 conclusion 변경 없음")
    }

    func testSetConclusionUpdatesAndBroadcasts() async {
        let engine = makeEngine()
        await engine.setConclusion("사용자가 직접 편집한 결론")
        let d = await engine.discussion
        XCTAssertEqual(d.conclusion, "사용자가 직접 편집한 결론")
    }
}
