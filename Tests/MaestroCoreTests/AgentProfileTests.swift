@testable import MaestroCore
import XCTest

/// Phase 2 / Test 2.3 — AgentProfile 의 argv 기반 실행 모델.
///
/// 핵심 계약: `invokeArgs: [InvokeArg]` 는 shell 을 거치지 않고 `Process.arguments`
/// 에 직접 전달되므로 **임의 문자열이 인자에 들어가도 인젝션 불가**.
final class AgentProfileTests: XCTestCase {
    private func claudeProfile() -> AgentProfile {
        AgentProfile(
            adapterId: AdapterID(rawValue: "claude"),
            displayName: "Claude Code",
            executable: "claude",
            detectArgs: ["--version"],
            versionRegex: #"^(\d+\.\d+\.\d+)"#,
            invokeArgs: [
                .literal("-p"),
                .placeholder("prompt"),
                .literal("--resume"),
                .placeholder("session"),
                .literal("--output-format"),
                .literal("json"),
            ]
        )
    }

    func testInitPopulatesFields() {
        let p = claudeProfile()
        XCTAssertEqual(p.adapterId.rawValue, "claude")
        XCTAssertEqual(p.displayName, "Claude Code")
        XCTAssertEqual(p.executable, "claude")
        XCTAssertEqual(p.detectArgs, ["--version"])
    }

    func testPlaceholderNamesOrderedAndDeduped() {
        let p = claudeProfile()
        XCTAssertEqual(p.placeholderNames, ["prompt", "session"])

        // 중복/역순 케이스
        let weird = AgentProfile(
            adapterId: AdapterID(rawValue: "x"),
            displayName: "x",
            executable: "x",
            detectArgs: [],
            versionRegex: "",
            invokeArgs: [.placeholder("b"), .placeholder("a"), .placeholder("b")]
        )
        XCTAssertEqual(weird.placeholderNames, ["b", "a"])
    }

    func testRenderArgvSubstitutesAndPreservesOrder() throws {
        let p = claudeProfile()
        let argv = try p.renderArgv(substitutions: [
            "prompt": "안녕 🎼",
            "session": "abc-123",
        ])
        XCTAssertEqual(argv, [
            "-p", "안녕 🎼",
            "--resume", "abc-123",
            "--output-format", "json",
        ])
    }

    func testRenderArgvDoesNotShellEscapeDangerousInput() throws {
        // 핵심 보안 속성: 인자 내용은 그대로 argv 에 전달. Process 가 shell 파싱 안 함.
        let p = claudeProfile()
        let argv = try p.renderArgv(substitutions: [
            "prompt": "; rm -rf / #",
            "session": "$(whoami)",
        ])
        // 원본 문자열이 그대로 포함 — shell 이 해석하지 않으므로 안전.
        XCTAssertTrue(argv.contains("; rm -rf / #"))
        XCTAssertTrue(argv.contains("$(whoami)"))
    }

    func testRenderArgvThrowsForMissingPlaceholder() {
        let p = claudeProfile()
        XCTAssertThrowsError(try p.renderArgv(substitutions: ["prompt": "x"])) { err in
            XCTAssertEqual(err as? AgentProfileError, .unresolvedPlaceholder(name: "session"))
        }
    }

    func testDisplayCommandIncludesExecutableAndPlaceholderHints() {
        let p = claudeProfile()
        let cmd = p.displayCommand()
        XCTAssertTrue(cmd.hasPrefix("claude "))
        XCTAssertTrue(cmd.contains("{prompt}"))
        XCTAssertTrue(cmd.contains("{session}"))
    }

    func testDisplayCommandWithPartialSubstitutions() {
        let p = claudeProfile()
        let cmd = p.displayCommand(substitutions: ["prompt": "hi"])
        XCTAssertTrue(cmd.contains(" hi "))
        XCTAssertTrue(cmd.contains("{session}"))
    }

    // MARK: Codable

    func testCodableRoundtrip() throws {
        let original = claudeProfile()
        let data = try JSONEncoder.maestro.encode(original)
        let decoded = try JSONDecoder.maestro.decode(AgentProfile.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testInvokeArgCodable() throws {
        let values: [InvokeArg] = [.literal("-p"), .placeholder("prompt")]
        let data = try JSONEncoder.maestro.encode(values)
        let decoded = try JSONDecoder.maestro.decode([InvokeArg].self, from: data)
        XCTAssertEqual(decoded, values)
    }

    // MARK: Equality — 전체 필드 비교 (이름과 내용이 일치하도록 변경)

    func testEqualityRequiresAllFieldsMatch() {
        let a = claudeProfile()
        var invokeArgs = a.invokeArgs
        invokeArgs.append(.literal("--extra"))
        let b = AgentProfile(
            adapterId: a.adapterId,
            displayName: a.displayName,
            executable: a.executable,
            detectArgs: a.detectArgs,
            versionRegex: a.versionRegex,
            invokeArgs: invokeArgs
        )
        XCTAssertNotEqual(a, b)
    }
}
