@testable import MaestroCore
import XCTest

/// Phase 2 / Test 2.0 — phantom-typed `Identifier<Tag>` 의 계약.
///
/// 서로 다른 도메인 ID (EnvelopeID / ThreadID / SessionID / AgentID) 를
/// 타입 시스템 수준에서 구분하는 것이 목표. 같은 `String` 을 랩하지만
/// 컴파일러가 섞어쓰기를 막아야 한다.
final class IdentifierTests: XCTestCase {
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
        XCTAssertEqual(dict[b], 42, "같은 rawValue 는 Dictionary 에서 같은 키로 취급")
    }

    func testIdentifierCodableRoundtrip() throws {
        let original = AgentID(rawValue: "cpo")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentID.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testIdentifierEncodesAsPlainString() throws {
        let id = EnvelopeID(rawValue: "e-42")
        let data = try JSONEncoder().encode(id)
        let json = String(data: data, encoding: .utf8)
        XCTAssertEqual(json, "\"e-42\"", "ID 는 JSON 에서 평문 문자열로 직렬화")
    }

    func testCustomStringConvertible() {
        let id = ThreadID(rawValue: "t-1")
        XCTAssertEqual("\(id)", "t-1")
    }

    func testEmptyStringIsInvalid() {
        // 빈 문자열 ID 는 factory 에서 허용하지 않음 (의도적 방어).
        // 단, rawValue 직접 구성은 허용 (마이그레이션 유연성 위함).
        XCTAssertThrowsError(try AgentID.validated(rawValue: ""))
        XCTAssertThrowsError(try AgentID.validated(rawValue: "   "))
    }

    func testValidatedAcceptsNonEmpty() throws {
        let id = try AgentID.validated(rawValue: "cpo")
        XCTAssertEqual(id.rawValue, "cpo")
    }
}
