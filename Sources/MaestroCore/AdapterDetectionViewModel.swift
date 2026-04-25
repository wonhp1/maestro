import Foundation
import Observation

/// 등록된 모든 어댑터의 설치 상태를 한 번에 감지해서 UI 에 노출.
///
/// ## 사용처
/// - `+ 폴더 추가` 의 vendor picker sheet — 사용자가 어느 어댑터를 쓸지 선택할 때
///   각 어댑터가 실제로 설치돼있는지 보여줘야 함.
/// - 폴더 설정 시트 — 등록 후 어댑터 변경.
///
/// ## 책임
/// - `AdapterRegistry.detectAll()` 호출 → 결과 캐싱
/// - 각 어댑터별 설치 안내 메시지 (한국어) 매핑
/// - 정렬된 어댑터 ID 목록 노출
///
/// ## 동시성
/// `@MainActor` — UI 와 같은 isolation. registry actor 는 await 로 호출.
@MainActor
@Observable
public final class AdapterDetectionViewModel {
    public private(set) var detections: [String: AdapterDetection] = [:]
    public private(set) var sortedAdapterIDs: [String] = []
    public private(set) var displayNames: [String: String] = [:]
    public private(set) var isDetecting: Bool = false

    private let registry: AdapterRegistry

    public init(registry: AdapterRegistry) {
        self.registry = registry
    }

    /// 모든 어댑터에 대해 detect 호출 — 결과 캐싱. 호출 중 isDetecting=true.
    /// displayNames 도 동시에 캡처해서 UI 의 하드코딩된 vendor name switch 제거.
    public func refresh() async {
        isDetecting = true
        defer { isDetecting = false }
        let ids = await registry.adapterIds()
        let results = await registry.detectAll()
        let adapters = await registry.allAdapters()
        var nameMap: [String: String] = [:]
        for adapter in adapters {
            nameMap[adapter.id] = adapter.displayName
        }
        detections = results
        sortedAdapterIDs = ids
        displayNames = nameMap
    }

    /// 특정 어댑터의 감지 결과. 없으면 nil (아직 refresh 호출 전 또는 등록 안 된 어댑터).
    public func detection(for adapterId: String) -> AdapterDetection? {
        detections[adapterId]
    }

    /// 어댑터의 사람 친화 표시 이름. 없으면 raw id 반환.
    public func displayName(for adapterId: String) -> String {
        displayNames[adapterId] ?? adapterId
    }

    /// 미설치 어댑터에 대한 사용자 친화 설치 안내 메시지.
    /// 알려진 어댑터만 매핑됨 (claude / aider). 나머지는 nil → UI 가 일반 안내 표시.
    public static func installationHint(for adapterId: String) -> InstallationHint? {
        switch adapterId {
        case "claude":
            return InstallationHint(
                command: "npm install -g @anthropic-ai/claude-code",
                docsURL: URL(string: "https://docs.anthropic.com/en/docs/claude-code/setup"),
                description: "Claude Code CLI 가 설치되어 있지 않아요."
            )
        case "aider":
            return InstallationHint(
                command: "pip install aider-chat",
                docsURL: URL(string: "https://aider.chat/docs/install.html"),
                description: "Aider 가 설치되어 있지 않아요."
            )
        default:
            return nil
        }
    }

    /// 사용자 친화 어댑터 설명 — vendor picker 행에 한 줄로 표시.
    public static func description(for adapterId: String) -> String? {
        switch adapterId {
        case "claude":
            return "Anthropic 의 공식 코딩 에이전트. 도구 사용이 강하고 처음 쓰기 좋아요."
        case "aider":
            return "오픈소스 멀티 모델 (OpenAI / Claude / Gemini 등) 지원. git 자동 커밋 강점."
        default:
            return nil
        }
    }

    /// "처음 쓰기 좋음" / "추천" 등의 벳지 — 무거운 표지 아니지만 시작점 안내.
    public static func recommendationBadge(for adapterId: String) -> String? {
        switch adapterId {
        case "claude": return "처음 쓰기 좋음"
        default: return nil
        }
    }
}

/// 미설치 어댑터의 설치 안내 — UI 에 inline 표시용.
public struct InstallationHint: Equatable, Sendable {
    public let command: String
    public let docsURL: URL?
    public let description: String

    public init(command: String, docsURL: URL?, description: String) {
        self.command = command
        self.docsURL = docsURL
        self.description = description
    }
}
