import Foundation
import Observation

/// 한 폴더의 쉘 탭 식별자.
public struct ShellTabID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static func new() -> ShellTabID {
        ShellTabID(rawValue: UUID().uuidString)
    }
}

/// 한 쉘 탭의 메타데이터 + 출력 buffer + 세션.
///
/// `outputBuffer` 는 SwiftUI 가 폴링하는 단순 String — 라인 cap 으로 메모리 보호.
@MainActor
@Observable
public final class ShellTab: Identifiable {
    public let id: ShellTabID
    public var title: String
    public let cwd: URL?
    public private(set) var outputBuffer: String = ""
    public private(set) var hasExited: Bool = false
    public private(set) var exitCode: Int32?

    @ObservationIgnored
    public let session: ShellSession
    public let maxBufferChars: Int

    @ObservationIgnored
    private var consumeTask: Task<Void, Never>?

    public init(
        id: ShellTabID = .new(),
        title: String,
        cwd: URL?,
        session: ShellSession,
        maxBufferChars: Int = 256_000
    ) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.session = session
        self.maxBufferChars = max(1024, maxBufferChars)
    }

    public func startIfNeeded() async {
        guard consumeTask == nil else { return }
        do {
            try await session.start()
        } catch {
            append("[start failed: \(error)]\n")
            hasExited = true
            return
        }
        let stream = await session.events
        consumeTask = Task { [weak self] in
            for await event in stream {
                if Task.isCancelled { break }
                await self?.handle(event)
            }
        }
    }

    public func send(_ text: String) async {
        await session.send(Data(text.utf8))
    }

    public func resize(cols: Int, rows: Int) async {
        await session.resize(cols: cols, rows: rows)
    }

    public func terminate() async {
        consumeTask?.cancel()
        consumeTask = nil
        await session.terminate()
    }

    private func handle(_ event: ShellSessionEvent) {
        switch event {
        case .output(let data):
            if let text = String(data: data, encoding: .utf8) {
                append(text)
            } else {
                // non-UTF8 — replace 로 그래도 표시
                let text = String(decoding: data, as: UTF8.self)
                append(text)
            }
        case .exited(let code):
            hasExited = true
            exitCode = code
            append("\n[exited \(code)]\n")
        case .error(let message):
            append("\n[error: \(message)]\n")
        }
    }

    private func append(_ text: String) {
        outputBuffer.append(text)
        if outputBuffer.count > maxBufferChars {
            // 앞쪽 절반 잘라냄 (flicker 최소화)
            let removeCount = outputBuffer.count - (maxBufferChars / 2)
            let endIdx = outputBuffer.index(outputBuffer.startIndex, offsetBy: removeCount)
            outputBuffer.removeSubrange(outputBuffer.startIndex..<endIdx)
        }
    }
}

/// 한 폴더의 쉘 탭 목록 + active 관리.
@MainActor
@Observable
public final class ShellTabsViewModel {
    public private(set) var tabs: [ShellTab] = []
    public var activeTabID: ShellTabID?

    @ObservationIgnored
    public let sessionFactory: @MainActor @Sendable (URL?) -> ShellSession

    public init(
        sessionFactory: @escaping @MainActor @Sendable (URL?) -> ShellSession
    ) {
        self.sessionFactory = sessionFactory
    }

    public var activeTab: ShellTab? {
        guard let id = activeTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    @discardableResult
    public func openNewTab(cwd: URL?, title: String? = nil) async -> ShellTab {
        let session = sessionFactory(cwd)
        let resolvedTitle = title ?? cwd?.lastPathComponent ?? "셸"
        let tab = ShellTab(title: resolvedTitle, cwd: cwd, session: session)
        tabs.append(tab)
        activeTabID = tab.id
        await tab.startIfNeeded()
        return tab
    }

    public func closeTab(id: ShellTabID) async {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: idx)
        await tab.terminate()
        if activeTabID == id {
            activeTabID = tabs.first?.id
        }
    }

    public func selectTab(id: ShellTabID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
    }

    public func closeAll() async {
        let snapshot = tabs
        tabs.removeAll()
        activeTabID = nil
        for tab in snapshot {
            await tab.terminate()
        }
    }
}
