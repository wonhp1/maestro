import Foundation

/// 모든 영속성 레이어 (FileStore / JSONL / Keychain / FileWatcher) 가 공유하는 에러 타입.
///
/// `underlying` 은 원본 에러의 설명 문자열로 보존 — `Equatable` 준수 + 민감 정보 로깅 방지.
public enum PersistenceError: Error, Equatable, Sendable {
    /// 파일 자체가 없어 읽을 수 없음.
    case fileNotFound(URL)
    /// JSON 디코딩 실패. 파일 손상 / 스키마 불일치 가능.
    case decodingFailed(path: URL, underlying: String)
    /// JSON 인코딩 실패. 매우 드물지만 Codable 순환 참조 등.
    case encodingFailed(path: URL, underlying: String)
    /// 원자적 쓰기 실패. 디스크 공간 부족 / 권한 부재 / FS 오류.
    case atomicWriteFailed(path: URL, underlying: String)
    /// 파일 잠금(fcntl) 획득 실패.
    case lockFailed(URL)
    /// Keychain 작업 실패 (`OSStatus` 기반).
    case keychainFailed(status: Int32)
    /// 경로가 규칙 위반 (샌드박스 이탈 등).
    case invalidPath(URL)
    /// 파일 감시(DispatchSource) 시작 실패.
    case watcherStartFailed(URL)
}
