import Foundation
import Observation

/// 컨트롤 타워 상단 status bar 의 driving 데이터 — 현재 진행 중인 dispatch 들을 표시.
///
/// ## UI 모델
/// 각 항목은 "● <from> → <to> (state)" 표시. state 는 .running / .completed / .failed.
/// 자동 만료: completed/failed 는 3초 후 list 에서 제거 (UI flicker 방지).
///
/// ## 향후 (Phase 13)
/// `DispatchService` 가 dispatch lifecycle 을 push:
/// - dispatch 시작 → `record(start:)`
/// - 응답 수신 → `record(completion:)`
/// - 실패 → `record(failure:)`
@MainActor
@Observable
public final class OrchestrationStatusModel {
    public private(set) var entries: [OrchestrationEntry] = []
    private let autoExpire: TimeInterval
    @ObservationIgnored
    private var expiryTasks: [EnvelopeID: Task<Void, Never>] = [:]

    public init(autoExpire: TimeInterval = 3.0) {
        self.autoExpire = autoExpire
    }

    deinit {
        // 스케줄된 만료 Task 정리 — leak 방어 (must-fix).
        for task in expiryTasks.values { task.cancel() }
    }

    /// 새 dispatch 시작.
    public func recordStart(
        envelopeId: EnvelopeID,
        from: AgentID,
        to: AgentID,
        startedAt: Date = Date()
    ) {
        let entry = OrchestrationEntry(
            envelopeId: envelopeId,
            from: from,
            to: to,
            state: .running,
            startedAt: startedAt,
            updatedAt: startedAt
        )
        // 같은 envelopeId 가 이미 있으면 갱신
        if let idx = entries.firstIndex(where: { $0.envelopeId == envelopeId }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
    }

    public func recordCompletion(envelopeId: EnvelopeID, at completedAt: Date = Date()) {
        guard let idx = entries.firstIndex(where: { $0.envelopeId == envelopeId }) else {
            return
        }
        entries[idx].state = .completed
        entries[idx].updatedAt = completedAt
        scheduleExpiry(envelopeId: envelopeId)
    }

    public func recordFailure(
        envelopeId: EnvelopeID,
        message: String,
        at failedAt: Date = Date()
    ) {
        guard let idx = entries.firstIndex(where: { $0.envelopeId == envelopeId }) else {
            return
        }
        // bidi/control sanitization — status bar 표시 spoof 방어 (must-fix).
        entries[idx].state = .failed(message: DisplayTextSanitizer.sanitize(message))
        entries[idx].updatedAt = failedAt
        scheduleExpiry(envelopeId: envelopeId)
    }

    /// 만료된 항목을 즉시 정리 (테스트용).
    public func purgeExpired(now: Date = Date()) {
        let removed = entries.compactMap { entry -> EnvelopeID? in
            guard entry.state != .running else { return nil }
            guard now.timeIntervalSince(entry.updatedAt) >= autoExpire else { return nil }
            return entry.envelopeId
        }
        entries.removeAll { removed.contains($0.envelopeId) }
        for id in removed {
            expiryTasks[id]?.cancel()
            expiryTasks[id] = nil
        }
    }

    /// 진행 중 dispatch 가 있는가.
    public var hasRunning: Bool {
        entries.contains { $0.state == .running }
    }

    /// 같은 envelopeId 의 기존 expiry Task 가 있으면 cancel 후 새로 스케줄 — leak 방어.
    private func scheduleExpiry(envelopeId: EnvelopeID) {
        expiryTasks[envelopeId]?.cancel()
        let task = Task { @MainActor [weak self, autoExpire] in
            try? await Task.sleep(nanoseconds: UInt64(autoExpire * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.entries.removeAll { entry in
                entry.envelopeId == envelopeId && entry.state != .running
            }
            self.expiryTasks[envelopeId] = nil
        }
        expiryTasks[envelopeId] = task
    }
}

/// status bar 의 한 행.
public struct OrchestrationEntry: Sendable, Identifiable, Hashable {
    public let envelopeId: EnvelopeID
    public let from: AgentID
    public let to: AgentID
    public var state: State
    public let startedAt: Date
    public var updatedAt: Date

    public var id: EnvelopeID { envelopeId }

    public enum State: Sendable, Hashable {
        case running
        case completed
        case failed(message: String)
    }

    public init(
        envelopeId: EnvelopeID,
        from: AgentID,
        to: AgentID,
        state: State,
        startedAt: Date,
        updatedAt: Date
    ) {
        self.envelopeId = envelopeId
        self.from = from
        self.to = to
        self.state = state
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}
