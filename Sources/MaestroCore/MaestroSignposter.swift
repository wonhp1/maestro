import Foundation
import os

/// `OSSignposter` 위에 얹은 카테고리 wrapper. Instruments 의 *Points of Interest* /
/// *os_signpost* 인스트루먼트로 인터벌 가시화.
///
/// 카테고리는 `LogCategory` 와 동일 enum 사용 — Console.app 의 logger 필터와
/// Instruments 의 signposter 필터를 같은 키로 맞춤.
///
/// ## 사용
/// ```swift
/// let sp = MaestroSignposter(category: .adapter)
/// let result = await sp.interval("detect-claude") {
///     await detector.detect(profile: ...)
/// }
/// ```
///
/// - Note: signpost 이름은 `StaticString` — 컴파일 타임 상수만 허용 (Instruments
///   요구사항).
public struct MaestroSignposter: Sendable {
    public let subsystem: String
    public let category: LogCategory
    private let signposter: OSSignposter

    public init(category: LogCategory, subsystem: String = MaestroConfig.bundleIdentifier) {
        self.subsystem = subsystem
        self.category = category
        self.signposter = OSSignposter(subsystem: subsystem, category: category.rawValue)
    }

    /// 새 signpost ID 발급. 동일 인터벌의 begin/end 페어링에 사용.
    public func makeSignpostID() -> OSSignpostID {
        signposter.makeSignpostID()
    }

    /// 명시적 begin — interval 패턴이 안 맞을 때 (e.g., 콜백 분리).
    public func begin(_ name: StaticString, id: OSSignpostID) -> OSSignpostIntervalState {
        signposter.beginInterval(name, id: id)
    }

    /// 명시적 end — `begin` 의 state 와 페어.
    public func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    /// 단일 시점 이벤트 — `name` 만 기록.
    public func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }

    // MARK: - Scope helpers

    /// async 클로저를 인터벌로 감싸기 — begin/end 자동.
    public func interval<T: Sendable>(
        _ name: StaticString,
        body: () async throws -> T
    ) async rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        defer { signposter.endInterval(name, state) }
        return try await body()
    }

    /// 동기 클로저용 인터벌 — UI / 짧은 작업.
    public func interval<T>(
        _ name: StaticString,
        body: () throws -> T
    ) rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        defer { signposter.endInterval(name, state) }
        return try body()
    }
}
