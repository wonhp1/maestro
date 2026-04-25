@testable import MaestroCore
import XCTest

final class ResponseChunkTests: XCTestCase {
    func testTextFactoryProducesTextKind() {
        let chunk = ResponseChunk.text("hello")
        XCTAssertEqual(chunk.kind, .text)
        XCTAssertEqual(chunk.content, "hello")
    }

    func testCompletionFactoryProducesCompletionKind() {
        let chunk = ResponseChunk.completion(reason: "stop")
        XCTAssertEqual(chunk.kind, .completion)
        XCTAssertEqual(chunk.content, "stop")
    }

    func testCodableRoundtripPreservesAllFields() throws {
        let original = ResponseChunk(
            kind: .toolUse,
            content: #"{"name":"Read"}"#,
            timestamp: Date(timeIntervalSince1970: 1_714_500_000)
        )
        let data = try JSONEncoder.maestro.encode(original)
        let decoded = try JSONDecoder.maestro.decode(ResponseChunk.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testAllKindsAreCaseIterable() {
        // 새 case 추가 시 UI/router switch 도 업데이트되도록 강제하는 테스트.
        let kinds = Set(ResponseChunk.Kind.allCases)
        XCTAssertEqual(kinds, [.text, .thinking, .toolUse, .toolResult, .error, .completion])
    }
}
