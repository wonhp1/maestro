@testable import MaestroCore
import XCTest

@MainActor
final class ShellTabsViewModelTests: XCTestCase {
    private actor StubSession: ShellSession {
        var sent: [Data] = []
        var resized: (Int, Int)?
        var started: Bool = false
        var terminated: Bool = false
        private var continuation: AsyncStream<ShellSessionEvent>.Continuation?
        private var stream: AsyncStream<ShellSessionEvent>?

        var events: AsyncStream<ShellSessionEvent> {
            get async {
                if let stream { return stream }
                let s = AsyncStream<ShellSessionEvent> { c in
                    self.continuation = c
                }
                self.stream = s
                return s
            }
        }

        func start() async throws {
            started = true
            _ = await events
        }

        func send(_ data: Data) async {
            sent.append(data)
        }

        func resize(cols: Int, rows: Int) async {
            resized = (cols, rows)
        }

        func terminate() async {
            terminated = true
            continuation?.finish()
        }

        func emit(_ event: ShellSessionEvent) {
            continuation?.yield(event)
        }
    }

    private func makeModel() -> (ShellTabsViewModel, [StubSession]) {
        let sessionsBox = SessionsBox()
        let viewModel = ShellTabsViewModel { _ in
            let s = StubSession()
            sessionsBox.append(s)
            return s
        }
        return (viewModel, sessionsBox.snapshot)
    }

    private final class SessionsBox: @unchecked Sendable {
        private(set) var snapshot: [StubSession] = []
        func append(_ s: StubSession) { snapshot.append(s) }
    }

    func testOpenNewTabAppendsAndActivates() async {
        let (viewModel, _) = makeModel()
        let tab = await viewModel.openNewTab(cwd: nil, title: "alpha")
        XCTAssertEqual(viewModel.tabs.count, 1)
        XCTAssertEqual(viewModel.activeTabID, tab.id)
        XCTAssertEqual(viewModel.activeTab?.title, "alpha")
    }

    func testCloseTabRemovesAndShiftsActive() async {
        let (viewModel, _) = makeModel()
        let a = await viewModel.openNewTab(cwd: nil, title: "a")
        let b = await viewModel.openNewTab(cwd: nil, title: "b")
        await viewModel.closeTab(id: b.id)
        XCTAssertEqual(viewModel.tabs.map(\.id), [a.id])
        XCTAssertEqual(viewModel.activeTabID, a.id)
    }

    func testCloseLastTabClearsActive() async {
        let (viewModel, _) = makeModel()
        let tab = await viewModel.openNewTab(cwd: nil)
        await viewModel.closeTab(id: tab.id)
        XCTAssertTrue(viewModel.tabs.isEmpty)
        XCTAssertNil(viewModel.activeTabID)
    }

    func testSelectTabRequiresExistence() async {
        let (viewModel, _) = makeModel()
        let a = await viewModel.openNewTab(cwd: nil)
        viewModel.selectTab(id: ShellTabID(rawValue: "missing"))
        XCTAssertEqual(viewModel.activeTabID, a.id, "없는 id 는 무시")
    }

    func testCloseAllTerminatesAll() async {
        let (viewModel, _) = makeModel()
        _ = await viewModel.openNewTab(cwd: nil)
        _ = await viewModel.openNewTab(cwd: nil)
        await viewModel.closeAll()
        XCTAssertTrue(viewModel.tabs.isEmpty)
        XCTAssertNil(viewModel.activeTabID)
    }
}

@MainActor
final class ShellTabTests: XCTestCase {
    private actor StubSession: ShellSession {
        var started: Bool = false
        var sent: [Data] = []
        var terminated: Bool = false
        private var continuation: AsyncStream<ShellSessionEvent>.Continuation?
        private var stream: AsyncStream<ShellSessionEvent>?

        var events: AsyncStream<ShellSessionEvent> {
            get async {
                if let stream { return stream }
                let s = AsyncStream<ShellSessionEvent> { c in
                    self.continuation = c
                }
                self.stream = s
                return s
            }
        }
        func start() async throws { started = true; _ = await events }
        func send(_ data: Data) async { sent.append(data) }
        func resize(cols: Int, rows: Int) async {}
        func terminate() async { terminated = true; continuation?.finish() }
        func emit(_ event: ShellSessionEvent) { continuation?.yield(event) }
    }

    func testStartTriggersSession() async {
        let session = StubSession()
        let tab = ShellTab(title: "x", cwd: nil, session: session)
        await tab.startIfNeeded()
        let started = await session.started
        XCTAssertTrue(started)
    }

    func testOutputAppendsToBuffer() async throws {
        let session = StubSession()
        let tab = ShellTab(title: "x", cwd: nil, session: session)
        await tab.startIfNeeded()
        await session.emit(.output(Data("hi\n".utf8)))
        // yield 대기
        for _ in 0..<10 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
            if !tab.outputBuffer.isEmpty { break }
        }
        XCTAssertTrue(tab.outputBuffer.contains("hi"))
    }

    func testExitMarksHasExited() async throws {
        let session = StubSession()
        let tab = ShellTab(title: "x", cwd: nil, session: session)
        await tab.startIfNeeded()
        await session.emit(.exited(code: 0))
        for _ in 0..<10 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
            if tab.hasExited { break }
        }
        XCTAssertTrue(tab.hasExited)
        XCTAssertEqual(tab.exitCode, 0)
    }

    func testBufferRespectsCap() async throws {
        let session = StubSession()
        let tab = ShellTab(title: "x", cwd: nil, session: session, maxBufferChars: 4096)
        await tab.startIfNeeded()
        let big = Data(String(repeating: "a", count: 8192).utf8)
        await session.emit(.output(big))
        for _ in 0..<10 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
            if tab.outputBuffer.count <= 4096 { break }
        }
        XCTAssertLessThanOrEqual(tab.outputBuffer.count, 4096)
    }
}
