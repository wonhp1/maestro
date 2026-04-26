@testable import MaestroCore
import XCTest

@MainActor
final class ChatViewModelRelayResultTests: XCTestCase {
    func testAppendRelayResultAddsAssistantMessage() throws {
        let viewModel = try makeViewModel()
        viewModel.appendRelayResult(from: "CFO", body: "재무 담당입니다.")
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages[0].role, .assistant)
        XCTAssertEqual(viewModel.messages[0].status, .complete)
        XCTAssertTrue(viewModel.messages[0].content.contains("CFO"))
        XCTAssertTrue(viewModel.messages[0].content.contains("재무 담당입니다."))
    }

    func testMultipleRelayResultsAppendInOrder() throws {
        let viewModel = try makeViewModel()
        viewModel.appendRelayResult(from: "CFO", body: "재무")
        viewModel.appendRelayResult(from: "CMO", body: "마케팅")
        viewModel.appendRelayResult(from: "CTO", body: "기술")
        XCTAssertEqual(viewModel.messages.count, 3)
        XCTAssertTrue(viewModel.messages[0].content.contains("CFO"))
        XCTAssertTrue(viewModel.messages[1].content.contains("CMO"))
        XCTAssertTrue(viewModel.messages[2].content.contains("CTO"))
    }

    func testOnAssistantResponseCompleteFiresWithFinalBody() async throws {
        let adapter = EchoStubAdapter(reply: "OK <RELAY_TO=agent-x>do x</RELAY_TO>")
        let session = Session(
            id: SessionID.new(),
            agentId: try AgentID.validated(rawValue: "test"),
            adapterId: try AdapterID.validated(rawValue: "stub"),
            folderPath: URL(fileURLWithPath: "/tmp"),
            createdAt: Date(),
            lastActivityAt: Date(),
            status: .active
        )
        let viewModel = try ChatViewModel(adapter: adapter, session: session)
        let captured = CapturedBody()
        viewModel.onAssistantResponseComplete = { body in
            await captured.set(body)
        }
        viewModel.draft = "hi"
        viewModel.send()
        // 스트림 종료 대기 (placeholder .complete + callback 호출)
        for _ in 0..<200 where viewModel.isStreaming {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let received = await captured.value
        XCTAssertNotNil(received)
        XCTAssertTrue(received?.contains("RELAY_TO=agent-x") ?? false)
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

private actor CapturedBody {
    private(set) var value: String?
    func set(_ v: String) { value = v }
}

private struct EchoStubAdapter: AgentAdapter {
    static var id: String { "echo-stub" }
    static var displayName: String { "EchoStub" }
    let reply: String
    func detect() async -> AdapterDetection {
        AdapterDetection.notInstalled(at: Date())
    }
    func createSession(folderPath: URL) async throws -> Session {
        throw AdapterError.unsupported(operation: "echo")
    }
    func destroySession(_ id: SessionID) async throws {}
    func sendMessage(
        _ envelope: MessageEnvelope, in session: Session
    ) async throws -> MessageEnvelope {
        MessageEnvelope.task(from: envelope.to, to: envelope.from, body: reply)
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
        _ envelope: MessageEnvelope, in session: Session
    ) async throws -> MessageEnvelope {
        throw AdapterError.unsupported(operation: "stub")
    }
}
