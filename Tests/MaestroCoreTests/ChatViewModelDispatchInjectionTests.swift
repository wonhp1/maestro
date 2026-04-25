@testable import MaestroCore
import XCTest

@MainActor
final class ChatViewModelDispatchInjectionTests: XCTestCase {
    func testInjectIncomingDispatchAddsUserAndAssistantMessages() throws {
        let viewModel = try makeViewModel()
        let from = AgentID(rawValue: "control")
        let request = MessageEnvelope.task(
            from: from,
            to: viewModel.session.agentId,
            body: "역할 보고 부탁"
        )
        let reply = MessageEnvelope.task(
            from: viewModel.session.agentId,
            to: from,
            body: "CFO 입니다. 재무 담당."
        )
        viewModel.injectIncomingDispatch(request: request, reply: reply)

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].role, .user)
        XCTAssertTrue(viewModel.messages[0].content.contains("역할 보고 부탁"))
        XCTAssertEqual(viewModel.messages[1].role, .assistant)
        XCTAssertTrue(viewModel.messages[1].content.contains("CFO 입니다"))
        XCTAssertEqual(viewModel.messages[1].status, .complete)
    }

    func testInjectIncomingDispatchPrefixedWithSenderName() throws {
        let viewModel = try makeViewModel()
        let request = MessageEnvelope.task(
            from: AgentID(rawValue: "control"),
            to: viewModel.session.agentId,
            body: "test"
        )
        let reply = MessageEnvelope.task(
            from: viewModel.session.agentId,
            to: AgentID(rawValue: "control"),
            body: "ok"
        )
        viewModel.injectIncomingDispatch(
            request: request,
            reply: reply,
            requestSenderLabel: "Control"
        )
        XCTAssertTrue(viewModel.messages[0].content.contains("Control"))
    }

    func testInjectAfterUserSendDoesNotInterruptStreaming() throws {
        let viewModel = try makeViewModel()
        // 메시지 두 개 미리 — 사용자가 한 턴 보낸 적 있다고 가정
        let priorRequest = MessageEnvelope.task(
            from: AgentID(rawValue: "control"),
            to: viewModel.session.agentId,
            body: "earlier"
        )
        let priorReply = MessageEnvelope.task(
            from: viewModel.session.agentId,
            to: AgentID(rawValue: "control"),
            body: "earlier reply"
        )
        viewModel.injectIncomingDispatch(request: priorRequest, reply: priorReply)
        XCTAssertEqual(viewModel.messages.count, 2)

        let request = MessageEnvelope.task(
            from: AgentID(rawValue: "control"),
            to: viewModel.session.agentId,
            body: "second"
        )
        let reply = MessageEnvelope.task(
            from: viewModel.session.agentId,
            to: AgentID(rawValue: "control"),
            body: "second reply"
        )
        viewModel.injectIncomingDispatch(request: request, reply: reply)
        XCTAssertEqual(viewModel.messages.count, 4)
    }

    private func makeViewModel() throws -> ChatViewModel {
        let adapter = StubChatAdapter()
        let session = Session(
            id: SessionID.new(),
            agentId: try AgentID.validated(rawValue: "test"),
            adapterId: try AdapterID.validated(rawValue: "stub"),
            folderPath: URL(fileURLWithPath: "/tmp"),
            createdAt: Date(),
            lastActivityAt: Date(),
            status: .active
        )
        return try ChatViewModel(adapter: adapter, session: session)
    }
}

private struct StubChatAdapter: AgentAdapter {
    static var id: String { "stub" }
    static var displayName: String { "Stub" }

    func detect() async -> AdapterDetection {
        AdapterDetection.notInstalled(at: Date())
    }
    func createSession(folderPath: URL) async throws -> Session {
        throw AdapterError.unsupported(operation: "stub")
    }
    func destroySession(_ id: SessionID) async throws {}
    func sendMessage(
        _ envelope: MessageEnvelope,
        in session: Session
    ) async throws -> MessageEnvelope {
        throw AdapterError.unsupported(operation: "stub")
    }
}
