@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

final class AiderSlashCommandsTests: XCTestCase {
    func testBuiltInsContainCoreCommands() {
        let names = Set(AiderSlashCommands.builtIns.map(\.name))
        XCTAssertTrue(names.contains("add"))
        XCTAssertTrue(names.contains("drop"))
        XCTAssertTrue(names.contains("commit"))
        XCTAssertTrue(names.contains("undo"))
        XCTAssertTrue(names.contains("clear"))
        XCTAssertTrue(names.contains("help"))
    }

    func testAllAreCategorizedAsBuiltIn() {
        for cmd in AiderSlashCommands.builtIns {
            XCTAssertEqual(cmd.category, "built-in")
            XCTAssertFalse(cmd.name.isEmpty)
            XCTAssertFalse(cmd.description.isEmpty)
        }
    }

    func testCommandCountReasonable() {
        XCTAssertGreaterThanOrEqual(AiderSlashCommands.builtIns.count, 15)
    }

    func testNoNameDuplicates() {
        let names = AiderSlashCommands.builtIns.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }
}
