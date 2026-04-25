@testable import MaestroCore
import XCTest

/// AgentAdapter 프로토콜의 default implementation 검증.
/// 실제 구현체는 Tests/MaestroAdaptersTests/ 의 MockAdapter 사용 테스트로 검증.
final class AgentAdapterProtocolTests: XCTestCase {
    func testDefaultIconNameIsTerminal() {
        XCTAssertEqual(StubMinimalAdapter.iconName, "terminal")
    }

    func testInstanceIDMirrorsStaticID() {
        let adapter = StubMinimalAdapter()
        XCTAssertEqual(adapter.id, StubMinimalAdapter.id)
        XCTAssertEqual(adapter.displayName, StubMinimalAdapter.displayName)
        XCTAssertEqual(adapter.iconName, StubMinimalAdapter.iconName)
    }

    func testDefaultListSlashCommandsReturnsEmpty() async throws {
        let adapter = StubMinimalAdapter()
        let session = try makeStubSession()
        let commands = await adapter.listSlashCommands(in: session)
        XCTAssertTrue(commands.isEmpty)
    }

    func testDefaultStreamMessageEmitsTextThenCompletion() async throws {
        let adapter = StubMinimalAdapter()
        let session = try makeStubSession()
        let envelope = try makeEnvelope(body: "hi")
        let stream = adapter.streamMessage(envelope, in: session)
        var collected: [ResponseChunk] = []
        for try await chunk in stream {
            collected.append(chunk)
        }
        XCTAssertEqual(collected.count, 2)
        XCTAssertEqual(collected[0].kind, .text)
        XCTAssertEqual(collected[0].content, "echo:hi")
        XCTAssertEqual(collected[1].kind, .completion)
    }

    func testDefaultStreamPropagatesErrorFromSendMessage() async throws {
        let adapter = StubFailingAdapter()
        let session = try makeStubSession()
        let envelope = try makeEnvelope(body: "")
        let stream = adapter.streamMessage(envelope, in: session)
        do {
            for try await _ in stream {}
            XCTFail("expected error from sendMessage to surface in stream")
        } catch let err as AdapterError {
            XCTAssertEqual(err, .unsupported(operation: "stub"))
        }
    }

    // MARK: - helpers

    private func makeStubSession() throws -> Session {
        Session(
            id: SessionID.new(),
            agentId: try AgentID.validated(rawValue: "stub"),
            adapterId: try AdapterID.validated(rawValue: "stub"),
            folderPath: URL(fileURLWithPath: "/tmp/x"),
            createdAt: Date(timeIntervalSince1970: 0),
            lastActivityAt: Date(timeIntervalSince1970: 0),
            status: .active
        )
    }

    private func makeEnvelope(body: String) throws -> MessageEnvelope {
        MessageEnvelope.task(
            from: try AgentID.validated(rawValue: "alice"),
            to: try AgentID.validated(rawValue: "bob"),
            body: body
        )
    }
}

// MARK: - Test stubs

/// 최소 구현 — default implementations 가 어디까지 채워주는지 검증.
private struct StubMinimalAdapter: AgentAdapter {
    static let id = "stub-min"
    static let displayName = "Stub Minimal"
    // iconName 의도적으로 미구현 → default "terminal" 검증

    func detect() async -> AdapterDetection { .notInstalled() }

    func createSession(folderPath: URL) async throws -> Session {
        Session(
            id: SessionID.new(),
            agentId: try AgentID.validated(rawValue: "stub"),
            adapterId: try AdapterID.validated(rawValue: "stub"),
            folderPath: folderPath,
            createdAt: Date(),
            lastActivityAt: Date(),
            status: .active
        )
    }

    func destroySession(_ id: SessionID) async throws {}

    func sendMessage(
        _ envelope: MessageEnvelope, in session: Session
    ) async throws -> MessageEnvelope {
        MessageEnvelope.report(
            from: envelope.to,
            inReplyTo: envelope,
            body: "echo:\(envelope.body)"
        )
    }
}

private struct StubFailingAdapter: AgentAdapter {
    static let id = "stub-fail"
    static let displayName = "Stub Failing"

    func detect() async -> AdapterDetection { .notInstalled() }

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
