@testable import MaestroCore
import XCTest

final class UpdateCheckerTests: XCTestCase {
    private actor StubFetcher: AppCastFetching {
        var data: Data
        var fetchCount: Int = 0
        var error: (any Error)?

        init(data: Data, error: (any Error)? = nil) {
            self.data = data
            self.error = error
        }

        func fetch(_ url: URL) async throws -> Data {
            fetchCount += 1
            if let error { throw error }
            return data
        }
    }

    private func appCast(versions: [(String, sig: String?)]) -> Data {
        let items = versions.map { v, sig in
            let sigAttr = sig.map { "sparkle:edSignature=\"\($0)\"" } ?? ""
            return """
              <item><sparkle:version>\(v)</sparkle:version>
                <enclosure url="https://example.com/\(v).dmg" \(sigAttr)/>
              </item>
            """
        }.joined(separator: "\n")
        let xml = """
        <rss xmlns:sparkle="x"><channel>
        \(items)
        </channel></rss>
        """
        return Data(xml.utf8)
    }

    func testReturnsAvailableWhenNewer() async throws {
        let fetcher = StubFetcher(data: appCast(versions: [("1.2.0", "SIG=="), ("1.1.0", "OLD==")]))
        let checker = UpdateChecker(
            appCastURL: URL(string: "https://example.com/appcast.xml")!,
            currentVersion: AppVersion(major: 1, minor: 0, patch: 0),
            fetcher: fetcher
        )
        let result = try await checker.check()
        if case let .available(item) = result {
            XCTAssertEqual(item.version, AppVersion(major: 1, minor: 2, patch: 0))
        } else {
            XCTFail("expected .available, got \(result)")
        }
    }

    func testReturnsUpToDateWhenAllOlder() async throws {
        let fetcher = StubFetcher(data: appCast(versions: [("0.5.0", "X==")]))
        let checker = UpdateChecker(
            appCastURL: URL(string: "https://example.com/x.xml")!,
            currentVersion: AppVersion(major: 1, minor: 0, patch: 0),
            fetcher: fetcher
        )
        let result = try await checker.check()
        XCTAssertEqual(result, .upToDate)
    }

    func testReturnsUnsignedWhenSignatureMissing() async throws {
        let fetcher = StubFetcher(data: appCast(versions: [("2.0.0", nil)]))
        let checker = UpdateChecker(
            appCastURL: URL(string: "https://example.com/x.xml")!,
            currentVersion: AppVersion(major: 1, minor: 0, patch: 0),
            fetcher: fetcher
        )
        let result = try await checker.check()
        if case .unsignedAvailable = result {
            // ok
        } else {
            XCTFail("expected .unsignedAvailable, got \(result)")
        }
    }

    func testRequireSignatureFalseAcceptsUnsigned() async throws {
        let fetcher = StubFetcher(data: appCast(versions: [("2.0.0", nil)]))
        let checker = UpdateChecker(
            appCastURL: URL(string: "https://example.com/x.xml")!,
            currentVersion: AppVersion(major: 1, minor: 0, patch: 0),
            fetcher: fetcher,
            requireSignature: false
        )
        let result = try await checker.check()
        if case .available = result { /* ok */ } else { XCTFail("expected .available") }
    }

    func testThrowsOnEmptyAppCast() async {
        let fetcher = StubFetcher(data: Data("<rss/>".utf8))
        let checker = UpdateChecker(
            appCastURL: URL(string: "https://example.com/x.xml")!,
            currentVersion: AppVersion(major: 1, minor: 0, patch: 0),
            fetcher: fetcher
        )
        do {
            _ = try await checker.check()
            XCTFail("should throw")
        } catch UpdateCheckerError.malformedAppCast {
            // ok
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testFetcherErrorPropagates() async {
        struct Boom: Error {}
        let fetcher = StubFetcher(data: Data(), error: Boom())
        let checker = UpdateChecker(
            appCastURL: URL(string: "https://example.com/x.xml")!,
            currentVersion: AppVersion(major: 1, minor: 0, patch: 0),
            fetcher: fetcher
        )
        do {
            _ = try await checker.check()
            XCTFail("should throw")
        } catch is Boom {
            // ok
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testInsecureURLRejected() async {
        let fetcher = URLSessionAppCastFetcher()
        do {
            _ = try await fetcher.fetch(URL(string: "http://example.com/cast.xml")!)
            XCTFail("http URL should throw")
        } catch UpdateCheckerError.insecureURL {
            // ok
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
