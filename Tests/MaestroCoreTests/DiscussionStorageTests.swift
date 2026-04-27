@testable import MaestroCore
import XCTest

final class DiscussionStorageTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "discussions-test-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    private func makeRecord(id: String, envCount: Int = 2) -> DiscussionRecord {
        let threadId = ThreadID(rawValue: id)
        let alice = AgentID(rawValue: "alice")
        let bob = AgentID(rawValue: "bob")
        let discussion = Discussion(
            id: threadId,
            title: "test \(id)",
            participants: [alice, bob],
            moderatorId: nil,
            maxTurns: 10,
            state: .completed,
            turns: [],
            conclusion: "결론 텍스트"
        )
        let envelopes = (0..<envCount).map { i in
            MessageEnvelope(
                id: EnvelopeID(rawValue: "e-\(id)-\(i)"),
                threadId: threadId,
                inReplyTo: nil,
                from: i.isMultiple(of: 2) ? alice : bob,
                to: AgentID(rawValue: "engine"),
                type: .report,
                body: "msg \(i)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + i)),
                expectReply: false
            )
        }
        return DiscussionRecord(discussion: discussion, envelopes: envelopes)
    }

    func testSaveAndLoadRoundtrip() async throws {
        let storage = DiscussionStorage(directory: tempDir)
        let record = makeRecord(id: "d-1", envCount: 3)
        try await storage.save(record)
        let loaded = try await storage.load(id: ThreadID(rawValue: "d-1"))
        XCTAssertEqual(loaded?.id.rawValue, "d-1")
        XCTAssertEqual(loaded?.envelopes.count, 3)
        XCTAssertEqual(loaded?.discussion.conclusion, "결론 텍스트")
    }

    func testLoadAllReturnsByUpdatedAtDesc() async throws {
        let storage = DiscussionStorage(directory: tempDir)
        try await storage.save(makeRecord(id: "old"))
        try await Task.sleep(nanoseconds: 10_000_000)
        try await storage.save(makeRecord(id: "new"))
        let all = try await storage.loadAll()
        XCTAssertEqual(all.map { $0.id.rawValue }, ["new", "old"])
    }

    func testDeleteRemovesFile() async throws {
        let storage = DiscussionStorage(directory: tempDir)
        try await storage.save(makeRecord(id: "d-1"))
        try await storage.delete(id: ThreadID(rawValue: "d-1"))
        let loaded = try await storage.load(id: ThreadID(rawValue: "d-1"))
        XCTAssertNil(loaded)
    }

    func testLoadAllSurvivesCorruptFile() async throws {
        let storage = DiscussionStorage(directory: tempDir)
        try await storage.save(makeRecord(id: "ok"))
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        try Data("garbage".utf8).write(to: tempDir.appending(path: "broken.json"))
        let all = try await storage.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id.rawValue, "ok")
    }
}
