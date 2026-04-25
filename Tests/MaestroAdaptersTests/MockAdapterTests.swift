import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

final class MockAdapterTests: XCTestCase {
    func testStaticMetadata() {
        XCTAssertEqual(MockAdapter.id, "mock")
        XCTAssertEqual(MockAdapter.displayName, "Mock Agent")
        XCTAssertFalse(MockAdapter.iconName.isEmpty)
    }

    func testDefaultDetectionReportsInstalledWithMockVersion() async {
        let adapter = MockAdapter()
        let detection = await adapter.detect()
        XCTAssertTrue(detection.isInstalled)
        XCTAssertEqual(detection.version, "0.0.0-mock")
        // Phase 4 must-fix: Mock 은 가상 — executablePath nil.
        XCTAssertNil(detection.executablePath)
    }

    func testDetectionOverrideRespected() async {
        let override = AdapterDetection.notInstalled()
        let adapter = MockAdapter(detectionOverride: override)
        let result = await adapter.detect()
        XCTAssertEqual(result, override)
    }

    func testCreateSessionAndDestroy() async throws {
        let adapter = MockAdapter()
        let folder = URL(fileURLWithPath: "/tmp/mock-folder")
        let session = try await adapter.createSession(folderPath: folder)
        XCTAssertEqual(session.folderPath, folder)
        XCTAssertEqual(session.status, .active)
        let activeSessions = await adapter.sessions
        XCTAssertEqual(activeSessions.count, 1)

        try await adapter.destroySession(session.id)
        let afterDestroy = await adapter.sessions
        XCTAssertTrue(afterDestroy.isEmpty)
    }

    func testDestroyUnknownSessionThrows() async throws {
        let adapter = MockAdapter()
        let unknown = SessionID.new()
        do {
            try await adapter.destroySession(unknown)
            XCTFail("expected unknownSession")
        } catch let err as AdapterError {
            XCTAssertEqual(err, .unknownSession(id: unknown))
        }
    }

    func testEchoSendMessageDefault() async throws {
        let adapter = MockAdapter()
        let session = try await adapter.createSession(folderPath: URL(fileURLWithPath: "/tmp"))
        let env = MessageEnvelope.task(
            from: try AgentID.validated(rawValue: "alice"),
            to: try AgentID.validated(rawValue: "bob"),
            body: "ping"
        )
        let response = try await adapter.sendMessage(env, in: session)
        XCTAssertEqual(response.body, "[Mock mock] ping")
        XCTAssertEqual(response.from.rawValue, "bob")
        XCTAssertEqual(response.to.rawValue, "alice")
        XCTAssertEqual(response.inReplyTo, env.id)
        let count = await adapter.processedCount
        XCTAssertEqual(count, 1)
    }

    func testCustomResponderInvoked() async throws {
        let adapter = MockAdapter(responder: { env, _ in
            MessageEnvelope.report(
                from: env.to,
                inReplyTo: env,
                body: "custom:\(env.body)"
            )
        })
        let session = try await adapter.createSession(folderPath: URL(fileURLWithPath: "/tmp"))
        let env = MessageEnvelope.task(
            from: try AgentID.validated(rawValue: "a"),
            to: try AgentID.validated(rawValue: "b"),
            body: "x"
        )
        let response = try await adapter.sendMessage(env, in: session)
        XCTAssertEqual(response.body, "custom:x")
    }

    func testSendMessageOnUnknownSessionThrows() async throws {
        let adapter = MockAdapter()
        let stranger = Session(
            id: SessionID.new(),
            agentId: try AgentID.validated(rawValue: "a"),
            adapterId: try AdapterID.validated(rawValue: "mock"),
            folderPath: URL(fileURLWithPath: "/tmp"),
            createdAt: Date(),
            lastActivityAt: Date(),
            status: .active
        )
        let env = MessageEnvelope.task(
            from: try AgentID.validated(rawValue: "a"),
            to: try AgentID.validated(rawValue: "b"),
            body: "x"
        )
        do {
            _ = try await adapter.sendMessage(env, in: stranger)
            XCTFail("expected unknownSession")
        } catch let err as AdapterError {
            XCTAssertEqual(err, .unknownSession(id: stranger.id))
        }
    }

    func testStreamMessageDefaultEmitsTextThenCompletion() async throws {
        let adapter = MockAdapter()
        let session = try await adapter.createSession(folderPath: URL(fileURLWithPath: "/tmp"))
        let env = MessageEnvelope.task(
            from: try AgentID.validated(rawValue: "alice"),
            to: try AgentID.validated(rawValue: "bob"),
            body: "stream-me"
        )
        let stream = await adapter.streamMessage(env, in: session)
        var collected: [ResponseChunk] = []
        for try await chunk in stream {
            collected.append(chunk)
        }
        XCTAssertEqual(collected.count, 2)
        XCTAssertEqual(collected[0].kind, .text)
        XCTAssertEqual(collected[0].content, "[Mock mock] stream-me")
        XCTAssertEqual(collected[1].kind, .completion)
    }

    func testListSlashCommandsReturnsConfigured() async throws {
        let cmds = [
            SlashCommand(name: "compact", description: "Compact"),
            SlashCommand(name: "review", description: "Review"),
        ]
        let adapter = MockAdapter(slashCommands: cmds)
        let session = try await adapter.createSession(folderPath: URL(fileURLWithPath: "/tmp"))
        let result = await adapter.listSlashCommands(in: session)
        XCTAssertEqual(result, cmds)
    }

    // MARK: - Registry integration

    func testMockAdapterRegistersInRegistry() async throws {
        let registry = AdapterRegistry()
        let adapter = MockAdapter()
        try await registry.register(adapter)
        let count = await registry.count
        XCTAssertEqual(count, 1)
        let retrieved = await registry.adapter(for: MockAdapter.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "mock")
    }

    func testRegistryDetectAllSurfacesMockDetection() async throws {
        let registry = AdapterRegistry()
        try await registry.register(MockAdapter())
        let results = await registry.detectAll()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results["mock"]?.version, "0.0.0-mock")
    }
}
