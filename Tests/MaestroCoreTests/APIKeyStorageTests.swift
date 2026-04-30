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

    // MARK: - v0.9.0 — Codex / Gemini namespace 자동 지원 검증

    func testCodexAndGeminiKeysSupportedAutomatically() throws {
        try storage.setKey(for: "codex", value: "sk-openai-fake")
        try storage.setKey(for: "gemini", value: "AIzaFakeGemini")
        XCTAssertEqual(try storage.key(for: "codex"), "sk-openai-fake")
        XCTAssertEqual(try storage.key(for: "gemini"), "AIzaFakeGemini")
        // 모든 4개 어댑터 namespace 격리
        try storage.setKey(for: "claude", value: "anthropic-key")
        try storage.setKey(for: "aider", value: "aider-key")
        XCTAssertEqual(try storage.key(for: "claude"), "anthropic-key")
        XCTAssertEqual(try storage.key(for: "aider"), "aider-key")
        XCTAssertEqual(try storage.key(for: "codex"), "sk-openai-fake")
        XCTAssertEqual(try storage.key(for: "gemini"), "AIzaFakeGemini")
    }

    func testCodexGeminiNamespaceFormat() throws {
        XCTAssertEqual(try APIKeyStorage.makeKey(adapterID: "codex"), "adapter:codex:apiKey")
        XCTAssertEqual(try APIKeyStorage.makeKey(adapterID: "gemini"), "adapter:gemini:apiKey")
    }
}
