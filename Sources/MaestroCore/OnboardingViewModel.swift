import Foundation
import Observation

/// 첫 실행 온보딩 마법사의 step state.
public enum OnboardingStep: Int, Sendable, CaseIterable {
    case welcome
    case detectAgents
    case firstFolder

    public var title: String {
        switch self {
        case .welcome: return "Maestro 에 오신 걸 환영합니다"
        case .detectAgents: return "에이전트 감지"
        case .firstFolder: return "첫 폴더 추가"
        }
    }
}

/// 온보딩 마법사 driving state.
///
/// 각 step 완료 → `advance()` 가 다음 step. 마지막 step 완료 → `complete()` 가
/// `PreferencesStore.firstRunCompleted = true` 설정 + `onComplete` 콜백.
///
/// ## 동시성
/// `@MainActor @Observable` — SwiftUI binding.
@MainActor
@Observable
public final class OnboardingViewModel {
    public private(set) var currentStep: OnboardingStep = .welcome
    public private(set) var detectedAdapters: [String] = []
    public var hasAddedFirstFolder: Bool = false
    public private(set) var isCompleted: Bool = false

    @ObservationIgnored
    private let preferences: PreferencesStore
    @ObservationIgnored
    public var onComplete: (@MainActor @Sendable () -> Void)?

    public init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    public func setDetectedAdapters(_ ids: [String]) {
        detectedAdapters = ids
    }

    /// step 완료 → 다음으로. 마지막에서 advance() 호출하면 complete().
    public func advance() {
        guard !isCompleted else { return }
        let raw = currentStep.rawValue + 1
        if let next = OnboardingStep(rawValue: raw) {
            currentStep = next
        } else {
            complete()
        }
    }

    /// 이전 step 으로 (welcome 에서는 no-op).
    public func goBack() {
        guard !isCompleted else { return }
        let raw = currentStep.rawValue - 1
        if let prev = OnboardingStep(rawValue: raw) {
            currentStep = prev
        }
    }

    /// 사용자가 "건너뛰기" — 모든 단계 통과 처리.
    public func skip() {
        complete()
    }

    public func complete() {
        guard !isCompleted else { return }
        isCompleted = true
        preferences.setFirstRunCompleted(true)
        onComplete?()
    }
}
