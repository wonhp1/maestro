import Foundation
@testable import MaestroCore
import XCTest

final class InboxWatcherTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppSupportPaths!

    override func setUpWithError() throws {
        tempRoot = try TestSupport.makeTempDirectory()
        paths = AppSupportPaths(root: tempRoot)
        try paths.ensureAllDirectoriesExist()
    }

    override func tearDownWithError() throws {
        TestSupport.removeTempDirectory(tempRoot)
    }

    private func writeEnvelope(
        id: EnvelopeID,
        to dir: URL,
        body: String = "x"
    ) async throws {
        let envelope = MessageEnvelope(
            id: id,
            threadId: ThreadID.new(),
            inReplyTo: nil,
            from: AgentID(rawValue: "alice"),
            to: AgentID(rawValue: "bob"),
            type: .task,
            body: body,
            createdAt: Date(),
            expectReply: true
        )
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let path = dir.appending(path: "\(id.rawValue).json")
        let data = try JSONEncoder.maestro.encode(envelope)
        try data.write(to: path)
    }

    func testReplaysExistingFilesOnStart() async throws {
        let agent = AgentID(rawValue: "bob")
        let dir = paths.inboxDir(for: agent)
        let id1 = EnvelopeID.new()
        let id2 = EnvelopeID.new()
        try await writeEnvelope(id: id1, to: dir)
        try await writeEnvelope(id: id2, to: dir)

        let watcher = InboxWatcher(agentId: agent, directory: dir, pollInterval: 60)
        let stream = await watcher.start()

        let collector = StringCollector()
        let collectTask = Task {
            for await url in stream {
                let stem = url.deletingPathExtension().lastPathComponent
                let count = await collector.append(stem)
                if count >= 2 { break }
            }
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        collectTask.cancel()
        await watcher.stop()

        let received = await collector.snapshot()
        XCTAssertEqual(Set(received), Set([id1.rawValue, id2.rawValue]))
    }

    func testEmitsOnNewFileDrop() async throws {
        let agent = AgentID(rawValue: "bob")
        let dir = paths.inboxDir(for: agent)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let watcher = InboxWatcher(agentId: agent, directory: dir, pollInterval: 0.5)
        let stream = await watcher.start()

        let receivedID = EnvelopeID.new()
        let collectTask = Task { () -> String? in
            for await url in stream {
                return url.deletingPathExtension().lastPathComponent
            }
            return nil
        }
        // 잠시 기다린 뒤 파일 drop
        try await Task.sleep(nanoseconds: 200_000_000)
        try await writeEnvelope(id: receivedID, to: dir)

        let received = await withTimeout(seconds: 3.0) { await collectTask.value }
        await watcher.stop()
        XCTAssertEqual(received, receivedID.rawValue)
    }

    func testIgnoresInvalidFilenames() async throws {
        let agent = AgentID(rawValue: "bob")
        let dir = paths.inboxDir(for: agent)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        // 잘못된 이름 파일 — Identifier.validated 가 reject (공백 포함, 또는 leading -)
        let badPath = dir.appending(path: "bad name with spaces.json")
        try Data("garbage".utf8).write(to: badPath)
        let badPath2 = dir.appending(path: "-starts-with-dash.json")
        try Data("garbage".utf8).write(to: badPath2)
        // 정상 파일도 하나
        let goodID = EnvelopeID.new()
        try await writeEnvelope(id: goodID, to: dir)

        let watcher = InboxWatcher(agentId: agent, directory: dir, pollInterval: 60)
        let stream = await watcher.start()
        let collector = StringCollector()
        let collectTask = Task {
            for await url in stream {
                let count = await collector.append(
                    url.deletingPathExtension().lastPathComponent
                )
                if count >= 1 { break }
            }
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        collectTask.cancel()
        await watcher.stop()

        let collected = await collector.snapshot()
        XCTAssertEqual(collected, [goodID.rawValue])
        let invalidCount = await watcher.invalidFileCount
        XCTAssertGreaterThanOrEqual(invalidCount, 1)
    }

    func testDoesNotEmitSameFileTwice() async throws {
        let agent = AgentID(rawValue: "bob")
        let dir = paths.inboxDir(for: agent)
        let id = EnvelopeID.new()
        try await writeEnvelope(id: id, to: dir)

        let watcher = InboxWatcher(agentId: agent, directory: dir, pollInterval: 0.3)
        let stream = await watcher.start()
        let collector = StringCollector()
        let collectTask = Task {
            for await url in stream {
                _ = await collector.append(url.lastPathComponent)
            }
        }
        try await Task.sleep(nanoseconds: 800_000_000)
        collectTask.cancel()
        await watcher.stop()

        let received = await collector.snapshot()
        XCTAssertEqual(received.count, 1, "watcher should dedupe same file")
    }
}

actor StringCollector {
    private var items: [String] = []

    func append(_ value: String) -> Int {
        items.append(value)
        return items.count
    }

    func snapshot() -> [String] { items }
}

private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async -> T?
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let result: T? = await group.next().flatMap { $0 }
        group.cancelAll()
        return result
    }
}
