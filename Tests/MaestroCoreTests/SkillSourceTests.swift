@testable import MaestroCore
import XCTest

final class SkillSourceTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "SkillSourceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeSkill(_ dir: String, content: String) throws {
        let skillDir = tempRoot.appending(path: dir, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let file = skillDir.appending(path: "SKILL.md", directoryHint: .notDirectory)
        try content.data(using: .utf8)!.write(to: file)
    }

    func testEmptyDirectoryYieldsEmpty() async {
        let source = SkillSource(directory: tempRoot)
        let discovered = await source.discover()
        XCTAssertTrue(discovered.isEmpty)
    }

    func testParsesSkillFrontmatter() async throws {
        try makeSkill("feature-planner", content: """
        ---
        name: feature-planner
        description: Generate phased plans
        ---
        """)
        let source = SkillSource(directory: tempRoot)
        let discovered = await source.discover()
        XCTAssertEqual(discovered.count, 1)
        XCTAssertEqual(discovered[0].command.name, "feature-planner")
        XCTAssertEqual(discovered[0].command.description, "Generate phased plans")
        XCTAssertEqual(discovered[0].source, .skill)
    }

    func testFallsBackToDirectoryNameIfFrontmatterNameMissing() async throws {
        try makeSkill("my-skill", content: """
        ---
        description: hi
        ---
        """)
        let source = SkillSource(directory: tempRoot)
        let discovered = await source.discover()
        XCTAssertEqual(discovered.first?.command.name, "my-skill")
    }

    func testSkipsDirectoriesWithoutSkillFile() async throws {
        let dir = tempRoot.appending(path: "noskill", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try makeSkill("yes", content: "---\nname: yes\ndescription: \n---\n")
        let source = SkillSource(directory: tempRoot)
        let discovered = await source.discover()
        XCTAssertEqual(discovered.map(\.command.name), ["yes"])
    }

    func testRejectsInvalidDirectoryNames() async throws {
        try makeSkill(".hidden", content: "---\nname: hidden\ndescription:\n---")
        try makeSkill("ok", content: "---\nname: ok\ndescription:\n---")
        let source = SkillSource(directory: tempRoot)
        let discovered = await source.discover()
        XCTAssertEqual(discovered.map(\.command.name), ["ok"])
    }
}
