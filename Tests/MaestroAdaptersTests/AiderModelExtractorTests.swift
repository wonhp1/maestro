import Foundation
@testable import MaestroAdapters
import XCTest

/// v0.6.0 Phase 1 — Aider stdout 의 `Main model: <id>` 라인에서 모델 ID 추출.
final class AiderModelExtractorTests: XCTestCase {
    func testExtractMainModelLine() {
        let line = "Main model: gpt-4o with diff edit format, infinite output"
        XCTAssertEqual(AiderModelExtractor.extractMainModel(from: line), "gpt-4o")
    }

    func testExtractMainModelLineWithSimpleId() {
        let line = "Main model: claude-sonnet-4-5"
        XCTAssertEqual(
            AiderModelExtractor.extractMainModel(from: line),
            "claude-sonnet-4-5"
        )
    }

    func testExtractIgnoresLeadingWhitespace() {
        let line = "  Main model: deepseek-coder"
        XCTAssertEqual(
            AiderModelExtractor.extractMainModel(from: line),
            "deepseek-coder"
        )
    }

    func testExtractReturnsNilForUnrelatedLine() {
        XCTAssertNil(AiderModelExtractor.extractMainModel(from: "Aider v0.50.0"))
        XCTAssertNil(AiderModelExtractor.extractMainModel(from: "Editor model: ..."))
        XCTAssertNil(AiderModelExtractor.extractMainModel(from: "hello world"))
    }

    func testExtractReturnsNilForEmptyModelValue() {
        XCTAssertNil(AiderModelExtractor.extractMainModel(from: "Main model: "))
        XCTAssertNil(AiderModelExtractor.extractMainModel(from: "Main model:"))
    }

    func testExtractFromMultilineStdout() {
        let stdout = """
        Aider v0.50.0
        Main model: gpt-4o with diff edit format
        Weak model: gpt-3.5-turbo
        Git repo: .git
        """
        XCTAssertEqual(
            AiderModelExtractor.extractFromStdout(stdout),
            "gpt-4o"
        )
    }

    func testExtractFromStdoutReturnsNilWhenNoMainModel() {
        let stdout = "Aider v0.50.0\nGit repo: .git"
        XCTAssertNil(AiderModelExtractor.extractFromStdout(stdout))
    }
}
