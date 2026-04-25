import Foundation

/// CLI 에이전트 내부에서 사용 가능한 **슬래시 명령** 메타데이터.
///
/// `AgentAdapter.listSlashCommands` 가 반환. UI 자동완성 / 검색에 사용.
/// `name` 은 선두 슬래시(`/`)를 포함하지 않는다.
///
/// - 카테고리는 옵션. 어댑터별로 `built-in` / `user-defined` / `skill` 등으로 그룹핑.
public struct SlashCommand: Codable, Hashable, Sendable, Identifiable {
    public let name: String
    public let description: String
    public let category: String?
    /// 인자 이름 힌트 (예: `["agent", "task"]`). UI 자동완성에서 placeholder 로 표시.
    /// nil 이면 인자 메타데이터 미제공. Phase 4 리뷰 must-fix — Phase 18 UI 가
    /// 명령 이름만이 아닌 인자까지 안내할 수 있도록 미리 확장.
    public let arguments: [String]?

    public var id: String { name }

    public init(
        name: String,
        description: String,
        category: String? = nil,
        arguments: [String]? = nil
    ) {
        self.name = name
        self.description = description
        self.category = category
        self.arguments = arguments
    }
}
