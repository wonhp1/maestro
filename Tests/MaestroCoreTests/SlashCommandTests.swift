@testable import MaestroCore
import XCTest

final class SlashCommandTests: XCTestCase {
    func testIDIsName() {
        let cmd = SlashCommand(name: "compact", description: "compact context")
        XCTAssertEqual(cmd.id, "compact")
    }

    func testCodableRoundtripPreservesAllFields() throws {
        let original = SlashCommand(
            name: "review",
            description: "Review the diff",
            category: "built-in"
        )
        let data = try JSONEncoder.maestro.encode(original)
        let decoded = try JSONDecoder.maestro.decode(SlashCommand.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCategoryIsOptional() {
        let cmd = SlashCommand(name: "x", description: "y")
        XCTAssertNil(cmd.category)
    }
}
