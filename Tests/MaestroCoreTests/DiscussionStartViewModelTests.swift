@testable import MaestroCore
import XCTest

@MainActor
final class DiscussionStartViewModelTests: XCTestCase {
    func testEmptyTopicIsInvalid() {
        let viewModel = makeViewModel()
        viewModel.topic = ""
        viewModel.selectedParticipants = [agentA, agentB]
        XCTAssertFalse(viewModel.canStart)
    }

    func testWhitespaceOnlyTopicIsInvalid() {
        let viewModel = makeViewModel()
        viewModel.topic = "   \n  "
        viewModel.selectedParticipants = [agentA, agentB]
        XCTAssertFalse(viewModel.canStart)
    }

    func testFewerThanTwoParticipantsIsInvalid() {
        let viewModel = makeViewModel()
        viewModel.topic = "주제"
        viewModel.selectedParticipants = [agentA]
        XCTAssertFalse(viewModel.canStart)
    }

    func testValidInputCanStart() {
        let viewModel = makeViewModel()
        viewModel.topic = "기능 우선순위"
        viewModel.selectedParticipants = [agentA, agentB]
        XCTAssertTrue(viewModel.canStart)
    }

    func testMaxTurnsClampedToValidRange() {
        let viewModel = makeViewModel()
        viewModel.maxTurns = 0
        XCTAssertGreaterThanOrEqual(viewModel.clampedMaxTurns, DiscussionStartViewModel.minMaxTurns)
        viewModel.maxTurns = 999_999
        XCTAssertLessThanOrEqual(viewModel.clampedMaxTurns, DiscussionStartViewModel.maxMaxTurns)
    }

    func testStartInvokesActionWithRequest() async throws {
        var capturedRequest: DiscussionStartRequest?
        let viewModel = DiscussionStartViewModel(
            availableParticipants: [participantA, participantB],
            startAction: { request in
                capturedRequest = request
                return ThreadID.new()
            }
        )
        viewModel.topic = "테스트 주제"
        viewModel.selectedParticipants = [agentA, agentB]
        viewModel.maxTurns = 10
        viewModel.moderatorChoice = .roundRobin

        let result = try await viewModel.start()
        XCTAssertNotNil(result)
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.topic, "테스트 주제")
        XCTAssertEqual(Set(request.participants), Set([agentA, agentB]))
        XCTAssertEqual(request.maxTurns, 10)
        if case .roundRobin = request.moderatorChoice {} else {
            XCTFail("expected roundRobin moderator")
        }
    }

    func testStartWhenInvalidThrowsAndDoesNotInvokeAction() async {
        var actionInvoked = false
        let viewModel = DiscussionStartViewModel(
            availableParticipants: [participantA, participantB],
            startAction: { _ in
                actionInvoked = true
                return ThreadID.new()
            }
        )
        viewModel.topic = ""
        viewModel.selectedParticipants = [agentA, agentB]

        do {
            _ = try await viewModel.start()
            XCTFail("expected throw")
        } catch DiscussionStartError.invalidInput {
            // ok
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertFalse(actionInvoked)
    }

    func testStartActionFailureSurfacedAsErrorMessage() async {
        let viewModel = DiscussionStartViewModel(
            availableParticipants: [participantA, participantB],
            startAction: { _ in
                throw NSError(domain: "test", code: 1)
            }
        )
        viewModel.topic = "주제"
        viewModel.selectedParticipants = [agentA, agentB]

        do {
            _ = try await viewModel.start()
            XCTFail("expected throw")
        } catch {
            // throws — UI 가 errorMessage 로 surface
        }
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Helpers

    private let agentA = AgentID(rawValue: "agent-a")
    private let agentB = AgentID(rawValue: "agent-b")
    private var participantA: DiscussionParticipantOption {
        DiscussionParticipantOption(agentId: agentA, displayName: "Agent A")
    }
    private var participantB: DiscussionParticipantOption {
        DiscussionParticipantOption(agentId: agentB, displayName: "Agent B")
    }

    private func makeViewModel() -> DiscussionStartViewModel {
        DiscussionStartViewModel(
            availableParticipants: [participantA, participantB],
            startAction: { _ in ThreadID.new() }
        )
    }
}
