import Foundation

/// 실행 파일을 PATH 또는 명시된 디렉토리들에서 찾는 추상화.
///
/// 테스트는 `StubExecutableLocator` (in-memory 매핑) 으로 교체하여 실제 PATH 영향 제거.
public protocol ExecutableLocating: Sendable {
    /// 실행 파일 이름 (예: `claude`) → 절대 경로 또는 nil.
    func locate(_ executableName: String) -> URL?
}

/// 환경변수 `PATH` 를 콜론으로 분할해 순서대로 검사하는 기본 구현.
///
/// - 후보 파일이 일반 파일이고 실행 가능 비트가 켜진 경우만 매칭.
/// - 첫 매치 우선 (PATH 순서). 없으면 nil.
/// - 절대/상대 경로 (슬래시 포함) 입력은 그대로 검증.
public struct PATHExecutableLocator: ExecutableLocating {
    public let pathOverride: String?

    public init(pathOverride: String? = nil) {
        self.pathOverride = pathOverride
    }

    public func locate(_ executableName: String) -> URL? {
        guard !executableName.isEmpty else { return nil }

        // 슬래시 포함 — 경로로 직접 처리.
        if executableName.contains("/") {
            let url = URL(fileURLWithPath: executableName)
            return Self.isExecutableRegularFile(at: url) ? url : nil
        }

        let pathString = pathOverride ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        for component in pathString.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = URL(fileURLWithPath: String(component))
                .appending(path: executableName)
            if Self.isExecutableRegularFile(at: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func isExecutableRegularFile(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return false
        }
        return fm.isExecutableFile(atPath: url.path)
    }
}
