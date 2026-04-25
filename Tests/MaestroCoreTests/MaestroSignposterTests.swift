@testable import MaestroCore
import XCTest

final class MaestroSignposterTests: XCTestCase {
    func testMakeSignpostIDIsNonZero() {
        let sp = MaestroSignposter(category: .general)
        let id = sp.makeSignpostID()
        // OSSignpostID 0 은 .invalid — non-invalid 보장.
        XCTAssertNotEqual(id, .invalid)
    }

    func testManualBeginEndDoesNotCrash() {
        let sp = MaestroSignposter(category: .adapter)
        let id = sp.makeSignpostID()
        let state = sp.begin("test-interval", id: id)
        sp.end("test-interval", state)
    }

    func testEventEmits() {
        let sp = MaestroSignposter(category: .ui)
        sp.event("test-event")
    }

    func testAsyncIntervalScopeReturnsValue() async throws {
        let sp = MaestroSignposter(category: .orchestration)
        let result = await sp.interval("compute") {
            try? await Task.sleep(nanoseconds: 1_000_000)
            return 42
        }
        XCTAssertEqual(result, 42)
    }

    func testSyncIntervalScopeReturnsValue() throws {
        let sp = MaestroSignposter(category: .orchestration)
        let result = sp.interval("hash") {
            (1...100).reduce(0, +)
        }
        XCTAssertEqual(result, 5050)
    }

    func testAsyncIntervalPropagatesError() async {
        struct Boom: Error {}
        let sp = MaestroSignposter(category: .general)
        do {
            _ = try await sp.interval("boom") {
                throw Boom()
            }
            XCTFail("expected throw")
        } catch is Boom {
            // OK
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testCustomSubsystem() {
        let sp = MaestroSignposter(category: .process, subsystem: "test.subsystem")
        XCTAssertEqual(sp.subsystem, "test.subsystem")
        XCTAssertEqual(sp.category, .process)
    }

    /// Phase 5 must-fix: 중첩 인터벌이 충돌 없이 동작 (각 호출 fresh signpostID).
    func testNestedIntervalsReturnInnerValue() async {
        let outer = MaestroSignposter(category: .orchestration)
        let inner = MaestroSignposter(category: .adapter)
        let result = await outer.interval("outer") {
            await inner.interval("inner") {
                42
            }
        }
        XCTAssertEqual(result, 42)
    }
}
