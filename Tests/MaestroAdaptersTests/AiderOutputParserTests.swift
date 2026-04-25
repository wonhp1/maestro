@testable import MaestroAdapters
import XCTest

final class AiderOutputParserTests: XCTestCase {
    // MARK: - extractAssistantResponse

    func testTypicalAiderOutputExtractsResponseBody() {
        let raw = """
        Aider v0.74.2
        Main model: claude-sonnet-4-5 with diff edit format
        Git repo: .git with 3 files
        Repo-map: using 1024 tokens
        Added /path/to/file.py to the chat.

        > Explain this code

        This code reads a file and prints its contents.

        Specifically:
        1. Opens the file
        2. Reads lines

        Tokens: 1.2k sent, 234 received. Cost: $0.01
        """
        let response = AiderOutputParser.extractAssistantResponse(from: raw)
        XCTAssertTrue(response.hasPrefix("This code reads a file"))
        XCTAssertTrue(response.contains("1. Opens the file"))
        XCTAssertFalse(response.contains("Tokens:"))
        XCTAssertFalse(response.contains("Aider v"))
        XCTAssertFalse(response.contains("> Explain"))
    }

    /// Phase 9 must-fix: 첫 `> ` 를 anchor — assistant 의 markdown blockquote 가 anchor
    /// 가 되지 않도록. 본문에 또 다른 `> ` 가 있어도 그대로 보존.
    func testFirstUserEchoIsAnchorAndPreservesBlockquoteInBody() {
        let raw = """
        > prompt

        > note: this is a markdown blockquote in the response
        actual answer follows

        Tokens: 1k sent
        """
        let response = AiderOutputParser.extractAssistantResponse(from: raw)
        XCTAssertTrue(response.contains("> note:"))
        XCTAssertTrue(response.contains("actual answer follows"))
    }

    func testNoUserEchoFallsBackToHeaderStripping() {
        let raw = """
        Aider v0.74.2
        Main model: claude-sonnet-4-5
        Git repo: .git

        Plain response without echo

        Tokens: 1k sent
        """
        let response = AiderOutputParser.extractAssistantResponse(from: raw)
        XCTAssertTrue(response.contains("Plain response without echo"))
        XCTAssertFalse(response.contains("Aider v"))
        XCTAssertFalse(response.contains("Tokens:"))
    }

    func testEmptyResponseAfterUserEcho() {
        let raw = """
        > prompt only

        Tokens: 1k
        """
        let response = AiderOutputParser.extractAssistantResponse(from: raw)
        XCTAssertEqual(response, "")
    }

    func testCRLFInputHandledCorrectly() {
        let raw = "Aider v0.74.2\r\n> prompt\r\n\r\nresponse line\r\n\r\nTokens: 1k\r\n"
        let response = AiderOutputParser.extractAssistantResponse(from: raw)
        XCTAssertEqual(response, "response line")
    }

    func testCommitFooterEndsResponseExtraction() {
        let raw = """
        > fix bug

        Here is the fix:

        ```python
        def f(): return 1
        ```

        Commit abc123: fix bug
        """
        let response = AiderOutputParser.extractAssistantResponse(from: raw)
        XCTAssertTrue(response.contains("Here is the fix:"))
        XCTAssertTrue(response.contains("```python"))
        XCTAssertFalse(response.contains("Commit abc123"))
    }

    // MARK: - detectKnownError

    func testDetectsAuthError() {
        let raw = "litellm.exceptions.AuthenticationError: API key invalid"
        XCTAssertNotNil(AiderOutputParser.detectKnownError(in: raw))
    }

    func testDetectsRateLimit() {
        XCTAssertNotNil(
            AiderOutputParser.detectKnownError(in: "Error: rate limit exceeded")
        )
    }

    func testDetectsMissingApiKey() {
        XCTAssertNotNil(
            AiderOutputParser.detectKnownError(in: "Error: No API key found")
        )
    }

    func testReturnsNilForNormalOutput() {
        XCTAssertNil(AiderOutputParser.detectKnownError(in: "Aider v0.74.2\n> hi\n\nresponse"))
    }

    // MARK: - isHeaderOrFooter (streaming path)

    func testRecognizesKnownHeaderLines() {
        XCTAssertTrue(AiderOutputParser.isHeaderOrFooter("Aider v0.74.2"))
        XCTAssertTrue(AiderOutputParser.isHeaderOrFooter("Main model: claude-sonnet-4-5"))
        XCTAssertTrue(AiderOutputParser.isHeaderOrFooter("Git repo: .git with 3 files"))
        XCTAssertTrue(AiderOutputParser.isHeaderOrFooter("Tokens: 1.2k sent"))
        XCTAssertTrue(AiderOutputParser.isHeaderOrFooter("Cost: $0.01"))
        XCTAssertTrue(AiderOutputParser.isHeaderOrFooter("Commit abc: fix"))
    }

    func testDoesNotMisidentifyResponseLines() {
        XCTAssertFalse(AiderOutputParser.isHeaderOrFooter("This code does X"))
        XCTAssertFalse(AiderOutputParser.isHeaderOrFooter("```python"))
        XCTAssertFalse(AiderOutputParser.isHeaderOrFooter("- bullet point"))
    }

    func testEmptyLineNotHeader() {
        XCTAssertFalse(AiderOutputParser.isHeaderOrFooter(""))
        XCTAssertFalse(AiderOutputParser.isHeaderOrFooter("  "))
    }
}
