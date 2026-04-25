@testable import MaestroCore
import XCTest

final class ControlAgentSystemPromptTests: XCTestCase {
    func testEmptyAgentsRendersPlaceholder() {
        let prompt = ControlAgentSystemPrompt.build(agents: [])
        XCTAssertTrue(prompt.contains("아직 등록된"))
        XCTAssertTrue(prompt.contains("RELAY_TO"))
    }

    func testAgentsListedWithIDAndPath() {
        let prompt = ControlAgentSystemPrompt.build(agents: [
            ControlAgentSystemPrompt.AgentEntry(
                agentID: "agent-aaa", displayName: "MyApp", folderPath: "/Users/test/myapp"
            ),
            ControlAgentSystemPrompt.AgentEntry(
                agentID: "agent-bbb", displayName: "Design", folderPath: "/Users/test/design"
            ),
        ])
        XCTAssertTrue(prompt.contains("MyApp"))
        XCTAssertTrue(prompt.contains("agent-aaa"))
        XCTAssertTrue(prompt.contains("Design"))
        XCTAssertTrue(prompt.contains("agent-bbb"))
    }

    func testHomeDirectoryShortened() {
        let home = NSHomeDirectory()
        let prompt = ControlAgentSystemPrompt.build(agents: [
            ControlAgentSystemPrompt.AgentEntry(
                agentID: "x", displayName: "X", folderPath: "\(home)/Desktop/test"
            ),
        ])
        XCTAssertTrue(prompt.contains("~/Desktop/test"))
        XCTAssertFalse(prompt.contains(home))
    }

    func testRelayToFormatExplained() {
        let prompt = ControlAgentSystemPrompt.build(agents: [])
        XCTAssertTrue(prompt.contains("RELAY_TO: <agent-id>"))
        XCTAssertTrue(prompt.contains("위임할 작업 내용"))
    }
}

final class ControlAgentProvisionerTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppSupportPaths!
    private var registry: FolderRegistry!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "ControlAgentTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        paths = AppSupportPaths(root: tempRoot)
        try paths.ensureAllDirectoriesExist()
        registry = FolderRegistry(paths: paths)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testProvisionCreatesFolderAndCwd() async throws {
        let registration = try await ControlAgentProvisioner.provision(
            registry: registry, appSupportRoot: tempRoot
        )
        XCTAssertEqual(registration.id, ControlAgentProvisioner.controlFolderID)
        XCTAssertEqual(registration.displayName, "Control")
        XCTAssertTrue(FileManager.default.fileExists(atPath: registration.path.path))
        // README seeded
        let readme = registration.path.appending(path: "README.md", directoryHint: .notDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: readme.path))
    }

    func testProvisionIsIdempotent() async throws {
        let first = try await ControlAgentProvisioner.provision(
            registry: registry, appSupportRoot: tempRoot
        )
        let second = try await ControlAgentProvisioner.provision(
            registry: registry, appSupportRoot: tempRoot
        )
        XCTAssertEqual(first.id, second.id)
        let folders = await registry.list()
        XCTAssertEqual(folders.filter { $0.id == ControlAgentProvisioner.controlFolderID }.count, 1)
    }

    func testIsControlFolder() {
        XCTAssertTrue(ControlAgentProvisioner.isControlFolder(ControlAgentProvisioner.controlFolderID))
        XCTAssertFalse(ControlAgentProvisioner.isControlFolder(FolderID.new()))
    }
}

final class FolderListSnapshotTests: XCTestCase {
    func testReadAfterUpdate() {
        let snap = FolderListSnapshot()
        XCTAssertTrue(snap.read().isEmpty)
        let folder = FolderRegistration(
            id: FolderID.new(), displayName: "x",
            path: URL(fileURLWithPath: "/tmp/x"),
            adapterId: AdapterID(rawValue: "claude")
        )
        snap.update([folder])
        XCTAssertEqual(snap.read().count, 1)
        XCTAssertEqual(snap.read()[0].displayName, "x")
    }

    func testConcurrentReadsWriteSafe() async {
        let snap = FolderListSnapshot()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    let folder = FolderRegistration(
                        id: FolderID.new(),
                        displayName: "f\(i)",
                        path: URL(fileURLWithPath: "/tmp/\(i)"),
                        adapterId: AdapterID(rawValue: "claude")
                    )
                    snap.update([folder])
                    _ = snap.read()
                }
            }
        }
        // 동시 read/write 가 crash 없이 종료
        XCTAssertEqual(snap.read().count, 1)
    }
}
