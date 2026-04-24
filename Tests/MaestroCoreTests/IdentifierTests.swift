@testable import MaestroCore
import XCTest

/// Phase 2 / Test — phantom-typed `Identifier<Tag>` 계약 + 보안 검증.
final class IdentifierTests: XCTestCase {
    // MARK: Basic contract

    func testNewIdentifierGeneratesUniqueValues() {
        let a = EnvelopeID.new()
        let b = EnvelopeID.new()
        XCTAssertNotEqual(a, b)
    }

    func testIdentifierRoundtripFromRawValue() {
        let raw = "abc-123"
        let id = ThreadID(rawValue: raw)
        XCTAssertEqual(id.rawValue, raw)
    }

    func testIdentifierHashableForDictionaryKey() {
        let a = SessionID(rawValue: "s-1")
        let b = SessionID(rawValue: "s-1")
        var dict: [SessionID: Int] = [:]
        dict[a] = 42
        XCTAssertEqual(dict[b], 42)
    }

    func testCustomStringConvertible() {
        let id = ThreadID(rawValue: "t-1")
        XCTAssertEqual("\(id)", "t-1")
    }

    // MARK: Codable (with validation)

    func testCodableRoundtripForValidID() throws {
        let original = AgentID(rawValue: "cpo")
        let data = try JSONEncoder.maestro.encode(original)
        let decoded = try JSONDecoder.maestro.decode(AgentID.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testIdentifierEncodesAsPlainString() throws {
        let id = EnvelopeID(rawValue: "e-42")
        let data = try JSONEncoder.maestro.encode(id)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"e-42\"")
    }

    func testDecodingRejectsInvalidID() {
        // 경로 traversal 이 파일에 남아 디스크에서 로드되는 시나리오 방어.
        let malicious = "\"../etc/passwd\"".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder.maestro.decode(AgentID.self, from: malicious))
    }

    // MARK: validated() — 허용 케이스

    func testValidatedAcceptsAlphaNumAndAllowedPunct() throws {
        let samples = ["cpo", "ai-news", "team_x", "agent.v2", "a1b2-c3_d4.e5"]
        for sample in samples {
            XCTAssertNoThrow(try AgentID.validated(rawValue: sample), "허용되어야 함: \(sample)")
        }
    }

    func testValidatedRejectsEmpty() {
        XCTAssertThrowsError(try AgentID.validated(rawValue: "")) { err in
            XCTAssertEqual(err as? IdentifierError, .emptyRawValue)
        }
    }

    func testValidatedRejectsWhitespaceAndControlChars() {
        XCTAssertThrowsError(try AgentID.validated(rawValue: "a b")) { err in
            XCTAssertEqual(err as? IdentifierError, .containsForbiddenCharacter)
        }
        XCTAssertThrowsError(try AgentID.validated(rawValue: "a\tb")) { err in
            XCTAssertEqual(err as? IdentifierError, .containsForbiddenCharacter)
        }
        XCTAssertThrowsError(try AgentID.validated(rawValue: "a\nb")) { err in
            XCTAssertEqual(err as? IdentifierError, .containsForbiddenCharacter)
        }
        XCTAssertThrowsError(try AgentID.validated(rawValue: "a\u{0000}b")) { err in
            XCTAssertEqual(err as? IdentifierError, .containsForbiddenCharacter)
        }
    }

    func testValidatedRejectsPathTraversal() {
        for sample in ["../etc", "a/../b", "..", "a/b", #"a\b"#] {
            XCTAssertThrowsError(try AgentID.validated(rawValue: sample), "차단 필요: \(sample)") { err in
                XCTAssertEqual(err as? IdentifierError, .pathTraversal)
            }
        }
    }

    func testValidatedRejectsLeadingDotOrDash() {
        XCTAssertThrowsError(try AgentID.validated(rawValue: ".hidden")) { err in
            XCTAssertEqual(err as? IdentifierError, .invalidLeadingCharacter)
        }
        XCTAssertThrowsError(try AgentID.validated(rawValue: "-flag")) { err in
            XCTAssertEqual(err as? IdentifierError, .invalidLeadingCharacter)
        }
    }

    func testValidatedRejectsShellMetacharacters() {
        for sample in ["a;b", "a|b", "a$b", "a`b", "a&b", "a(b)", "a<b>", "a*b"] {
            XCTAssertThrowsError(try AgentID.validated(rawValue: sample), "차단 필요: \(sample)") { err in
                XCTAssertEqual(err as? IdentifierError, .disallowedCharacter)
            }
        }
    }

    func testValidatedRejectsOverlyLongID() {
        let long = String(repeating: "a", count: 65)
        XCTAssertThrowsError(try AgentID.validated(rawValue: long)) { err in
            XCTAssertEqual(err as? IdentifierError, .tooLong(length: 65))
        }
    }

    func testNewIsAlwaysValid() throws {
        // UUID 는 허용 문자 집합 + 길이 제한 내 — `new()` 는 항상 validated 통과해야.
        for _ in 0..<20 {
            let id = AgentID.new()
            XCTAssertNoThrow(try AgentID.validated(rawValue: id.rawValue))
        }
    }
}
