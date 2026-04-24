import Foundation
@testable import MaestroCore
import XCTest

/// 테스트 전용 헬퍼 — 매 테스트마다 unique temp 디렉토리 생성/정리.
enum TestSupport {
    static func makeTempDirectory(
        named prefix: String = "maestro-test",
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let dir = base.appending(
            path: "\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func removeTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
