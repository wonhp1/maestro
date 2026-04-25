@testable import MaestroCore
import XCTest

final class MaestroLoggerTests: XCTestCase {
    func testDefaultSubsystemMatchesBundleIdentifier() {
        let log = MaestroLogger(category: .general)
        XCTAssertEqual(log.subsystem, MaestroConfig.bundleIdentifier)
        XCTAssertEqual(log.category, .general)
    }

    func testCustomSubsystem() {
        let log = MaestroLogger(category: .adapter, subsystem: "test.subsystem")
        XCTAssertEqual(log.subsystem, "test.subsystem")
        XCTAssertEqual(log.category, .adapter)
    }

    /// OSLog 자체 출력은 검증 불가 (system log 후크 권한 문제). 호출이 throws/crash 하지 않으면 OK.
    func testAllLogLevelsCallable() {
        let log = MaestroLogger(category: .persistence)
        log.debug("debug msg")
        log.info("info msg")
        log.notice("notice msg")
        log.warning("warning msg")
        log.error("error msg")
        log.fault("fault msg")
        log.publicInfo("public info — static string")
    }

    func testLoggerIsSendableAcrossTasks() async {
        let log = MaestroLogger(category: .orchestration)
        await withTaskGroup(of: Void.self) { group in
            for idx in 0..<10 {
                group.addTask {
                    log.info("concurrent \(idx)")
                }
            }
        }
    }
}
