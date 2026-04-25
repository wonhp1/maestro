import Foundation

/// 시스템 알림 추상화 — 테스트에서 모킹하기 위한 경계.
///
/// 운영체제는 사용자 집중 모드 / Do Not Disturb 규칙을 자동 적용 — 우리 코드는
/// 단순 schedule 만 호출. 권한 요청은 한 번만, 이후는 캐시된 상태.
///
/// 메시지/제목은 호출자가 sanitize 한 상태로 전달해야 함 — 본 인터페이스는
/// payload 변형 없음.
public protocol NotificationService: Sendable {
    /// 알림 권한 요청. 사용자가 한 번 허용/거부한 후엔 OS 가 결정 캐시.
    func requestAuthorization() async -> Bool

    /// 단일 알림 schedule. id 가 같으면 OS 가 dedupe.
    func notify(_ notification: AppNotification) async
}

/// 시스템 알림 payload. **호출자는 외부에서 온 텍스트(에이전트 응답 등)를
/// `DisplayTextSanitizer.sanitize` 거친 후 title/body 에 담아야 함** —
/// `NotificationService` 구현은 raw 그대로 OS 에 전달.
public struct AppNotification: Sendable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let body: String
    /// 배지 카운트로 사용 (0 이면 변경 없음).
    public let badge: Int?

    public init(id: String, title: String, body: String, badge: Int? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.badge = badge
    }
}

/// 비활성 구현 — 테스트 / unit-test 진입점에서 사용.
public actor NoopNotificationService: NotificationService {
    public private(set) var sent: [AppNotification] = []
    public private(set) var authorizedRequested: Bool = false

    public init() {}

    public func requestAuthorization() async -> Bool {
        authorizedRequested = true
        return true
    }

    public func notify(_ notification: AppNotification) async {
        sent.append(notification)
    }
}
