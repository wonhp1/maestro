import Foundation

/// 폴더 선택 다이얼로그 추상화 — UI 패널을 띄우지 않고 테스트 가능하도록 분리.
///
/// ## 구현체
/// - `NSOpenPanelFolderPicker` (Sources/Maestro): NSOpenPanel 래퍼. 실제 앱 사용.
/// - 테스트: 인라인 stub 으로 `presentPicker(suggested:)` 가 미리 정해진 URL 또는
///   `nil` (취소) 을 반환하도록 구성.
///
/// ## 사용 패턴
/// ```swift
/// let url = try await picker.presentPicker(suggested: nil)
/// guard let url else { return }  // 사용자 취소
/// try await registry.add(displayName: url.lastPathComponent, path: url, adapterId: ...)
/// ```
///
/// ## 보안
/// 사용자가 명시적으로 선택한 경로만 반환 — deep link / 외부 URL 로 등록 금지.
/// macOS 14+ 의 sandboxing 미적용 빌드에서는 모든 경로 접근 가능. Phase 21 의
/// app sandbox 적용 시 security-scoped bookmark 가 필요해질 수 있음 — 그때 다시 검토.
public protocol FolderPicking: Sendable {
    /// 폴더 선택 다이얼로그를 표시. 사용자 취소 시 nil.
    /// - Parameter suggested: 초기 진입 디렉토리 (선택). nil 이면 OS 기본.
    func presentPicker(suggested: URL?) async throws -> URL?
}

/// 테스트용 스텁 picker — 미리 정해진 결과 반환.
///
/// XCTest 에서 ViewModel 의 폴더 추가 플로우 검증 시 사용.
public actor StubFolderPicker: FolderPicking {
    private var pendingResults: [URL?]
    private(set) var receivedSuggestions: [URL?] = []

    public init(results: [URL?]) {
        self.pendingResults = results
    }

    public func presentPicker(suggested: URL?) async throws -> URL? {
        receivedSuggestions.append(suggested)
        guard !pendingResults.isEmpty else {
            throw StubFolderPickerError.noMoreResults
        }
        return pendingResults.removeFirst()
    }
}

public enum StubFolderPickerError: Error, Equatable, Sendable {
    case noMoreResults
}
