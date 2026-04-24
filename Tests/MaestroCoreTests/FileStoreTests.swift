@testable import MaestroCore
import XCTest

final class FileStoreTests: XCTestCase {
    private struct TestValue: Codable, Equatable, Sendable {
        let name: String
        let count: Int
    }

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestSupport.makeTempDirectory(named: "file-store")
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempDir)
        super.tearDown()
    }

    func testSaveThenLoadRoundtrip() async throws {
        let path = tempDir.appending(path: "v.json")
        let store = FileStore<TestValue>(path: path)
        let value = TestValue(name: "test", count: 3)
        try await store.save(value)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, value)
    }

    func testLoadNonExistentThrowsFileNotFound() async {
        let path = tempDir.appending(path: "missing.json")
        let store = FileStore<TestValue>(path: path)
        do {
            _ = try await store.load()
            XCTFail("load 는 fileNotFound throw 해야")
        } catch let error as PersistenceError {
            XCTAssertEqual(error, .fileNotFound(path))
        } catch {
            XCTFail("예상과 다른 에러: \(error)")
        }
    }

    func testLoadIfExistsReturnsNilForMissing() async throws {
        let store = FileStore<TestValue>(path: tempDir.appending(path: "x.json"))
        let result = try await store.loadIfExists()
        XCTAssertNil(result)
    }

    func testLoadIfExistsReturnsValueWhenPresent() async throws {
        let path = tempDir.appending(path: "v.json")
        let store = FileStore<TestValue>(path: path)
        try await store.save(TestValue(name: "abc", count: 1))
        let loaded = try await store.loadIfExists()
        XCTAssertNotNil(loaded)
    }

    func testSaveCreatesParentDirectory() async throws {
        let nested = tempDir.appending(path: "a/b/c/v.json")
        let store = FileStore<TestValue>(path: nested)
        try await store.save(TestValue(name: "nested", count: 99))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func testSaveIsAtomicOverwrite() async throws {
        let path = tempDir.appending(path: "v.json")
        let store = FileStore<TestValue>(path: path)
        try await store.save(TestValue(name: "first", count: 1))
        try await store.save(TestValue(name: "second", count: 2))
        let loaded = try await store.load()
        XCTAssertEqual(loaded, TestValue(name: "second", count: 2))
    }

    func testDeleteRemovesFile() async throws {
        let path = tempDir.appending(path: "v.json")
        let store = FileStore<TestValue>(path: path)
        try await store.save(TestValue(name: "x", count: 0))
        let existedBefore = await store.exists()
        XCTAssertTrue(existedBefore)
        try await store.delete()
        let existedAfter = await store.exists()
        XCTAssertFalse(existedAfter)
    }

    func testDeleteIsIdempotent() async throws {
        let store = FileStore<TestValue>(path: tempDir.appending(path: "missing.json"))
        // await 를 XCTAssertNoThrow 에 못 넣음 — do/catch 로 직접 검증.
        do {
            try await store.delete()
        } catch {
            XCTFail("존재 안 해도 silent 해야 함: \(error)")
        }
    }

    func testDecodeFailureRaisesDecodingFailed() async throws {
        let path = tempDir.appending(path: "corrupt.json")
        try "not json at all".data(using: .utf8)!.write(to: path)
        let store = FileStore<TestValue>(path: path)
        do {
            _ = try await store.load()
            XCTFail("corrupt JSON 은 decodingFailed 로 변환되어야")
        } catch let error as PersistenceError {
            if case .decodingFailed = error {
                // pass
            } else {
                XCTFail("예상과 다른 에러 케이스: \(error)")
            }
        } catch {
            XCTFail("PersistenceError 로 래핑되어야: \(error)")
        }
    }
}
