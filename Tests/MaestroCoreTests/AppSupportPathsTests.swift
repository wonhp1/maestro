@testable import MaestroCore
import XCTest

final class AppSupportPathsTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppSupportPaths!

    override func setUpWithError() throws {
        tempRoot = try TestSupport.makeTempDirectory(named: "paths")
        paths = AppSupportPaths(root: tempRoot)
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempRoot)
        super.tearDown()
    }

    func testTopLevelFilesUnderRoot() {
        XCTAssertEqual(paths.configFile.lastPathComponent, "config.json")
        XCTAssertEqual(paths.foldersFile.lastPathComponent, "folders.json")
        XCTAssertTrue(paths.configFile.path.hasPrefix(tempRoot.path))
        XCTAssertTrue(paths.foldersFile.path.hasPrefix(tempRoot.path))
    }

    func testDirectoriesAreUnderRoot() {
        for dir in [
            paths.sessionsDir, paths.agentsDir, paths.inboxRoot,
            paths.outboxRoot, paths.threadsDir, paths.failedDir, paths.logsDir,
        ] {
            XCTAssertTrue(
                dir.path.hasPrefix(tempRoot.path),
                "\(dir) 가 root 바깥으로 벗어남"
            )
        }
    }

    func testPerAgentInboxOutboxPaths() {
        let agent = AgentID(rawValue: "cpo")
        let env = EnvelopeID(rawValue: "e-42")

        let inbox = paths.inboxFile(agent: agent, envelope: env)
        XCTAssertTrue(inbox.path.contains("/inbox/cpo/"))
        XCTAssertEqual(inbox.lastPathComponent, "e-42.json")

        let outbox = paths.outboxFile(agent: agent, envelope: env)
        XCTAssertTrue(outbox.path.contains("/outbox/cpo/"))
    }

    func testThreadFileExtension() {
        let tid = ThreadID(rawValue: "t-1")
        XCTAssertEqual(paths.threadFile(id: tid).lastPathComponent, "t-1.jsonl")
    }

    func testEnsureAllDirectoriesExistCreatesThem() throws {
        try paths.ensureAllDirectoriesExist()
        let fm = FileManager.default
        var isDir: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: paths.sessionsDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        XCTAssertTrue(fm.fileExists(atPath: paths.threadsDir.path, isDirectory: &isDir))
        XCTAssertTrue(fm.fileExists(atPath: paths.logsDir.path, isDirectory: &isDir))
    }
}
