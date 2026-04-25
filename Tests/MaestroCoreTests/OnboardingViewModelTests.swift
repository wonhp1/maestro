@testable import MaestroCore
import XCTest

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private var tempRoot: URL!
    private var preferences: PreferencesStore!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "OnboardingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let path = tempRoot.appending(path: "preferences.json", directoryHint: .notDirectory)
        preferences = PreferencesStore(path: path, autosaveDebounceNanos: 0)
        await preferences.bootstrap()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testStartsAtWelcome() {
        let vm = OnboardingViewModel(preferences: preferences)
        XCTAssertEqual(vm.currentStep, .welcome)
        XCTAssertFalse(vm.isCompleted)
    }

    func testAdvanceCyclesAllSteps() {
        let vm = OnboardingViewModel(preferences: preferences)
        vm.advance()
        XCTAssertEqual(vm.currentStep, .detectAgents)
        vm.advance()
        XCTAssertEqual(vm.currentStep, .firstFolder)
        vm.advance()
        // 마지막 단계에서 advance → complete
        XCTAssertTrue(vm.isCompleted)
        XCTAssertTrue(preferences.snapshot.firstRunCompleted)
    }

    func testGoBackHonorsBoundary() {
        let vm = OnboardingViewModel(preferences: preferences)
        vm.goBack()
        XCTAssertEqual(vm.currentStep, .welcome, "welcome 에서 이전 — no-op")
        vm.advance()
        vm.goBack()
        XCTAssertEqual(vm.currentStep, .welcome)
    }

    func testSkipCompletesImmediately() {
        let vm = OnboardingViewModel(preferences: preferences)
        vm.skip()
        XCTAssertTrue(vm.isCompleted)
        XCTAssertTrue(preferences.snapshot.firstRunCompleted)
    }

    func testCompleteIsIdempotent() {
        let vm = OnboardingViewModel(preferences: preferences)
        vm.complete()
        let firstFlag = vm.isCompleted
        vm.complete()
        // Phase 19: callback fires only once
        XCTAssertTrue(firstFlag)
    }

    func testOnCompleteCallbackFires() async {
        let vm = OnboardingViewModel(preferences: preferences)
        var fired = false
        vm.onComplete = { fired = true }
        vm.skip()
        XCTAssertTrue(fired)
    }

    func testDetectedAdaptersStored() {
        let vm = OnboardingViewModel(preferences: preferences)
        vm.setDetectedAdapters(["claude", "aider"])
        XCTAssertEqual(vm.detectedAdapters, ["claude", "aider"])
    }
}
