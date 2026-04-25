@testable import MaestroCore
import XCTest

final class MarkdownRendererTests: XCTestCase {
    // MARK: - render

    func testRenderInlineMarkdownProducesAttributedString() {
        let attr = MarkdownRenderer.render("**bold** and *italic*")
        let plain = String(attr.characters)
        XCTAssertTrue(plain.contains("bold"))
        XCTAssertTrue(plain.contains("italic"))
    }

    func testRenderEmptyStringReturnsEmpty() {
        let attr = MarkdownRenderer.render("")
        XCTAssertEqual(String(attr.characters), "")
    }

    func testPlainTextStripsMarkdownSyntax() {
        let plain = MarkdownRenderer.plainText("**hi** [link](https://x)")
        XCTAssertTrue(plain.contains("hi"))
        XCTAssertTrue(plain.contains("link"))
        XCTAssertFalse(plain.contains("**"))
    }

    // MARK: - segments

    func testSegmentsPlainProseReturnsSingleSegment() {
        let segments = MarkdownRenderer.segments("just text\nwith newlines")
        XCTAssertEqual(segments.count, 1)
        if case .prose(let text) = segments[0] {
            XCTAssertEqual(text, "just text\nwith newlines")
        } else {
            XCTFail("expected prose")
        }
    }

    func testSegmentsExtractsCodeBlock() {
        let md = """
        intro line

        ```swift
        let x = 1
        print(x)
        ```

        outro
        """
        let segments = MarkdownRenderer.segments(md)
        XCTAssertEqual(segments.count, 3)
        if case .prose(let p) = segments[0] {
            XCTAssertTrue(p.contains("intro line"))
        } else { XCTFail("expected prose first") }
        if case .codeBlock(let lang, let code) = segments[1] {
            XCTAssertEqual(lang, "swift")
            XCTAssertEqual(code, "let x = 1\nprint(x)")
        } else { XCTFail("expected code block") }
        if case .prose(let p) = segments[2] {
            XCTAssertTrue(p.contains("outro"))
        } else { XCTFail("expected prose last") }
    }

    func testSegmentsCodeBlockWithoutLanguage() {
        let md = "```\nplain code\n```"
        let segments = MarkdownRenderer.segments(md)
        XCTAssertEqual(segments.count, 1)
        if case .codeBlock(let lang, let code) = segments[0] {
            XCTAssertNil(lang)
            XCTAssertEqual(code, "plain code")
        } else {
            XCTFail("expected code block")
        }
    }

    func testSegmentsMultipleCodeBlocks() {
        let md = """
        ```
        first
        ```

        between

        ```py
        second
        ```
        """
        let segments = MarkdownRenderer.segments(md)
        // [code, prose, code]
        XCTAssertEqual(segments.count, 3)
        XCTAssertTrue(segments.contains { if case .codeBlock(_, let c) = $0 { return c == "first" } else { return false } })
        XCTAssertTrue(segments.contains { if case .codeBlock(_, let c) = $0 { return c == "second" } else { return false } })
    }

    func testSegmentsUnclosedFenceFallsBackToProse() {
        // 마감 fence 누락 — 데이터 손실 없이 prose 로 합쳐야.
        let md = """
        before
        ```
        unfinished code
        no end fence
        """
        let segments = MarkdownRenderer.segments(md)
        XCTAssertGreaterThanOrEqual(segments.count, 1)
        let total = segments.compactMap { seg -> String? in
            if case .prose(let s) = seg { return s }
            if case .codeBlock(_, let s) = seg { return s }
            return nil
        }.joined(separator: "\n")
        XCTAssertTrue(total.contains("before"))
        XCTAssertTrue(total.contains("unfinished code"))
    }

    func testSegmentsIgnoresInlineTripleBacktick() {
        // 라인 시작이 아닌 ``` 는 fence 로 인식 안 됨.
        let md = "this is `not` ``` a fence"
        let segments = MarkdownRenderer.segments(md)
        XCTAssertEqual(segments.count, 1)
        if case .prose = segments[0] { /* OK */ } else {
            XCTFail("expected prose only")
        }
    }

    /// Phase 8 must-fix: CRLF 라인 종료에서도 fence 정확 인식.
    func testSegmentsHandlesCRLFLineEndings() {
        let md = "intro\r\n```swift\r\nlet x = 1\r\n```\r\nend"
        let segments = MarkdownRenderer.segments(md)
        XCTAssertEqual(segments.count, 3)
        if case .codeBlock(let lang, let code) = segments[1] {
            XCTAssertEqual(lang, "swift", "language 에 \\r 가 남음")
            XCTAssertEqual(code, "let x = 1")
        } else {
            XCTFail("expected code block at [1]")
        }
    }

    /// Phase 8 sec must-fix: 위험한 URL 스킴이 link attribute 에서 제거됨.
    func testRenderStripsDangerousLinkSchemes() {
        let attr = MarkdownRenderer.render("[click](javascript:alert(1)) [safe](https://example.com)")
        var dangerousFound = false
        var safeFound = false
        for run in attr.runs {
            guard let link = run.link else { continue }
            if link.scheme?.lowercased() == "javascript" { dangerousFound = true }
            if link.scheme?.lowercased() == "https" { safeFound = true }
        }
        XCTAssertFalse(dangerousFound, "javascript: 스킴이 link 에서 제거되지 않음")
        XCTAssertTrue(safeFound, "https: 링크가 보존되지 않음")
    }

    func testRenderStripsFileScheme() {
        let attr = MarkdownRenderer.render("[evil](file:///etc/passwd)")
        for run in attr.runs {
            XCTAssertNil(run.link, "file:// 스킴 link 가 통과됨")
        }
    }

    /// Phase 8 sec must-fix: bidi 제어 문자 제거 — Trojan Source 방어.
    func testStripBidiControlsRemovesRLOAndZeroWidth() {
        let evil = "safe\u{202E}reversed\u{200B}invisible"
        let cleaned = MarkdownRenderer.stripBidiControls(evil)
        XCTAssertEqual(cleaned, "safereversedinvisible")
    }

    func testStripBidiControlsPreservesNormalText() {
        let normal = "hello world\n안녕\t한글"
        XCTAssertEqual(MarkdownRenderer.stripBidiControls(normal), normal)
    }
}
