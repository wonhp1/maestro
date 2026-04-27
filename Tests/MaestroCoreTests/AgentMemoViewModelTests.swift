@testable import MaestroCore
import XCTest

@MainActor
final class AgentMemoViewModelTests: XCTestCase {
    private var tempDir: URL!
    private var store: AgentMemoStore!
    private var viewModel: AgentMemoViewModel!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "memo-vm-test-\(UUID().uuidString)")
        store = AgentMemoStore(directory: tempDir)
        viewModel = AgentMemoViewModel(store: store)
    }

    override func tearDown() async throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    private func makeMemo(id: String, active: Bool = true) -> DiscussionMemo {
        DiscussionMemo(
            id: ThreadID(rawValue: id),
            title: "Title \(id)",
            body: "Body \(id)",
            sharedWith: [AgentID(rawValue: "agent-aaa")],
            updatedAt: Date(),
            active: active
        )
    }

    func testReloadPopulatesMemos() async throws {
        try await store.save(makeMemo(id: "d-1"))
        try await store.save(makeMemo(id: "d-2"))
        await viewModel.reload()
        XCTAssertEqual(viewModel.memos.count, 2)
    }

    func testToggleActivePersists() async throws {
        try await store.save(makeMemo(id: "d-1", active: true))
        await viewModel.reload()
        await viewModel.toggleActive(memoId: ThreadID(rawValue: "d-1"), active: false)
        let saved = await store.memo(id: ThreadID(rawValue: "d-1"))
        XCTAssertEqual(saved?.active, false)
        XCTAssertEqual(viewModel.memos.first(where: { $0.id.rawValue == "d-1" })?.active, false)
    }

    func testUpdateBodyPersists() async throws {
        try await store.save(makeMemo(id: "d-1"))
        await viewModel.reload()
        await viewModel.updateBody(memoId: ThreadID(rawValue: "d-1"), body: "수정된 결론")
        let saved = await store.memo(id: ThreadID(rawValue: "d-1"))
        XCTAssertEqual(saved?.body, "수정된 결론")
    }

    func testDeleteRemovesFromList() async throws {
        try await store.save(makeMemo(id: "d-1"))
        try await store.save(makeMemo(id: "d-2"))
        await viewModel.reload()
        await viewModel.delete(memoId: ThreadID(rawValue: "d-1"))
        XCTAssertEqual(viewModel.memos.count, 1)
        XCTAssertEqual(viewModel.memos.first?.id.rawValue, "d-2")
    }
}
