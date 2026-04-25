import Foundation
import XCTest

/// 테스트 전용 헬퍼 — MaestroCoreTests 의 TestSupport 와 동일한 패턴.
/// 두 타겟이 분리돼 있어 `internal` 가 공유 안 됨 → 각 타겟에 두기.
enum TestSupport {
    static func makeTempDirectory(named prefix: String = "maestro-adapters-test") throws -> URL {
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
