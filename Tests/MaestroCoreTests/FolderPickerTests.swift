import Foundation
@testable import MaestroCore
import XCTest

final class FolderPickerTests: XCTestCase {
    func testStubReturnsConfiguredResultsInOrder() async throws {
        let urls = [
            URL(filePath: "/tmp/a"),
            nil,
            URL(filePath: "/tmp/b"),
        ]
        let picker = StubFolderPicker(results: urls)
        let r1 = try await picker.presentPicker(suggested: nil)
        let r2 = try await picker.presentPicker(suggested: nil)
        let r3 = try await picker.presentPicker(suggested: nil)
        XCTAssertEqual(r1?.path, "/tmp/a")
        XCTAssertNil(r2)
        XCTAssertEqual(r3?.path, "/tmp/b")
    }

    func testStubRecordsSuggestions() async throws {
        let picker = StubFolderPicker(results: [nil, nil])
        _ = try await picker.presentPicker(suggested: URL(filePath: "/tmp/x"))
        _ = try await picker.presentPicker(suggested: nil)
        let received = await picker.receivedSuggestions
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0]?.path, "/tmp/x")
        XCTAssertNil(received[1])
    }

    func testStubThrowsWhenExhausted() async {
        let picker = StubFolderPicker(results: [])
        do {
            _ = try await picker.presentPicker(suggested: nil)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? StubFolderPickerError, .noMoreResults)
        }
    }
}
