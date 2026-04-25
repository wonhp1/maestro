@testable import MaestroCore
import XCTest

final class EnvironmentSanitizerTests: XCTestCase {
    func testDefaultDenyListBlocksKnownTokens() {
        let s = EnvironmentSanitizer.default
        for key in [
            "CLAUDE_CODE_OAUTH_TOKEN",
            "ANTHROPIC_API_KEY",
            "OPENAI_API_KEY",
            "GITHUB_TOKEN",
            "GH_TOKEN",
            "NPM_TOKEN",
            "GOOGLE_APPLICATION_CREDENTIALS",
        ] {
            XCTAssertTrue(s.shouldDeny(key: key), "expected deny for \(key)")
        }
    }

    func testDefaultPrefixBlocksAWSFamily() {
        let s = EnvironmentSanitizer.default
        XCTAssertTrue(s.shouldDeny(key: "AWS_ACCESS_KEY_ID"))
        XCTAssertTrue(s.shouldDeny(key: "AWS_SECRET_ACCESS_KEY"))
        XCTAssertTrue(s.shouldDeny(key: "AWS_SESSION_TOKEN"))
        XCTAssertTrue(s.shouldDeny(key: "AWS_PROFILE"))
    }

    func testSystemKeysPreserved() {
        let s = EnvironmentSanitizer.default
        for key in ["PATH", "HOME", "USER", "LANG", "TMPDIR", "SHELL"] {
            XCTAssertFalse(s.shouldDeny(key: key), "should NOT deny \(key)")
        }
    }

    func testSanitizeRemovesMatchingKeys() {
        let s = EnvironmentSanitizer.default
        let env = [
            "PATH": "/usr/bin",
            "HOME": "/Users/x",
            "ANTHROPIC_API_KEY": "secret-1",
            "AWS_ACCESS_KEY_ID": "secret-2",
            "MY_OWN_VAR": "kept",
        ]
        let cleaned = s.sanitize(env)
        XCTAssertEqual(cleaned["PATH"], "/usr/bin")
        XCTAssertEqual(cleaned["HOME"], "/Users/x")
        XCTAssertEqual(cleaned["MY_OWN_VAR"], "kept")
        XCTAssertNil(cleaned["ANTHROPIC_API_KEY"])
        XCTAssertNil(cleaned["AWS_ACCESS_KEY_ID"])
    }

    func testCustomDenyListSupplements() {
        let s = EnvironmentSanitizer(
            denyKeys: ["CUSTOM_SECRET"],
            denyPrefixes: ["TEST_"]
        )
        XCTAssertTrue(s.shouldDeny(key: "CUSTOM_SECRET"))
        XCTAssertTrue(s.shouldDeny(key: "TEST_TOKEN"))
        XCTAssertTrue(s.shouldDeny(key: "TEST_"))
        XCTAssertFalse(s.shouldDeny(key: "OTHER_VAR"))
        // default deny list 와는 독립 — custom 만 적용.
        XCTAssertFalse(s.shouldDeny(key: "ANTHROPIC_API_KEY"))
    }

    /// Phase 6 must-fix: 모든 매칭은 대소문자 무시.
    func testMatchesAreCaseInsensitive() {
        let s = EnvironmentSanitizer.default
        XCTAssertTrue(s.shouldDeny(key: "anthropic_api_key"))
        XCTAssertTrue(s.shouldDeny(key: "AntHRopic_API_KEY"))
        XCTAssertTrue(s.shouldDeny(key: "aws_access_key_id"))
        // suffix 도 case-insensitive.
        XCTAssertTrue(s.shouldDeny(key: "my_service_TOKEN"))
        XCTAssertTrue(s.shouldDeny(key: "Service_Api_Key"))
    }

    /// Phase 6 must-fix: suffix 패턴으로 미지의 새 서비스 키 자동 차단.
    func testSuffixPatternsBlockNovelTokens() {
        let s = EnvironmentSanitizer.default
        XCTAssertTrue(s.shouldDeny(key: "FUTURE_SERVICE_API_KEY"))
        XCTAssertTrue(s.shouldDeny(key: "X_TOKEN"))
        XCTAssertTrue(s.shouldDeny(key: "SOMETHING_SECRET"))
        XCTAssertTrue(s.shouldDeny(key: "DB_PASSWORD"))
        XCTAssertTrue(s.shouldDeny(key: "API_AUTH"))
        // _BASE_URL / _PROXY 는 redirect 공격 벡터로 차단.
        XCTAssertTrue(s.shouldDeny(key: "ANTHROPIC_BASE_URL"))
        XCTAssertTrue(s.shouldDeny(key: "OPENAI_BASE_URL"))
        XCTAssertTrue(s.shouldDeny(key: "CUSTOM_PROXY"))
    }

    func testStrictAllowOnlySystemVars() {
        let s = EnvironmentSanitizer.strict
        XCTAssertFalse(s.shouldDeny(key: "PATH"))
        XCTAssertFalse(s.shouldDeny(key: "HOME"))
        XCTAssertFalse(s.shouldDeny(key: "TMPDIR"))
        // 사용자 변수는 모두 차단.
        XCTAssertTrue(s.shouldDeny(key: "MY_OWN_VAR"))
        XCTAssertTrue(s.shouldDeny(key: "ANTHROPIC_API_KEY"))
        XCTAssertTrue(s.shouldDeny(key: "VIRTUAL_ENV"))
    }

    func testSanitizedProcessEnvironmentIncludesPATH() {
        // 실행 환경에 PATH 는 항상 있고 보존돼야 함.
        let cleaned = EnvironmentSanitizer.default.sanitizedProcessEnvironment()
        XCTAssertNotNil(cleaned["PATH"], "PATH 는 보존돼야 자식이 PATH 검색 가능")
    }
}
