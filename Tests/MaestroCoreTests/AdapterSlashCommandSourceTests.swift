@testable import MaestroCore
import XCTest

/// v0.7.0 Phase 3 — 어댑터의 capturedSlashCommands() 를 SlashCommandSource 로
/// 변환하는 정책 검증.
final class AdapterSlashCommandSourceTests: XCTestCase {
    /// 테스트용 어댑터 — capturedSlashCommands 만 의미 있게 채움.
    private actor StubAdapter: AgentAdapter {
        static let id = "stub"
        static let displayName = "Stub"
        let captured: [String]

        init(captured: [String]) { self.captured = captured }

        func detect() async -> AdapterDetection {
            AdapterDetection(
                isInstalled: true, version: "test", executablePath: nil, detectedAt: Date()
            )
        }

        func createSession(folderPath: URL) async throws -> Session {
            throw AdapterError.notInstalled(adapterId: Self.id)
        }

        func destroySession(_ id: SessionID) async throws {}

        func sendMessage(
            _ envelope: MessageEnvelope, in session: Session
        ) async throws -> MessageEnvelope {
            throw AdapterError.notInstalled(adapterId: Self.id)
        }

        func capturedSlashCommands() async -> [String] {
            captured
        }
    }

    func testEmptyCaptureReturnsEmptySource() async {
        let adapter = StubAdapter(captured: [])
        let source = AdapterSlashCommandSource(adapter: adapter)
        let result = await source.discover()
        XCTAssertTrue(result.isEmpty)
    }

    func testNonEmptyCaptureWrapsAsBuiltinSource() async {
        let adapter = StubAdapter(captured: ["compact", "usage"])
        let source = AdapterSlashCommandSource(adapter: adapter)
        let result = await source.discover()
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map { $0.command.name }, ["compact", "usage"])
        XCTAssertTrue(result.allSatisfy { $0.source == .builtin })
    }

    func testRefreshAfterCaptureReturnsUpdatedList() async {
        // 동일 source 의 두 번 discover() 호출이 매번 fresh adapter 결과 반영
        // (registry refresh() 가 source.discover() 를 매번 호출하므로 verify).
        let adapter = StubAdapter(captured: ["compact"])
        let source = AdapterSlashCommandSource(adapter: adapter)
        let first = await source.discover()
        let second = await source.discover()
        XCTAssertEqual(first.map { $0.command.name }, second.map { $0.command.name })
        XCTAssertEqual(first.count, 1)
    }
}
