import Foundation
import Observation

/// 컨트롤 타워의 InboxPanel — 받은 메시지 모음 + 폴더별 unread 카운트.
///
/// ## 책임
/// - 들어온 봉투 (EnvelopeRouter 가 push) 누적
/// - 폴더 별 unread 카운트 — 사이드바 뱃지 driving
/// - 읽음 처리 / 삭제
///
/// ## 향후 (Phase 13)
/// `EnvelopeRouter` 가 outbox write 시 이 store 의 `record(envelope:)` 호출.
/// 사용자가 InboxPanel 의 항목을 클릭 → `markRead`.
///
/// ## 메모리
/// `maxItems` 캡 (기본 200) — 오래된 항목 자동 trim. UI 가 무한 스크롤 안 함.
@MainActor
@Observable
public final class InboxStore {
    public private(set) var items: [InboxItem] = []
    public private(set) var unreadCountsByFolder: [FolderID: Int] = [:]
    private let maxItems: Int

    public init(maxItems: Int = 200) {
        self.maxItems = max(1, maxItems)
    }

    /// 새 봉투 도착 — folderID 는 라우터가 from/to 로부터 매핑한 결과.
    public func record(envelope: MessageEnvelope, folderID: FolderID, receivedAt: Date = Date()) {
        let item = InboxItem(
            id: envelope.id,
            folderID: folderID,
            from: envelope.from,
            to: envelope.to,
            type: envelope.type,
            preview: previewBody(envelope.body),
            receivedAt: receivedAt,
            isRead: false
        )
        items.insert(item, at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        unreadCountsByFolder[folderID, default: 0] += 1
    }

    public func markRead(itemID: EnvelopeID) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        guard !items[idx].isRead else { return }
        items[idx].isRead = true
        let folderID = items[idx].folderID
        if let current = unreadCountsByFolder[folderID], current > 0 {
            unreadCountsByFolder[folderID] = current - 1
        }
    }

    public func markAllRead(folderID: FolderID) {
        for idx in items.indices where items[idx].folderID == folderID {
            items[idx].isRead = true
        }
        unreadCountsByFolder[folderID] = 0
    }

    public func clear(folderID: FolderID) {
        items.removeAll { $0.folderID == folderID }
        unreadCountsByFolder[folderID] = nil
    }

    public func clearAll() {
        items.removeAll()
        unreadCountsByFolder.removeAll()
    }

    public func unreadCount(folderID: FolderID) -> Int {
        unreadCountsByFolder[folderID] ?? 0
    }

    public var totalUnread: Int {
        unreadCountsByFolder.values.reduce(0, +)
    }

    private func previewBody(_ body: String) -> String {
        // bidi/ZW/control 제거 — Trojan Source 방어 (must-fix).
        let sanitized = DisplayTextSanitizer.sanitize(body)
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 120 { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 120)
        return String(trimmed[..<endIndex]) + "…"
    }
}

/// InboxPanel 의 한 행.
public struct InboxItem: Sendable, Identifiable, Hashable {
    public let id: EnvelopeID
    public let folderID: FolderID
    public let from: AgentID
    public let to: AgentID
    public let type: MessageType
    public let preview: String
    public let receivedAt: Date
    public var isRead: Bool

    public init(
        id: EnvelopeID,
        folderID: FolderID,
        from: AgentID,
        to: AgentID,
        type: MessageType,
        preview: String,
        receivedAt: Date,
        isRead: Bool
    ) {
        self.id = id
        self.folderID = folderID
        self.from = from
        self.to = to
        self.type = type
        self.preview = preview
        self.receivedAt = receivedAt
        self.isRead = isRead
    }
}
