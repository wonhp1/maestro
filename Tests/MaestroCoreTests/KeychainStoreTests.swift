@testable import MaestroCore
import XCTest

/// Keychain 은 실제 시스템 서비스를 쓴다. 테스트 격리를 위해 매 테스트마다 unique
/// service 이름 사용 + tearDown 에서 deleteAll.
final class KeychainStoreTests: XCTestCase {
    private var store: KeychainStore!

    override func setUp() {
        super.setUp()
        // 테스트별 고유 service — 다른 테스트와의 간섭 0
        store = KeychainStore(
            service: "com.maestro.tests.\(UUID().uuidString)"
        )
    }

    override func tearDown() {
        try? store.deleteAll()
        super.tearDown()
    }

    func testSetThenGet() throws {
        try store.set("api-key", value: "sk-secret-123")
        XCTAssertEqual(try store.get("api-key"), "sk-secret-123")
    }

    func testGetMissingKeyReturnsNil() throws {
        XCTAssertNil(try store.get("never-set"))
    }

    func testOverwriteExistingKey() throws {
        try store.set("token", value: "first")
        try store.set("token", value: "second")
        XCTAssertEqual(try store.get("token"), "second")
    }

    func testDeleteRemovesEntry() throws {
        try store.set("tmp", value: "x")
        try store.delete("tmp")
        XCTAssertNil(try store.get("tmp"))
    }

    func testDeleteMissingIsSuccess() {
        XCTAssertNoThrow(try store.delete("ghost"), "없는 키 삭제는 no-op")
    }

    func testDeleteAllRemovesEverything() throws {
        try store.set("a", value: "1")
        try store.set("b", value: "2")
        try store.set("c", value: "3")
        try store.deleteAll()
        XCTAssertNil(try store.get("a"))
        XCTAssertNil(try store.get("b"))
        XCTAssertNil(try store.get("c"))
    }

    func testValueWithKoreanAndEmojiRoundtrip() throws {
        let value = "🔐 한글 값 ✨"
        try store.set("unicode", value: value)
        XCTAssertEqual(try store.get("unicode"), value)
    }

    func testMultipleServicesAreIsolated() throws {
        let alt = KeychainStore(service: "com.maestro.tests.\(UUID().uuidString)")
        try store.set("k", value: "first-service")
        try alt.set("k", value: "second-service")
        XCTAssertEqual(try store.get("k"), "first-service")
        XCTAssertEqual(try alt.get("k"), "second-service")
        try? alt.deleteAll()
    }
}
