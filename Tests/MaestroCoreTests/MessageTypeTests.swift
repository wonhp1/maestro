@testable import MaestroCore
import XCTest

/// Phase 2 / Test — MessageType enum 의 RawRepresentable + Codable 계약.
final class MessageTypeTests: XCTestCase {
    func testAllCasesExposed() {
        XCTAssertEqual(MessageType.allCases.count, 4)
        XCTAssertTrue(MessageType.allCases.contains(.task))
        XCTAssertTrue(MessageType.allCases.contains(.question))
        XCTAssertTrue(MessageType.allCases.contains(.report))
        XCTAssertTrue(MessageType.allCases.contains(.fyi))
    }

    func testRawValuesMatchGlossary() {
        XCTAssertEqual(MessageType.task.rawValue, "task")
        XCTAssertEqual(MessageType.question.rawValue, "question")
        XCTAssertEqual(MessageType.report.rawValue, "report")
        XCTAssertEqual(MessageType.fyi.rawValue, "fyi")
    }

    func testCodableRoundtrip() throws {
        for type in MessageType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(MessageType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }
}
