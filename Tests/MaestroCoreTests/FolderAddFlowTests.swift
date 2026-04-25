@testable import MaestroCore
import XCTest

@MainActor
final class FolderAddFlowTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppSupportPaths!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "FolderAddFlowTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        paths = AppSupportPaths(root: tempRoot)
        try paths.ensureAllDirectoriesExist()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testAddFolderViaPickerDeferAdapterDecisionToSheet() async throws {
        let registry = FolderRegistry(paths: paths)
        let folderURL = try makeFolder(named: "MyApp")
        let picker = StubFolderPicker(results: [folderURL])
        let viewModel = FolderViewModel(
            registry: registry, picker: picker,
            defaultAdapterID: AdapterID(rawValue: "claude")
        )
        await viewModel.bootstrap()

        await viewModel.addFolderViaPicker()

        // 폴더는 아직 등록되지 않음 — vendor 선택 sheet 가 열림.
        XCTAssertEqual(viewModel.folders.count, 0)
        XCTAssertEqual(viewModel.pendingFolderURL?.standardizedFileURL, folderURL.standardizedFileURL)
    }

    func testConfirmAddRegistersFolderWithChosenAdapter() async throws {
        let registry = FolderRegistry(paths: paths)
        let folderURL = try makeFolder(named: "Backend")
        let picker = StubFolderPicker(results: [folderURL])
        let viewModel = FolderViewModel(
            registry: registry, picker: picker,
            defaultAdapterID: AdapterID(rawValue: "claude")
        )
        await viewModel.bootstrap()

        await viewModel.addFolderViaPicker()
        await viewModel.confirmPendingAdd(adapterId: AdapterID(rawValue: "aider"))

        XCTAssertEqual(viewModel.folders.count, 1)
        XCTAssertEqual(viewModel.folders.first?.adapterId.rawValue, "aider")
        XCTAssertNil(viewModel.pendingFolderURL)
    }

    func testCancelPendingAddClearsState() async throws {
        let registry = FolderRegistry(paths: paths)
        let folderURL = try makeFolder(named: "Notes")
        let picker = StubFolderPicker(results: [folderURL])
        let viewModel = FolderViewModel(
            registry: registry, picker: picker,
            defaultAdapterID: AdapterID(rawValue: "claude")
        )
        await viewModel.bootstrap()

        await viewModel.addFolderViaPicker()
        viewModel.cancelPendingAdd()

        XCTAssertNil(viewModel.pendingFolderURL)
        XCTAssertEqual(viewModel.folders.count, 0)
    }

    func testConfirmAfterCancelIsNoOp() async throws {
        let registry = FolderRegistry(paths: paths)
        let folderURL = try makeFolder(named: "Cancelled")
        let picker = StubFolderPicker(results: [folderURL])
        let viewModel = FolderViewModel(
            registry: registry, picker: picker,
            defaultAdapterID: AdapterID(rawValue: "claude")
        )
        await viewModel.bootstrap()

        await viewModel.addFolderViaPicker()
        viewModel.cancelPendingAdd()
        await viewModel.confirmPendingAdd(adapterId: AdapterID(rawValue: "claude"))

        XCTAssertEqual(viewModel.folders.count, 0)
        XCTAssertNil(viewModel.pendingFolderURL)
    }

    func testAddFolderUserCancelDoesNotSetPending() async throws {
        let registry = FolderRegistry(paths: paths)
        let picker = StubFolderPicker(results: [nil])
        let viewModel = FolderViewModel(
            registry: registry, picker: picker,
            defaultAdapterID: AdapterID(rawValue: "claude")
        )
        await viewModel.bootstrap()
        await viewModel.addFolderViaPicker()
        XCTAssertNil(viewModel.pendingFolderURL)
    }

    private func makeFolder(named name: String) throws -> URL {
        let url = tempRoot.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
