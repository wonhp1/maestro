@testable import MaestroCore
import XCTest

/// Phase 2 / Test 2.3 — AgentProfile 은 CLI 어댑터의 "감지/실행/버전 확인" 프로파일.
///
/// 실제 어댑터 구현(P4+)의 파라미터화된 구성 요소. 프로파일 자체는 순수 데이터.
final class AgentProfileTests: XCTestCase {
    private func claudeProfile() -> AgentProfile {
        AgentProfile(
            adapterId: "claude",
            displayName: "Claude Code",
            detectCommand: "claude --version",
            versionRegex: #"^(\d+\.\d+\.\d+)"#,
            invokeTemplate: "claude -p {prompt} --resume {session}"
        )
    }

    func testInitPopulatesFields() {
        let p = claudeProfile()
        XCTAssertEqual(p.adapterId, "claude")
        XCTAssertEqual(p.displayName, "Claude Code")
        XCTAssertTrue(p.detectCommand.contains("--version"))
        XCTAssertTrue(p.invokeTemplate.contains("{prompt}"))
    }

    func testEqualityBasedOnAdapterId() {
        let claudeA = claudeProfile()
        let claudeB = AgentProfile(
            adapterId: "claude",
            displayName: "Claude Code (변경된 표시)",
            detectCommand: "claude --version",
            versionRegex: #"^(\d+\.\d+\.\d+)"#,
            invokeTemplate: "claude -p {prompt} --resume {session}"
        )
        // 동일 adapterId 는 같은 프로파일로 간주하지 않음 — struct 전체 동등성.
        XCTAssertNotEqual(claudeA, claudeB)
    }

    func testHashable() {
        let p = claudeProfile()
        var set: Set<AgentProfile> = []
        set.insert(p)
        set.insert(p)
        XCTAssertEqual(set.count, 1)
    }

    func testCodableRoundtrip() throws {
        let original = claudeProfile()
        let data = try JSONEncoder.maestro.encode(original)
        let decoded = try JSONDecoder.maestro.decode(AgentProfile.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testInvokeTemplateSubstitution() {
        let p = claudeProfile()
        let cmd = p.renderInvokeCommand(substitutions: [
            "prompt": "안녕",
            "session": "abc-123",
        ])
        XCTAssertEqual(cmd, "claude -p 안녕 --resume abc-123")
    }

    func testInvokeTemplateFailsOnMissingSubstitution() {
        let p = claudeProfile()
        XCTAssertThrowsError(try p.strictInvokeCommand(substitutions: ["prompt": "x"])) { err in
            guard case AgentProfileError.unresolvedPlaceholder(let name) = err else {
                return XCTFail("예상과 다른 에러: \(err)")
            }
            XCTAssertEqual(name, "session")
        }
    }
}
