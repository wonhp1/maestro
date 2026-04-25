@testable import MaestroCore
import XCTest

final class APIKeyStorageTests: XCTestCase {
    private var storage: APIKeyStorage!
    private var keychain: KeychainStore!

    override func setUp() {
        super.setUp()
        keychain = KeychainStore(service: "com.maestro.tests.apikey.\(UUID().uuidString)")
        storage = APIKeyStorage(keychain: keychain)
    }

    override func tearDown() {
        try? keychain.deleteAll()
        super.tearDown()
    }

    func testSetAndGetRoundtrip() throws {
        try storage.setKey(for: "claude", value: "sk-test-1")
        XCTAssertEqual(try storage.key(for: "claude"), "sk-test-1")
    }

    func testEmptyValueDeletes() throws {
        try storage.setKey(for: "claude", value: "sk-x")
        try storage.setKey(for: "claude", value: "")
        XCTAssertNil(try storage.key(for: "claude"))
    }

    func testWhitespaceTrimmedAndDeletes() throws {
        try storage.setKey(for: "aider", value: "  sk-y  ")
        XCTAssertEqual(try storage.key(for: "aider"), "sk-y")
        try storage.setKey(for: "aider", value: "   ")
        XCTAssertNil(try storage.key(for: "aider"))
    }

    func testNamespaceSeparation() throws {
        try storage.setKey(for: "claude", value: "c1")
        try storage.setKey(for: "aider", value: "a1")
        XCTAssertEqual(try storage.key(for: "claude"), "c1")
        XCTAssertEqual(try storage.key(for: "aider"), "a1")
    }

    func testInvalidIDsRejected() {
        XCTAssertThrowsError(try storage.setKey(for: "", value: "x")) { error in
            XCTAssertEqual(error as? APIKeyStorageError, .invalidAdapterID(""))
        }
        XCTAssertThrowsError(try storage.setKey(for: "../bad", value: "x"))
        XCTAssertThrowsError(try storage.setKey(for: "with space", value: "x"))
        XCTAssertThrowsError(try storage.setKey(for: String(repeating: "a", count: 65), value: "x"))
    }

    func testDeleteIsIdempotent() throws {
        try storage.deleteKey(for: "ghost")  // 없는 것 — throws 안 됨
        try storage.setKey(for: "claude", value: "v")
        try storage.deleteKey(for: "claude")
        XCTAssertNil(try storage.key(for: "claude"))
    }

    func testMakeKeyFormat() throws {
        let key = try APIKeyStorage.makeKey(adapterID: "claude")
        XCTAssertEqual(key, "adapter:claude:apiKey")
    }
}
