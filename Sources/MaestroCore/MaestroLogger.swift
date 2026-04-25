import Foundation
import os

/// `os.Logger` 위에 얹은 카테고리 + 프라이버시 기본값 wrapper.
///
/// ## 디자인 원칙
/// - **Sendable struct** — actor isolation 없이 어디서든 가볍게 인스턴스화.
/// - **subsystem 고정**: 기본 `MaestroConfig.bundleIdentifier`. Console.app 에서
///   `subsystem: com.gimgyeongwon.maestro` 로 필터하면 Maestro 만 추출.
/// - **privacy 기본 .private**: 동적 문자열은 시스템 로그에서 마스킹. `publicXxx` 메서드는
///   `StaticString` 만 받아 컴파일 타임에 secrets 유입 차단 (Phase 5 must-fix).
/// - **lazy 메시지**: 모든 메서드는 `@autoclosure` — 필터링된 레벨에서는 보간 평가
///   자체를 건너뜀 (`os.Logger` 의 디자인 의도 보존).
/// - **logger 캐시**: `(subsystem, category)` 별 단일 `os.Logger` 공유 — 인스턴스
///   생성 시 hashtable 룩업만 발생.
///
/// ## 사용
/// ```swift
/// let log = MaestroLogger(category: .adapter)
/// log.info("Detected adapter \(adapterId)")            // 마스킹됨 (private), lazy
/// log.publicInfo("App launched")                        // 평문 (StaticString만)
/// ```
///
/// ## NOTE
/// 로그 메시지는 의도적으로 비-로컬라이즈 (개발자/지원 대상). Phase 22 i18n 영역 외.
///
/// - SeeAlso: `MaestroSignposter` (성능 인터벌)
/// - SeeAlso: `GlobalErrorHandler` (전역 에러 → 로그)
public struct MaestroLogger: Sendable {
    public let subsystem: String
    public let category: LogCategory
    private let logger: Logger

    public init(category: LogCategory, subsystem: String = MaestroConfig.bundleIdentifier) {
        self.subsystem = subsystem
        self.category = category
        // os.Logger 는 (subsystem, category) 별로 내부 캐시 — 별도 캐시 불필요.
        self.logger = Logger(subsystem: subsystem, category: category.rawValue)
    }

    // MARK: - Privacy: .private (동적 문자열은 마스킹) — autoclosure for lazy interpolation

    public func debug(_ message: @autoclosure @escaping () -> String) {
        logger.debug("\(message(), privacy: .private)")
    }

    public func info(_ message: @autoclosure @escaping () -> String) {
        logger.info("\(message(), privacy: .private)")
    }

    public func notice(_ message: @autoclosure @escaping () -> String) {
        logger.notice("\(message(), privacy: .private)")
    }

    public func warning(_ message: @autoclosure @escaping () -> String) {
        logger.warning("\(message(), privacy: .private)")
    }

    public func error(_ message: @autoclosure @escaping () -> String) {
        logger.error("\(message(), privacy: .private)")
    }

    public func fault(_ message: @autoclosure @escaping () -> String) {
        logger.fault("\(message(), privacy: .private)")
    }

    // MARK: - Privacy: .public — StaticString 으로 컴파일 타임에 secret 유입 차단.

    public func publicInfo(_ message: StaticString) {
        logger.info("\(message, privacy: .public)")
    }
}
