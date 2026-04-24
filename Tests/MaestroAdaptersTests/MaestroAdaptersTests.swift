import XCTest
@testable import MaestroAdapters

final class MaestroAdaptersPlaceholderTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(MaestroAdapters.moduleName, "MaestroAdapters")
    }
}
