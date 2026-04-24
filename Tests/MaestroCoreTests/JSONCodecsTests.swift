@testable import MaestroCore
import XCTest

/// Phase 2 / Test — 공용 JSON 코덱의 형식 불변식 검증.
///
/// 이 코덱은 디스크 포맷의 유일한 진실 원천이므로 출력 바이트 수준에서 단언.
final class JSONCodecsTests: XCTestCase {
    struct Sample: Codable, Equatable {
        let bravo: Int
        let alpha: Date
        let zulu: String
    }

    // MARK: Output formatting contract

    func testEncoderProducesSortedKeys() throws {
        let sample = Sample(
            bravo: 2,
            alpha: Date(timeIntervalSince1970: 0),
            zulu: "z"
        )
        let data = try JSONEncoder.maestro.encode(sample)
        let json = String(decoding: data, as: UTF8.self)
        // alpha, bravo, zulu 순 (알파벳) — sortedKeys 옵션 검증
        let alphaIdx = json.range(of: "alpha")!.lowerBound
        let bravoIdx = json.range(of: "bravo")!.lowerBound
        let zuluIdx = json.range(of: "zulu")!.lowerBound
        XCTAssertTrue(alphaIdx < bravoIdx)
        XCTAssertTrue(bravoIdx < zuluIdx)
    }

    func testEncoderDoesNotEscapeSlashes() throws {
        struct WithSlash: Codable { let path: String }
        let data = try JSONEncoder.maestro.encode(WithSlash(path: "a/b/c"))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("a/b/c"))
        XCTAssertFalse(json.contains("a\\/b"), "슬래시 이스케이프 금지")
    }

    // MARK: Date fidelity

    func testDateRoundtripWithinMillisecondTolerance() throws {
        struct Wrap: Codable { let d: Date }
        let original = Wrap(d: Date(timeIntervalSince1970: 1_714_500_000.123))
        let data = try JSONEncoder.maestro.encode(original)
        let decoded = try JSONDecoder.maestro.decode(Wrap.self, from: data)
        // iso8601 fractional seconds 는 ms 정밀도. Double 정밀도 드리프트 허용.
        XCTAssertEqual(
            decoded.d.timeIntervalSince1970,
            original.d.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testDateRoundtripExactForWholeSeconds() throws {
        struct Wrap: Codable, Equatable { let d: Date }
        let original = Wrap(d: Date(timeIntervalSince1970: 1_714_500_000))
        let data = try JSONEncoder.maestro.encode(original)
        let decoded = try JSONDecoder.maestro.decode(Wrap.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEncodedDateIncludesFractionalSeconds() throws {
        struct Wrap: Codable { let d: Date }
        let data = try JSONEncoder.maestro.encode(
            Wrap(d: Date(timeIntervalSince1970: 1_714_500_000.456))
        )
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(".456"), "소수점 초 포함 필요 — 실제 JSON: \(json)")
    }

    func testDecoderAcceptsIso8601WithoutFractionalSeconds() throws {
        // 사용자 수동 편집 대비 — 소수점 없는 ISO-8601 도 허용해야.
        struct Wrap: Codable { let d: Date }
        let json = #"{"d":"2026-04-25T10:00:00Z"}"#.data(using: .utf8)!
        XCTAssertNoThrow(try JSONDecoder.maestro.decode(Wrap.self, from: json))
    }

    func testDecoderRejectsGarbageDate() {
        struct Wrap: Codable { let d: Date }
        let json = #"{"d":"not-a-date"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder.maestro.decode(Wrap.self, from: json))
    }

    // MARK: Maestro type integration

    func testEnvelopeFileLikeRepresentation() throws {
        let env = MessageEnvelope(
            id: EnvelopeID(rawValue: "e-42"),
            threadId: ThreadID(rawValue: "t-1"),
            inReplyTo: nil,
            from: AgentID(rawValue: "control"),
            to: AgentID(rawValue: "cpo"),
            type: .task,
            body: "한글",
            createdAt: Date(timeIntervalSince1970: 1_714_500_000.123),
            expectReply: true
        )
        let data = try JSONEncoder.maestro.encode(env)
        let json = String(decoding: data, as: UTF8.self)

        // 파일 포맷 안정성 검증 — 필드 키 존재 + 기본값 지정.
        XCTAssertTrue(json.contains(#""schemaVersion":1"#))
        XCTAssertTrue(json.contains(#""deliveryStatus":"pending""#))
        XCTAssertTrue(json.contains(#""type":"task""#))
        XCTAssertTrue(json.contains(#""body":"한글""#))
    }
}
