@testable import MaestroAdapters
@testable import MaestroCore
import XCTest

/// v0.10.0 회귀 방지 — v0.9.6 critical 버그 (codex/gemini 폴더가 Claude 로 dispatch)
/// 의 직접 가드. AdapterRouter 가 folder.adapterId 를 정확히 selector 에 전달하고,
/// selector 의 모든 등록된 candidate 가 enabled 로 자동 사용되는지 검증.
final class AdapterRouterTests: XCTestCase {
    /// 실행 가능 stub — `createSession` 까지 정상 반환 (Session 본격 사용은 ChatFactory
    /// 가 처리하므로 여기서는 어댑터 ID 만 검증 가능하면 됨).
    private actor StubAdapter: AgentAdapter {
        nonisolated static let id: String = "_unused"
        nonisolated static let displayName: String = "Stub"
        nonisolated static let iconName: String = ""
        nonisolated let id: String
        nonisolated let displayName: String
        nonisolated let iconName: String
        let installed: Bool

        init(id: String, installed: Bool = true) {
            self.id = id
            self.displayName = id
            self.iconName = ""
            self.installed = installed
        }

        func detect() async -> AdapterDetection {
            installed
                ? AdapterDetection(
                    isInstalled: true,
                    version: "1.0",
                    executablePath: URL(fileURLWithPath: "/usr/bin/\(id)"),
                    detectedAt: Date()
                )
                : AdapterDetection.notInstalled()
        }

        func createSession(folderPath: URL) async throws -> Session {
            throw NSError(domain: "stub", code: 0)
        }
        func destroySession(_ id: SessionID) async throws {}
        func sendMessage(_ envelope: MessageEnvelope, in session: Session) async throws -> MessageEnvelope {
            envelope
        }
        func listSlashCommands(in session: Session) async -> [SlashCommand] { [] }
    }

    private func makeFolder(adapterId: String) -> FolderRegistration {
        FolderRegistration(
            displayName: "test-\(adapterId)",
            path: URL(fileURLWithPath: "/tmp/maestro-test"),
            adapterId: AdapterID(rawValue: adapterId)
        )
    }

    private func makeSelector(installedIDs: [String]) -> AdapterSelector {
        var candidates: [String: any AgentAdapter] = [:]
        for id in installedIDs {
            candidates[id] = StubAdapter(id: id, installed: true)
        }
        return AdapterSelector(
            candidates: candidates,
            fallback: StubAdapter(id: "fallback", installed: true)
        )
    }

    // MARK: - 회귀 가드: 4개 어댑터 ID → 정확히 그 어댑터로 라우팅

    func testCodexFolderRoutesToCodexAdapter() async {
        let selector = makeSelector(installedIDs: ["claude", "aider", "codex", "gemini"])
        let folder = makeFolder(adapterId: "codex")
        let adapter = await selector.resolve(folder: folder)
        XCTAssertEqual(adapter.id, "codex", "codex 폴더가 Claude 로 잘못 라우팅되던 v0.9.6 회귀 가드")
    }

    func testGeminiFolderRoutesToGeminiAdapter() async {
        let selector = makeSelector(installedIDs: ["claude", "aider", "codex", "gemini"])
        let folder = makeFolder(adapterId: "gemini")
        let adapter = await selector.resolve(folder: folder)
        XCTAssertEqual(adapter.id, "gemini", "gemini 폴더가 Claude 로 잘못 라우팅되던 v0.9.6 회귀 가드")
    }

    func testClaudeFolderRoutesToClaudeAdapter() async {
        let selector = makeSelector(installedIDs: ["claude", "aider", "codex", "gemini"])
        let folder = makeFolder(adapterId: "claude")
        let adapter = await selector.resolve(folder: folder)
        XCTAssertEqual(adapter.id, "claude")
    }

    func testAiderFolderRoutesToAiderAdapter() async {
        let selector = makeSelector(installedIDs: ["claude", "aider", "codex", "gemini"])
        let folder = makeFolder(adapterId: "aider")
        let adapter = await selector.resolve(folder: folder)
        XCTAssertEqual(adapter.id, "aider")
    }

    // MARK: - 새 어댑터 추가가 자동 반영되는지

    /// allCandidateIDs() 가 selector 의 candidates 를 자동으로 사용 → 미래 어댑터 추가
    /// 시 별도 enabled 셋 업데이트 없이 라우팅됨.
    func testFutureAdapterRoutesAutomatically() async {
        // 미래에 "newvendor" 어댑터가 추가됐다고 가정
        let selector = makeSelector(installedIDs: ["claude", "codex", "newvendor"])
        let folder = makeFolder(adapterId: "newvendor")
        let adapter = await selector.resolve(folder: folder)
        XCTAssertEqual(
            adapter.id, "newvendor",
            "selector candidates 에 등록된 새 어댑터가 자동 라우팅되어야 함 (allCandidateIDs 자동 반영)"
        )
    }

    // MARK: - Edge: 미설치 어댑터 polder

    /// 폴더의 adapterId 가 미설치 → fallback 으로 폴백.
    func testFolderAdapterNotInstalledFallsBack() async {
        let selector = AdapterSelector(
            candidates: ["claude": StubAdapter(id: "claude", installed: true)],
            fallback: StubAdapter(id: "fallback", installed: true)
        )
        let folder = makeFolder(adapterId: "codex")  // codex 미등록
        let adapter = await selector.resolve(folder: folder)
        XCTAssertEqual(adapter.id, "claude", "preferred 가 candidates 에 없으면 enabled 의 첫 설치된 어댑터로 폴백")
    }
}
