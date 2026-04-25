@testable import MaestroCore
import XCTest

final class SlashCommandFrontmatterTests: XCTestCase {
    func testParsesFrontmatterFields() {
        let raw = """
        ---
        description: Compact context
        argument-hint: [topic]
        ---
        Body content here
        on multiple lines
        """
        let parsed = SlashCommandFrontmatter.parse(raw)
        XCTAssertEqual(parsed.fields["description"], "Compact context")
        XCTAssertEqual(parsed.fields["argument-hint"], "[topic]")
        XCTAssertEqual(parsed.body, "Body content here\non multiple lines")
    }

    func testWithoutFrontmatterTreatsAsBody() {
        let raw = "Just body text\nwith newline"
        let parsed = SlashCommandFrontmatter.parse(raw)
        XCTAssertEqual(parsed.fields, [:])
        XCTAssertEqual(parsed.body, raw)
    }

    func testUnclosedFrontmatterTreatsAsBody() {
        let raw = """
        ---
        description: Missing close
        body line
        """
        let parsed = SlashCommandFrontmatter.parse(raw)
        XCTAssertEqual(parsed.fields, [:])
        XCTAssertEqual(parsed.body, raw)
    }

    func testQuotedValuesUnquoted() {
        let raw = """
        ---
        description: "with quotes"
        argument-hint: 'single'
        ---
        body
        """
        let parsed = SlashCommandFrontmatter.parse(raw)
        XCTAssertEqual(parsed.fields["description"], "with quotes")
        XCTAssertEqual(parsed.fields["argument-hint"], "single")
    }

    func testLowerCasesKeys() {
        let raw = """
        ---
        Description: top
        ARGUMENT-HINT: x
        ---
        """
        let parsed = SlashCommandFrontmatter.parse(raw)
        XCTAssertEqual(parsed.fields["description"], "top")
        XCTAssertEqual(parsed.fields["argument-hint"], "x")
    }

    func testEmptyBodyAfterFrontmatter() {
        let raw = """
        ---
        description: only
        ---
        """
        let parsed = SlashCommandFrontmatter.parse(raw)
        XCTAssertEqual(parsed.fields["description"], "only")
        XCTAssertEqual(parsed.body, "")
    }

    func testColonInValuePreserved() {
        let raw = """
        ---
        description: Run /help: shows commands
        ---
        body
        """
        let parsed = SlashCommandFrontmatter.parse(raw)
        XCTAssertEqual(parsed.fields["description"], "Run /help: shows commands")
    }
}
