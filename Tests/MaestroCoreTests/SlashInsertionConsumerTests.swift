@testable import MaestroCore
import XCTest

/// v0.7.0 Phase 1 — `pendingSlashInsertion` consume 정책 단위 테스트.
/// composer 의 SwiftUI wiring 자체는 manual smoke 로 검증 (UI test 인프라 없음).
final class SlashInsertionConsumerTests: XCTestCase {
    // MARK: shouldConsume

    func testShouldConsumeRejectsNil() {
        XCTAssertFalse(SlashInsertionConsumer.shouldConsume(pending: nil))
    }

    func testShouldConsumeRejectsEmptyString() {
        XCTAssertFalse(SlashInsertionConsumer.shouldConsume(pending: ""))
    }

    func testShouldConsumeRejectsWhitespaceOnly() {
        XCTAssertFalse(SlashInsertionConsumer.shouldConsume(pending: "   \n\t"))
    }

    func testShouldConsumeAcceptsValidSlashCommand() {
        XCTAssertTrue(SlashInsertionConsumer.shouldConsume(pending: "/help"))
    }

    func testShouldConsumeAcceptsCommandWithTrailingSpace() {
        // Phase 2 의 popover 가 인수 있는 명령에 trailing space 추가 — 의미 있는 값.
        XCTAssertTrue(SlashInsertionConsumer.shouldConsume(pending: "/review "))
    }

    // MARK: resolve

    func testResolveReturnsNilForNilPending() {
        XCTAssertNil(SlashInsertionConsumer.resolve(pending: nil))
    }

    func testResolveReturnsNilForEmptyPending() {
        XCTAssertNil(SlashInsertionConsumer.resolve(pending: ""))
        XCTAssertNil(SlashInsertionConsumer.resolve(pending: "   "))
    }

    func testResolveReturnsPendingForValidValue() {
        XCTAssertEqual(SlashInsertionConsumer.resolve(pending: "/help"), "/help")
    }

    func testResolvePreservesTrailingSpace() {
        // Phase 2 가 인수 있는 명령은 "/foo " 로 trailing space 박음 — preserve.
        XCTAssertEqual(SlashInsertionConsumer.resolve(pending: "/review "), "/review ")
    }
}
