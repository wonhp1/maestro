@testable import MaestroCore
import XCTest

/// v0.7.0 Phase 2 — SlashSuggestionEngine pure logic 단위 테스트.
final class SlashSuggestionEngineTests: XCTestCase {
    private let engine = SlashSuggestionEngine()

    /// 헬퍼 — DiscoveredSlashCommand 빠른 생성.
    private func cmd(
        _ name: String,
        args: [String]? = nil,
        source: SlashCommandSourceKind = .builtin
    ) -> DiscoveredSlashCommand {
        DiscoveredSlashCommand(
            command: SlashCommand(
                name: name,
                description: "",
                arguments: args
            ),
            source: source
        )
    }

    // MARK: - evaluate (no-suggestion cases)

    func testEvaluateEmptyDraftReturnsNil() {
        XCTAssertNil(engine.evaluate(draft: "", registrySnapshot: [cmd("help")]))
    }

    func testEvaluateNoSlashReturnsNil() {
        XCTAssertNil(engine.evaluate(draft: "hello world", registrySnapshot: [cmd("help")]))
    }

    func testEvaluateClosedTokenReturnsNil() {
        // "/help " — trailing space → token closed.
        XCTAssertNil(engine.evaluate(draft: "/help ", registrySnapshot: [cmd("help")]))
    }

    func testEvaluateNonSlashLastTokenReturnsNil() {
        // "/help world" — last token = "world", not slash.
        XCTAssertNil(engine.evaluate(draft: "/help world", registrySnapshot: [cmd("help")]))
    }

    func testEvaluateNoMatchingCandidateReturnsNil() {
        // "/xyz" — fuzzy match against "help" fails.
        XCTAssertNil(engine.evaluate(draft: "/xyz", registrySnapshot: [cmd("help")]))
    }

    // MARK: - evaluate (suggestion cases)

    func testEvaluateSlashOnlyReturnsAllCandidates() {
        let snap = [cmd("help"), cmd("clear"), cmd("review")]
        let result = engine.evaluate(draft: "/", registrySnapshot: snap)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.candidates.count, 3)
        XCTAssertEqual(result?.query, "")
    }

    func testEvaluatePartialQueryFiltersCandidates() {
        let snap = [cmd("help"), cmd("clear"), cmd("header")]
        let result = engine.evaluate(draft: "/he", registrySnapshot: snap)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.query, "he")
        // "help" + "header" 둘 다 'h'+'e' 부분 시퀀스. "clear" 는 'h' 없음 → 제외.
        XCTAssertEqual(result?.candidates.count, 2)
    }

    func testEvaluateLastSlashTokenInMiddle() {
        // "hello /he" — 마지막 token = "/he"
        let result = engine.evaluate(draft: "hello /he", registrySnapshot: [cmd("help")])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.query, "he")
    }

    func testEvaluateMultilineDraft() {
        // "line1\n/he" — newline 도 whitespace
        let draft = "line1\n/he"
        let result = engine.evaluate(draft: draft, registrySnapshot: [cmd("help")])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.query, "he")
    }

    func testEvaluateMultipleSlashTakesLast() {
        // "/old /ne" — 마지막 토큰 = "/ne"
        let snap = [cmd("new"), cmd("old")]
        let result = engine.evaluate(draft: "/old /ne", registrySnapshot: snap)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.query, "ne")
        XCTAssertTrue(result?.candidates.contains { $0.command.name == "new" } == true)
    }

    func testEvaluateExactMatchRanksHigher() {
        // "/help" — "help" 정확 매칭 vs "header" 부분 매칭 — help 가 위.
        let snap = [cmd("header"), cmd("help")]
        let result = engine.evaluate(draft: "/help", registrySnapshot: snap)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.candidates.first?.command.name, "help")
    }

    // MARK: - evaluate (replace range)

    func testReplaceRangeStartsAtSlashAndEndsAtDraftEnd() {
        let draft = "hello /he"
        let result = engine.evaluate(draft: draft, registrySnapshot: [cmd("help")])
        XCTAssertNotNil(result)
        let range = result!.replaceRange
        XCTAssertEqual(String(draft[range]), "/he")
    }

    func testReplaceRangeForSlashOnly() {
        let draft = "/"
        let result = engine.evaluate(draft: draft, registrySnapshot: [cmd("help")])
        XCTAssertNotNil(result)
        XCTAssertEqual(String(draft[result!.replaceRange]), "/")
    }

    // MARK: - applySelection

    func testApplySelectionNoArgsAppendsCommandOnly() {
        let draft = "/he"
        let snap = [cmd("help")]
        let result = engine.evaluate(draft: draft, registrySnapshot: snap)!
        let newDraft = engine.applySelection(
            draft: draft, suggestion: result, selected: snap[0]
        )
        XCTAssertEqual(newDraft, "/help")
    }

    func testApplySelectionWithArgsAppendsTrailingSpace() {
        let draft = "/re"
        let snap = [cmd("review", args: ["PR-url"])]
        let result = engine.evaluate(draft: draft, registrySnapshot: snap)!
        let newDraft = engine.applySelection(
            draft: draft, suggestion: result, selected: snap[0]
        )
        // 인수 있는 명령 → trailing space 만, <arg> literal 안 들어감 (TUI 방식)
        XCTAssertEqual(newDraft, "/review ")
    }

    func testApplySelectionPreservesPreContext() {
        let draft = "hello /he"
        let snap = [cmd("help")]
        let result = engine.evaluate(draft: draft, registrySnapshot: snap)!
        let newDraft = engine.applySelection(
            draft: draft, suggestion: result, selected: snap[0]
        )
        XCTAssertEqual(newDraft, "hello /help")
    }

    func testApplySelectionMultipleArgs() {
        let draft = "/cm"
        let snap = [cmd("cmd", args: ["a", "b"])]
        let result = engine.evaluate(draft: draft, registrySnapshot: snap)!
        let newDraft = engine.applySelection(
            draft: draft, suggestion: result, selected: snap[0]
        )
        // 멀티 인수도 마찬가지 — 사용자가 자유 타이핑
        XCTAssertEqual(newDraft, "/cmd ")
    }

    func testApplySelectionEmptyArgsArrayTreatedAsNoArgs() {
        // arguments: [] (빈 배열) — nil 과 동일하게 인수 없는 명령으로 처리
        let draft = "/he"
        let snap = [cmd("help", args: [])]
        let result = engine.evaluate(draft: draft, registrySnapshot: snap)!
        let newDraft = engine.applySelection(
            draft: draft, suggestion: result, selected: snap[0]
        )
        XCTAssertEqual(newDraft, "/help")
    }
}
