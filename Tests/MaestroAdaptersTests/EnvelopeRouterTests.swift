import Foundation
import MaestroAdapters
@testable import MaestroCore
import XCTest

final class EnvelopeRouterTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppSupportPaths!
    private var storage: EnvelopeStorage!
    private var logger: ThreadLogger!

    override func setUp() async throws {
        tempRoot = try TestSupport.makeTempDirectory()
        paths = AppSupportPaths(root: tempRoot)
        try paths.ensureAllDirectoriesExist()
        storage = EnvelopeStorage()
        logger = ThreadLogger(paths: paths)
    }

    override func tearDown() async throws {
        await logger.closeAll()
        TestSupport.removeTempDirectory(tempRoot)
    }

    private func makeMockResolved(adapter: MockAdapter) async throws -> ResolvedAgent {
        let session = try await adapter.createSession(
            folderPath: tempRoot
        )
        return ResolvedAgent(adapter: adapter, session: session)
    }

    // MARK: - dispatch (in-process)

    func testDispatchInvokesAdapterAndReturnsNormalizedReply() async throws {
        let adapter = MockAdapter()
        let resolver = StubAgentResolver()
        let resolved = try await makeMockResolved(adapter: adapter)
        let bobID = AgentID(rawValue: "bob")
        await resolver.register(resolved, for: bobID)

        let router = EnvelopeRouter(
            paths: paths, storage: storage, logger: logger, resolver: resolver
        )

        let envelope = MessageEnvelope.task(
            from: AgentID(rawValue: "alice"),
            to: bobID,
            body: "hello"
        )
        let reply = try await router.dispatch(envelope)

        XCTAssertEqual(reply.from, bobID)
        XCTAssertEqual(reply.to.rawValue, "alice")
        XCTAssertEqual(reply.threadId, envelope.threadId)
        XCTAssertEqual(reply.inReplyTo, envelope.id)
        XCTAssertEqual(reply.deliveryStatus, .delivered)
        XCTAssertTrue(reply.body.contains("hello"))

        let delivered = await router.deliveredCount
        XCTAssertEqual(delivered, 1)
    }

    func testDispatchWritesReplyToOutbox() async throws {
        let adapter = MockAdapter()
        let resolver = StubAgentResolver()
        let resolved = try await makeMockResolved(adapter: adapter)
        let bobID = AgentID(rawValue: "bob")
        await resolver.register(resolved, for: bobID)
        let router = EnvelopeRouter(
            paths: paths, storage: storage, logger: logger, resolver: resolver
        )
        let envelope = MessageEnvelope.task(
            from: AgentID(rawValue: "alice"), to: bobID, body: "hi"
        )

        let reply = try await router.dispatch(envelope)

        let outboxFile = paths.outboxFile(agent: envelope.from, envelope: reply.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outboxFile.path))
    }

    func testDispatchAppendsBothEnvelopesToThreadJSONL() async throws {
        let adapter = MockAdapter()
        let resolver = StubAgentResolver()
        let bobID = AgentID(rawValue: "bob")
        await resolver.register(try await makeMockResolved(adapter: adapter), for: bobID)
        let router = EnvelopeRouter(
            paths: paths, storage: storage, logger: logger, resolver: resolver
        )
        let envelope = MessageEnvelope.task(
            from: AgentID(rawValue: "alice"), to: bobID, body: "z"
        )

        _ = try await router.dispatch(envelope)
        await logger.closeAll()

        let threadFile = paths.threadFile(id: envelope.threadId)
        let content = try String(contentsOf: threadFile, encoding: .utf8)
        let lines = content.split(separator: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2, "input + reply should both be logged")
    }

    func testDispatchFailsWhenResolverThrows() async throws {
        let resolver = StubAgentResolver()  // 등록 안 함
        let router = EnvelopeRouter(
            paths: paths, storage: storage, logger: logger, resolver: resolver
        )
        let envelope = MessageEnvelope.task(
            from: AgentID(rawValue: "alice"),
            to: AgentID(rawValue: "ghost"),
            body: "no one home"
        )
        do {
            _ = try await router.dispatch(envelope)
            XCTFail("expected resolveFailure")
        } catch let error as EnvelopeRouterError {
            guard case .resolveFailure = error else {
                XCTFail("wrong: \(error)")
                return
            }
        }
        let failed = await router.failedCount
        XCTAssertEqual(failed, 1)
    }

    // MARK: - reply attribution (Phase 11 must)

    func testReplyAttributionWhenAdapterReturnsBareReply() async throws {
        // 어댑터가 inReplyTo / from / to 없이 응답했어도 router 가 강제 정규화해야 함.
        let adapter = MockAdapter()
        await adapter.setResponder { envelope, _ in
            // 의도적으로 잘못된 메타 — router 가 고쳐야 함
            MessageEnvelope(
                id: .new(),
                threadId: ThreadID(rawValue: "wrong-thread"),
                inReplyTo: nil,
                from: AgentID(rawValue: "wrong-from"),
                to: AgentID(rawValue: "wrong-to"),
                type: .report,
                body: "echo: \(envelope.body)",
                createdAt: Date(),
                expectReply: false
            )
        }
        let resolver = StubAgentResolver()
        let bobID = AgentID(rawValue: "bob")
        await resolver.register(try await makeMockResolved(adapter: adapter), for: bobID)
        let router = EnvelopeRouter(
            paths: paths, storage: storage, logger: logger, resolver: resolver
        )
        let envelope = MessageEnvelope.task(
            from: AgentID(rawValue: "alice"), to: bobID, body: "ping"
        )

        let reply = try await router.dispatch(envelope)
        XCTAssertEqual(reply.threadId, envelope.threadId, "router enforces threadId")
        XCTAssertEqual(reply.inReplyTo, envelope.id, "router enforces inReplyTo")
        XCTAssertEqual(reply.from, envelope.to, "router enforces from = original.to")
        XCTAssertEqual(reply.to, envelope.from, "router enforces to = original.from")
    }

    // MARK: - Concurrent dispatch (Phase 11 must — 10 envelopes)

    func testConcurrentDispatchAllSucceed() async throws {
        let adapter = MockAdapter()
        let resolver = StubAgentResolver()
        let bobID = AgentID(rawValue: "bob")
        await resolver.register(try await makeMockResolved(adapter: adapter), for: bobID)
        let router = EnvelopeRouter(
            paths: paths, storage: storage, logger: logger, resolver: resolver
        )

        let envelopes: [MessageEnvelope] = (0..<10).map { i in
            MessageEnvelope.task(
                from: AgentID(rawValue: "alice"),
                to: bobID,
                body: "msg-\(i)"
            )
        }

        let replies = try await withThrowingTaskGroup(of: MessageEnvelope.self) { group in
            for env in envelopes {
                group.addTask { try await router.dispatch(env) }
            }
            var collected: [MessageEnvelope] = []
            for try await reply in group { collected.append(reply) }
            return collected
        }

        XCTAssertEqual(replies.count, 10)
        let delivered = await router.deliveredCount
        XCTAssertEqual(delivered, 10)
    }

    // MARK: - Inbox watching (file → router → outbox)

    func testBindInboxProcessesDroppedEnvelopes() async throws {
        let adapter = MockAdapter()
        let resolver = StubAgentResolver()
        let bobID = AgentID(rawValue: "bob")
        await resolver.register(try await makeMockResolved(adapter: adapter), for: bobID)
        let router = EnvelopeRouter(
            paths: paths, storage: storage, logger: logger, resolver: resolver
        )
        await router.bindInbox(for: bobID)

        let envelope = MessageEnvelope.task(
            from: AgentID(rawValue: "alice"), to: bobID, body: "via inbox"
        )
        let inboxPath = paths.inboxFile(agent: bobID, envelope: envelope.id)
        try await storage.write(envelope, to: inboxPath)

        // wait for watcher pickup + dispatch
        var processed = false
        for _ in 0..<60 {  // 6초 max
            try await Task.sleep(nanoseconds: 100_000_000)
            let count = await router.deliveredCount
            if count >= 1 { processed = true; break }
        }
        await router.unbindAll()

        XCTAssertTrue(processed, "router should process inbox-dropped envelope")
        // inbox 파일은 처리 후 제거
        XCTAssertFalse(FileManager.default.fileExists(atPath: inboxPath.path))
        // outbox 응답은 존재
        let outboxDir = paths.outboxDir(for: envelope.from)
        let outboxContents = try FileManager.default.contentsOfDirectory(
            at: outboxDir, includingPropertiesForKeys: nil
        )
        XCTAssertEqual(outboxContents.count, 1)
    }

    // MARK: - DLQ (must-fix coverage)

    func testCorruptInboxFileGoesToDLQWithPreservedID() async throws {
        let adapter = MockAdapter()
        let resolver = StubAgentResolver()
        let bobID = AgentID(rawValue: "bob")
        await resolver.register(try await makeMockResolved(adapter: adapter), for: bobID)
        let router = EnvelopeRouter(
            paths: paths, storage: storage, logger: logger, resolver: resolver
        )
        await router.bindInbox(for: bobID)

        let envID = EnvelopeID.new()
        let inboxPath = paths.inboxFile(agent: bobID, envelope: envID)
        try Data("{not valid json".utf8).write(to: inboxPath)

        var moved = false
        for _ in 0..<60 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let dlqPath = paths.failedFile(envelope: envID)
            if FileManager.default.fileExists(atPath: dlqPath.path) {
                moved = true; break
            }
        }
        await router.unbindAll()

        XCTAssertTrue(moved, "corrupt envelope should be moved to DLQ with original ID (forensic)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: inboxPath.path))
    }

    func testAdapterThrowGoesToDLQ() async throws {
        // Use ThrowingAdapter — sendMessage 가 항상 throw
        let adapter = ThrowingAdapter()
        let session = try await adapter.createSession(folderPath: tempRoot)
        let resolver = StubAgentResolver()
        let bobID = AgentID(rawValue: "bob")
        await resolver.register(
            ResolvedAgent(adapter: adapter, session: session), for: bobID
        )
        let router = EnvelopeRouter(
            paths: paths, storage: storage, logger: logger, resolver: resolver
        )
        await router.bindInbox(for: bobID)

        let envelope = MessageEnvelope.task(
            from: AgentID(rawValue: "alice"), to: bobID, body: "fail"
        )
        let inboxPath = paths.inboxFile(agent: bobID, envelope: envelope.id)
        try await storage.write(envelope, to: inboxPath)

        var moved = false
        for _ in 0..<60 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let dlqPath = paths.failedFile(envelope: envelope.id)
            if FileManager.default.fileExists(atPath: dlqPath.path) {
                moved = true; break
            }
        }
        await router.unbindAll()

        XCTAssertTrue(moved, "adapter throw should land envelope in DLQ")
    }

    func testUnbindAllAwaitsInflightDispatch() async throws {
        let adapter = MockAdapter()
        await adapter.setResponderWithDelay(seconds: 0.4)
        let resolver = StubAgentResolver()
        let bobID = AgentID(rawValue: "bob")
        await resolver.register(try await makeMockResolved(adapter: adapter), for: bobID)
        let router = EnvelopeRouter(
            paths: paths, storage: storage, logger: logger, resolver: resolver
        )
        await router.bindInbox(for: bobID)

        let envelope = MessageEnvelope.task(
            from: AgentID(rawValue: "alice"), to: bobID, body: "slow"
        )
        let inboxPath = paths.inboxFile(agent: bobID, envelope: envelope.id)
        try await storage.write(envelope, to: inboxPath)

        // dispatch 가 시작되도록 잠시 대기
        try await Task.sleep(nanoseconds: 200_000_000)
        await router.unbindAll()

        // 응답이 outbox 에 정상 기록되었는지 (cancel 되지 않았다는 증거)
        let outboxDir = paths.outboxDir(for: envelope.from)
        let outboxContents = (try? FileManager.default.contentsOfDirectory(
            at: outboxDir, includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertEqual(outboxContents.count, 1, "in-flight dispatch should complete during unbind")
    }

    func testEnvelopeWithMismatchedToGoesToDLQ() async throws {
        let adapter = MockAdapter()
        let resolver = StubAgentResolver()
        let bobID = AgentID(rawValue: "bob")
        await resolver.register(try await makeMockResolved(adapter: adapter), for: bobID)
        let router = EnvelopeRouter(
            paths: paths, storage: storage, logger: logger, resolver: resolver
        )
        await router.bindInbox(for: bobID)

        // envelope.to = wrong-target 이지만 inbox/bob/ 에 위조 drop
        let envelope = MessageEnvelope.task(
            from: AgentID(rawValue: "alice"),
            to: AgentID(rawValue: "carol"),
            body: "spoof"
        )
        let inboxPath = paths.inboxFile(agent: bobID, envelope: envelope.id)
        try await storage.write(envelope, to: inboxPath)

        var moved = false
        for _ in 0..<60 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let dlqPath = paths.failedFile(envelope: envelope.id)
            if FileManager.default.fileExists(atPath: dlqPath.path) {
                moved = true; break
            }
        }
        await router.unbindAll()

        XCTAssertTrue(moved, "spoofed envelope should land in failed/")
        XCTAssertFalse(FileManager.default.fileExists(atPath: inboxPath.path))
    }
}

// MockAdapter responder setters
private extension MockAdapter {
    func setResponder(
        _ block: @escaping @Sendable (MessageEnvelope, Session) -> MessageEnvelope
    ) async {
        self.responder = block
    }

    func setResponderWithDelay(seconds: TimeInterval) async {
        self.responder = { envelope, _ in
            Thread.sleep(forTimeInterval: seconds)
            return MessageEnvelope.report(
                from: envelope.to, inReplyTo: envelope, body: "delayed: \(envelope.body)"
            )
        }
    }
}

/// 항상 throws 하는 어댑터 — DLQ dispatch-failure 테스트용.
private actor ThrowingAdapter: AgentAdapter {
    static let id = "throwing"
    static let displayName = "Throwing Mock"
    static let iconName = "exclamationmark.triangle"

    func detect() async -> AdapterDetection {
        AdapterDetection(isInstalled: true, version: "0", executablePath: nil, detectedAt: Date())
    }

    func createSession(folderPath: URL) async throws -> Session {
        Session(
            id: SessionID.new(),
            agentId: AgentID(rawValue: "throwing-agent"),
            adapterId: AdapterID(rawValue: Self.id),
            folderPath: folderPath,
            createdAt: Date(),
            lastActivityAt: Date(),
            status: .active
        )
    }

    func destroySession(_ id: SessionID) async throws {}

    func sendMessage(_ envelope: MessageEnvelope, in session: Session) async throws -> MessageEnvelope {
        throw AdapterError.processFailed(exitCode: 1, stderr: "intentional")
    }
}
