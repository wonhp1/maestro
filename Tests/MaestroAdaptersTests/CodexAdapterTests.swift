import Foundation
@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

/// v0.9.0 Phase 2A — CodexAdapter skeleton 검증.
/// (Phase 2B 에서 sendMessage / streamMessage tests 추가 예정)
final class CodexAdapterTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try TestSupport.makeTempDirectory(named: "codex-test")
    }

    override func tearDown() {
        TestSupport.removeTempDirectory(tempDir)
        super.tearDown()
    }

    // MARK: - detect

    func testDetectReturnsInstalledWhenCLIPresent() async throws {
        let adapter = try makeAdapter(executableExists: true)
        let detection = await adapter.detect()
        XCTAssertTrue(detection.isInstalled)
        XCTAssertEqual(detection.version, "0.125.0")
    }

    func testDetectReturnsNotInstalledWhenAbsent() async throws {
        let adapter = try makeAdapter(executableExists: false)
        let detection = await adapter.detect()
        XCTAssertFalse(detection.isInstalled)
    }

    func testDetectCachesResultBetweenCalls() async throws {
        let counter = CountingDetector(version: "0.125.0")
        let adapter = try CodexAdapter(detector: await counter.makeDetector())
        _ = await adapter.detect()
        _ = await adapter.detect()
        _ = await adapter.detect()
        let calls = await counter.callCount
        XCTAssertEqual(calls, 1, "성공한 detect 는 1회만 실제 호출 (cache)")
    }

    func testInvalidateDetectionCacheForcesRecheck() async throws {
        let counter = CountingDetector(version: "0.125.0")
        let adapter = try CodexAdapter(detector: await counter.makeDetector())
        _ = await adapter.detect()
        await adapter.invalidateDetectionCache()
        _ = await adapter.detect()
        let calls = await counter.callCount
        XCTAssertEqual(calls, 2)
    }

    // MARK: - createSession

    func testCreateSessionRegistersSession() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)
        XCTAssertEqual(session.adapterId.rawValue, "codex")
        XCTAssertEqual(session.status, .active)
        let active = await adapter.activeSessionIds()
        XCTAssertEqual(active.count, 1)
        XCTAssertTrue(active.contains(session.id))
    }

    func testCreateSessionWithPreferredID() async throws {
        let adapter = try makeAdapter()
        let preferredID = SessionID.new()
        let session = try await adapter.createSession(
            folderPath: tempDir,
            preferredSessionId: preferredID,
            modelId: "gpt-5"
        )
        XCTAssertEqual(session.id, preferredID)
        XCTAssertEqual(session.modelId, "gpt-5")
    }

    func testCreateSessionResolvesSymlinks() async throws {
        let adapter = try makeAdapter()
        // tempDir 자체가 symlink 일 가능성 (macOS /var → /private/var)
        let session = try await adapter.createSession(folderPath: tempDir)
        // resolved 결과는 absolute path 여야 함
        XCTAssertTrue(session.folderPath.path.hasPrefix("/"))
    }

    // MARK: - destroySession

    func testDestroySessionRemovesFromActiveSet() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)
        try await adapter.destroySession(session.id)
        let active = await adapter.activeSessionIds()
        XCTAssertEqual(active.count, 0)
    }

    func testDestroyUnknownSessionThrows() async throws {
        let adapter = try makeAdapter()
        do {
            try await adapter.destroySession(SessionID.new())
            XCTFail("expected unknownSession")
        } catch let err as AdapterError {
            if case .unknownSession = err { /* OK */ } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    // MARK: - availableModels / resolvedModel

    func testAvailableModelsReturnsKnownAliases() async throws {
        let adapter = try makeAdapter()
        let models = await adapter.availableModels()
        XCTAssertFalse(models.isEmpty)
        XCTAssertTrue(models.contains("gpt-5"), "gpt-5 should be in available models")
        XCTAssertTrue(models.contains("o1-preview"), "o1-preview should be in available models")
    }

    func testResolvedModelExplicitWhenSet() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(
            folderPath: tempDir, preferredSessionId: nil, modelId: "gpt-5-mini"
        )
        let resolved = await adapter.resolvedModel(for: session)
        XCTAssertEqual(resolved, "gpt-5-mini")
    }

    func testResolvedModelNilWhenNoExplicit() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)
        let resolved = await adapter.resolvedModel(for: session)
        XCTAssertNil(resolved)
    }

    // MARK: - Phase 2A skeleton — sendMessage stub

    func testSendMessageThrowsUnsupportedInPhase2A() async throws {
        // Phase 2A 는 skeleton — sendMessage 는 Phase 2B 에서 구현.
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)
        let env = makeEnvelope(body: "hi")
        do {
            _ = try await adapter.sendMessage(env, in: session)
            XCTFail("expected unsupported")
        } catch let err as AdapterError {
            if case .unsupported = err { /* OK */ } else {
                XCTFail("wrong: \(err)")
            }
        }
    }

    func testListSlashCommandsReturnsEmptyInPhase2A() async throws {
        let adapter = try makeAdapter()
        let session = try await adapter.createSession(folderPath: tempDir)
        let cmds = await adapter.listSlashCommands(in: session)
        XCTAssertTrue(cmds.isEmpty)
    }

    func testCapturedSlashCommandsEmptyInitially() async throws {
        let adapter = try makeAdapter()
        let cmds = await adapter.capturedSlashCommands()
        XCTAssertTrue(cmds.isEmpty)
    }

    // MARK: - Helpers

    private func makeAdapter(
        executableExists: Bool = true
    ) throws -> CodexAdapter {
        let detector = CLIDetector(
            locator: CodexTestLocator(
                url: executableExists ? URL(fileURLWithPath: "/usr/local/bin/codex") : nil
            ),
            executor: CodexDetectExecutor()
        )
        return try CodexAdapter(detector: detector)
    }

    private func makeEnvelope(body: String) -> MessageEnvelope {
        do {
            return MessageEnvelope.task(
                from: try AgentID.validated(rawValue: "user"),
                to: try AgentID.validated(rawValue: "codex"),
                body: body
            )
        } catch {
            fatalError("\(error)")
        }
    }
}

// MARK: - Stubs

private struct CodexTestLocator: ExecutableLocating {
    let url: URL?
    func locate(_ name: String) -> URL? { url }
}

private struct CodexDetectExecutor: ProcessExecuting {
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        ProcessOutput(stdout: "codex-cli 0.125.0\n", stderr: "", exitCode: 0)
    }
}

/// detect() cache 검증용 — 호출 횟수 추적.
private actor CountingDetector {
    private(set) var callCount: Int = 0
    let version: String

    init(version: String) {
        self.version = version
    }

    /// CLIDetector 가 사용하는 executor 를 통해 호출 횟수 카운트.
    func makeDetector() -> CLIDetector {
        let counter = self
        return CLIDetector(
            locator: CodexTestLocator(url: URL(fileURLWithPath: "/usr/local/bin/codex")),
            executor: CountingExecutor(counter: counter, version: version)
        )
    }

    fileprivate func bump() async { callCount += 1 }
}

private struct CountingExecutor: ProcessExecuting {
    let counter: CountingDetector
    let version: String

    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessOutput {
        await counter.bump()
        return ProcessOutput(stdout: "codex-cli \(version)\n", stderr: "", exitCode: 0)
    }
}
