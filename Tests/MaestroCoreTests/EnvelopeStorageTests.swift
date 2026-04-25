import Foundation
@testable import MaestroCore
import XCTest

final class EnvelopeStorageTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try TestSupport.makeTempDirectory()
    }

    override func tearDownWithError() throws {
        TestSupport.removeTempDirectory(tempRoot)
    }

    private func makeEnvelope(body: String = "hello") -> MessageEnvelope {
        MessageEnvelope.task(
            from: AgentID(rawValue: "alice"),
            to: AgentID(rawValue: "bob"),
            body: body
        )
    }

    func testWriteCreatesFileWith0600Perms() async throws {
        let storage = EnvelopeStorage()
        let envelope = makeEnvelope()
        let path = tempRoot.appending(path: "env.json")

        try await storage.write(envelope, to: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))

        let attrs = try FileManager.default.attributesOfItem(atPath: path.path)
        let posix = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(posix, 0o600)
    }

    func testReadRoundTripsAllFields() async throws {
        let storage = EnvelopeStorage()
        let envelope = makeEnvelope(body: "test body")
        let path = tempRoot.appending(path: "env.json")
        try await storage.write(envelope, to: path)

        let loaded = try await storage.read(from: path)
        XCTAssertEqual(loaded.id, envelope.id)
        XCTAssertEqual(loaded.body, envelope.body)
        XCTAssertEqual(loaded.from, envelope.from)
        XCTAssertEqual(loaded.to, envelope.to)
        XCTAssertEqual(loaded.threadId, envelope.threadId)
    }

    func testReadRejectsOversizedFile() async throws {
        let storage = EnvelopeStorage(maxFileSize: 10)  // 매우 작은 cap
        let envelope = makeEnvelope(body: "hello world this is more than ten bytes")
        let path = tempRoot.appending(path: "huge.json")
        try await storage.write(envelope, to: path)

        do {
            _ = try await storage.read(from: path)
            XCTFail("expected resourceLimitExceeded")
        } catch {
            guard case PersistenceError.resourceLimitExceeded = error else {
                XCTFail("wrong error: \(error)")
                return
            }
        }
    }

    func testReadThrowsForMissingFile() async {
        let storage = EnvelopeStorage()
        let path = tempRoot.appending(path: "nope.json")
        do {
            _ = try await storage.read(from: path)
            XCTFail("expected fileNotFound")
        } catch {
            guard case PersistenceError.fileNotFound = error else {
                XCTFail("wrong error: \(error)")
                return
            }
        }
    }

    func testMoveTransfersFile() async throws {
        let storage = EnvelopeStorage()
        let envelope = makeEnvelope()
        let src = tempRoot.appending(path: "src.json")
        let dst = tempRoot.appending(path: "sub/dst.json")
        try await storage.write(envelope, to: src)

        try await storage.move(from: src, to: dst)
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.path))
    }

    func testMoveOverwritesExistingDestination() async throws {
        let storage = EnvelopeStorage()
        let env1 = makeEnvelope(body: "first")
        let env2 = makeEnvelope(body: "second")
        let src = tempRoot.appending(path: "src.json")
        let dst = tempRoot.appending(path: "dst.json")
        try await storage.write(env1, to: dst)
        try await storage.write(env2, to: src)

        try await storage.move(from: src, to: dst)
        let loaded = try await storage.read(from: dst)
        XCTAssertEqual(loaded.body, "second")
    }

    func testDeleteRemovesFile() async throws {
        let storage = EnvelopeStorage()
        let path = tempRoot.appending(path: "env.json")
        try await storage.write(makeEnvelope(), to: path)
        try await storage.delete(at: path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }

    func testDeleteIsNoOpForMissingFile() async throws {
        let storage = EnvelopeStorage()
        let path = tempRoot.appending(path: "missing.json")
        try await storage.delete(at: path)  // does not throw
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }
}
