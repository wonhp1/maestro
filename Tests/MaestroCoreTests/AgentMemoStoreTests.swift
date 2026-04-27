@testable import MaestroCore
import XCTest

/// v0.5.0 Phase 5 — 메모 저장소 + frontmatter encoder/decoder 단위 테스트.
final class AgentMemoStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "maestro-memo-test-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    private func makeMemo(
        id: String = "d-1",
        sharedWith: [String] = ["agent-aaa", "agent-bbb"],
        active: Bool = true
    ) -> DiscussionMemo {
        DiscussionMemo(
            id: ThreadID(rawValue: id),
            title: "Q3 전략 결정",
            body: "신규 시장 진입 + 기존 주력 유지.",
            sharedWith: sharedWith.map { AgentID(rawValue: $0) },
            updatedAt: Date(timeIntervalSince1970: 1_714_500_000),
            active: active
        )
    }

    // MARK: - Frontmatter codec

    func testEncodeDecodeRoundtrip() throws {
        let original = makeMemo()
        let text = DiscussionMemoCoder.encode(original)
        let decoded = try DiscussionMemoCoder.decode(text: text)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.body, original.body)
        XCTAssertEqual(decoded.sharedWith, original.sharedWith)
        XCTAssertEqual(decoded.active, original.active)
        XCTAssertEqual(decoded.updatedAt.timeIntervalSince1970,
                       original.updatedAt.timeIntervalSince1970,
                       accuracy: 1.0)
    }

    func testDecodeMissingFrontmatterThrows() {
        XCTAssertThrowsError(try DiscussionMemoCoder.decode(text: "no frontmatter"))
    }

    func testDecodeMissingIdThrows() {
        let text = """
        ---
        title: "x"
        ---
        body
        """
        XCTAssertThrowsError(try DiscussionMemoCoder.decode(text: text)) { err in
            if case DiscussionMemoError.missingRequiredField(let f) = err {
                XCTAssertEqual(f, "discussionId")
            } else {
                XCTFail("wrong error: \(err)")
            }
        }
    }

    func testEncodeEscapesQuotesInTitle() throws {
        let memo = DiscussionMemo(
            id: ThreadID(rawValue: "d-2"),
            title: "Q3 \"전략\"\n결정",
            body: "...",
            sharedWith: []
        )
        let text = DiscussionMemoCoder.encode(memo)
        let decoded = try DiscussionMemoCoder.decode(text: text)
        XCTAssertEqual(decoded.title, "Q3 \"전략\"\n결정")
    }

    // MARK: - Store

    func testSaveAndLoadAll() async throws {
        let store = AgentMemoStore(directory: tempDir)
        let memo = makeMemo()
        try await store.save(memo)
        try await store.loadAll()
        let all = await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, memo.id)
    }

    func testActiveMemosForAgent() async throws {
        let store = AgentMemoStore(directory: tempDir)
        try await store.save(makeMemo(id: "d-1", sharedWith: ["agent-aaa"]))
        try await store.save(makeMemo(id: "d-2", sharedWith: ["agent-bbb"]))
        try await store.save(
            makeMemo(id: "d-3", sharedWith: ["agent-aaa"], active: false)
        )
        let aaa = await store.activeMemos(for: AgentID(rawValue: "agent-aaa"))
        XCTAssertEqual(aaa.map { $0.id.rawValue }, ["d-1"], "비활성 d-3 제외")
        let bbb = await store.activeMemos(for: AgentID(rawValue: "agent-bbb"))
        XCTAssertEqual(bbb.map { $0.id.rawValue }, ["d-2"])
        let none = await store.activeMemos(for: AgentID(rawValue: "agent-xxx"))
        XCTAssertEqual(none.count, 0)
    }

    func testDeleteRemovesFromCacheAndDisk() async throws {
        let store = AgentMemoStore(directory: tempDir)
        try await store.save(makeMemo(id: "d-1"))
        try await store.delete(id: ThreadID(rawValue: "d-1"))
        let still = await store.memo(id: ThreadID(rawValue: "d-1"))
        XCTAssertNil(still)
        let path = tempDir.appending(path: "d-1.md").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testLoadAllSurvivesCorruptFile() async throws {
        let store = AgentMemoStore(directory: tempDir)
        try await store.save(makeMemo(id: "d-1"))
        // 손상 파일 추가
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data("not a memo".utf8).write(
            to: tempDir.appending(path: "broken.md")
        )
        try await store.loadAll()
        let all = await store.all()
        XCTAssertEqual(all.count, 1, "손상 파일 1개가 다른 메모 차단 X")
    }
}
