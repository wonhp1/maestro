import Foundation
@testable import MaestroCore
import XCTest

@MainActor
final class InboxStoreTests: XCTestCase {
    private func makeEnvelope(
        id: EnvelopeID = .new(),
        body: String = "hello"
    ) -> MessageEnvelope {
        MessageEnvelope(
            id: id,
            threadId: ThreadID.new(),
            inReplyTo: nil,
            from: AgentID(rawValue: "alice"),
            to: AgentID(rawValue: "bob"),
            type: .task,
            body: body,
            createdAt: Date(),
            expectReply: true
        )
    }

    func testRecordIncrementsUnreadAndPrependsItem() {
        let store = InboxStore()
        let folder = FolderID.new()
        let env = makeEnvelope()
        store.record(envelope: env, folderID: folder)

        XCTAssertEqual(store.unreadCount(folderID: folder), 1)
        XCTAssertEqual(store.totalUnread, 1)
        XCTAssertEqual(store.items.first?.id, env.id)
    }

    func testRecordPreservesOrderNewestFirst() {
        let store = InboxStore()
        let folder = FolderID.new()
        let e1 = makeEnvelope()
        let e2 = makeEnvelope()
        store.record(envelope: e1, folderID: folder)
        store.record(envelope: e2, folderID: folder)
        XCTAssertEqual(store.items.map(\.id), [e2.id, e1.id])
    }

    func testRespectsMaxItemsCap() {
        let store = InboxStore(maxItems: 3)
        let folder = FolderID.new()
        for _ in 0..<5 {
            store.record(envelope: makeEnvelope(), folderID: folder)
        }
        XCTAssertEqual(store.items.count, 3)
    }

    func testMarkReadDecrementsUnread() {
        let store = InboxStore()
        let folder = FolderID.new()
        let env = makeEnvelope()
        store.record(envelope: env, folderID: folder)
        store.markRead(itemID: env.id)
        XCTAssertEqual(store.unreadCount(folderID: folder), 0)
        XCTAssertTrue(store.items[0].isRead)
    }

    func testMarkReadIsIdempotent() {
        let store = InboxStore()
        let folder = FolderID.new()
        let env = makeEnvelope()
        store.record(envelope: env, folderID: folder)
        store.markRead(itemID: env.id)
        store.markRead(itemID: env.id)  // 두 번째 호출은 unread count 변동 없어야 함
        XCTAssertEqual(store.unreadCount(folderID: folder), 0)
    }

    func testMarkAllReadResetsCount() {
        let store = InboxStore()
        let folder = FolderID.new()
        for _ in 0..<3 { store.record(envelope: makeEnvelope(), folderID: folder) }
        store.markAllRead(folderID: folder)
        XCTAssertEqual(store.unreadCount(folderID: folder), 0)
        XCTAssertTrue(store.items.allSatisfy { $0.isRead })
    }

    func testClearFolderRemovesItemsAndUnread() {
        let store = InboxStore()
        let folder1 = FolderID.new()
        let folder2 = FolderID.new()
        store.record(envelope: makeEnvelope(), folderID: folder1)
        store.record(envelope: makeEnvelope(), folderID: folder2)
        store.clear(folderID: folder1)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.unreadCount(folderID: folder1), 0)
        XCTAssertEqual(store.unreadCount(folderID: folder2), 1)
    }

    func testPreviewSanitizesBidiAndZeroWidth() {
        // bidi override + ZW joiner — Trojan Source 방어 (must-fix SEC-1).
        let store = InboxStore()
        let folder = FolderID.new()
        let body = "warn\u{202E}exe\u{200B}rm -rf /"
        store.record(envelope: makeEnvelope(body: body), folderID: folder)
        let preview = store.items[0].preview
        XCTAssertFalse(preview.unicodeScalars.contains(Unicode.Scalar(0x202E)!))
        XCTAssertFalse(preview.unicodeScalars.contains(Unicode.Scalar(0x200B)!))
    }

    func testPreviewTruncatesLongBody() {
        let store = InboxStore()
        let folder = FolderID.new()
        let body = String(repeating: "A", count: 300)
        store.record(envelope: makeEnvelope(body: body), folderID: folder)
        let preview = store.items[0].preview
        XCTAssertTrue(preview.hasSuffix("…"))
        XCTAssertLessThanOrEqual(preview.count, 121)
    }
}
