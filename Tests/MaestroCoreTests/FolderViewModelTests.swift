import Foundation
@testable import MaestroCore
import XCTest

@MainActor
final class FolderViewModelTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppSupportPaths!
    private var registry: FolderRegistry!

    override func setUp() async throws {
        tempRoot = try TestSupport.makeTempDirectory()
        paths = AppSupportPaths(root: tempRoot)
        try paths.ensureAllDirectoriesExist()
        registry = FolderRegistry(paths: paths)
    }

    override func tearDown() async throws {
        TestSupport.removeTempDirectory(tempRoot)
    }

    private func makeFolderURL() throws -> URL {
        let dir = tempRoot.appending(path: "p-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeViewModel(picker: FolderPicking) -> FolderViewModel {
        FolderViewModel(
            registry: registry,
            picker: picker,
            defaultAdapterID: AdapterID(rawValue: "claude")
        )
    }

    // MARK: - Bootstrap

    func testBootstrapLoadsExistingFolders() async throws {
        try await registry.loadFromDisk()
        let dir = try makeFolderURL()
        _ = try await registry.add(
            displayName: "Pre", path: dir, adapterId: AdapterID(rawValue: "claude")
        )

        let vm = makeViewModel(picker: StubFolderPicker(results: []))
        await vm.bootstrap()

        XCTAssertEqual(vm.folders.count, 1)
        XCTAssertEqual(vm.folders.first?.displayName, "Pre")
    }

    // MARK: - Add via picker

    func testAddFolderViaPickerHappyPath() async throws {
        let dir = try makeFolderURL()
        let picker = StubFolderPicker(results: [dir])
        let vm = makeViewModel(picker: picker)
        await vm.bootstrap()

        await vm.addFolderViaPicker()

        XCTAssertEqual(vm.folders.count, 1)
        XCTAssertEqual(vm.folders.first?.displayName, dir.lastPathComponent)
        XCTAssertEqual(vm.selectedFolderID, vm.folders.first?.id)
        XCTAssertNil(vm.errorMessage)
    }

    func testAddFolderViaPickerCancellationIsNoOp() async throws {
        let picker = StubFolderPicker(results: [nil])  // 사용자 취소
        let vm = makeViewModel(picker: picker)
        await vm.bootstrap()

        await vm.addFolderViaPicker()

        XCTAssertTrue(vm.folders.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    func testAddFolderSurfacesDuplicateError() async throws {
        let dir = try makeFolderURL()
        let picker = StubFolderPicker(results: [dir, dir])  // 같은 경로 두 번
        let vm = makeViewModel(picker: picker)
        await vm.bootstrap()

        await vm.addFolderViaPicker()
        await vm.addFolderViaPicker()

        XCTAssertEqual(vm.folders.count, 1)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("이미 등록된") ?? false)
    }

    // MARK: - Delete / select / rename

    func testDeleteFolderRemovesFromList() async throws {
        let dir = try makeFolderURL()
        let picker = StubFolderPicker(results: [dir])
        let vm = makeViewModel(picker: picker)
        await vm.bootstrap()
        await vm.addFolderViaPicker()
        let id = try XCTUnwrap(vm.folders.first?.id)

        await vm.deleteFolder(id: id)
        XCTAssertTrue(vm.folders.isEmpty)
        XCTAssertNil(vm.selectedFolderID)
    }

    func testDeleteFolderClearsSelectionIfTargetWasSelected() async throws {
        let dir1 = try makeFolderURL()
        let dir2 = try makeFolderURL()
        let picker = StubFolderPicker(results: [dir1, dir2])
        let vm = makeViewModel(picker: picker)
        await vm.bootstrap()
        await vm.addFolderViaPicker()
        await vm.addFolderViaPicker()
        let secondID = try XCTUnwrap(vm.folders.last?.id)
        let firstID = try XCTUnwrap(vm.folders.first?.id)
        vm.selectedFolderID = secondID

        await vm.deleteFolder(id: secondID)
        XCTAssertEqual(vm.selectedFolderID, firstID)
    }

    func testRenameUpdatesDisplayName() async throws {
        let dir = try makeFolderURL()
        let picker = StubFolderPicker(results: [dir])
        let vm = makeViewModel(picker: picker)
        await vm.bootstrap()
        await vm.addFolderViaPicker()
        let id = try XCTUnwrap(vm.folders.first?.id)

        await vm.rename(id: id, to: "New Name")
        // 이벤트가 reconcile 되도록 잠시 기다림
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(vm.folders.first?.displayName, "New Name")
    }

    func testChangeAdapterUpdatesFolder() async throws {
        let dir = try makeFolderURL()
        let picker = StubFolderPicker(results: [dir])
        let vm = makeViewModel(picker: picker)
        await vm.bootstrap()
        await vm.addFolderViaPicker()
        let id = try XCTUnwrap(vm.folders.first?.id)

        await vm.changeAdapter(id: id, to: AdapterID(rawValue: "aider"))
        XCTAssertEqual(vm.folders.first?.adapterId.rawValue, "aider")
        XCTAssertNil(vm.errorMessage)
    }

    func testSelectUpdatesIDAndTouchesRegistry() async throws {
        let dir = try makeFolderURL()
        let picker = StubFolderPicker(results: [dir])
        let vm = makeViewModel(picker: picker)
        await vm.bootstrap()
        await vm.addFolderViaPicker()
        let id = try XCTUnwrap(vm.folders.first?.id)
        vm.selectedFolderID = nil

        await vm.select(id: id)
        XCTAssertEqual(vm.selectedFolderID, id)
        let folder = await registry.get(id: id)
        XCTAssertNotNil(folder?.lastUsedAt)
    }

    // MARK: - Error dismissal

    func testDismissErrorClearsMessage() async throws {
        let vm = makeViewModel(picker: StubFolderPicker(results: []))
        vm.errorMessage = "boom"
        vm.dismissError()
        XCTAssertNil(vm.errorMessage)
    }
}
