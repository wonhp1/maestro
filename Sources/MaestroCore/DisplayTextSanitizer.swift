import Foundation

/// 어댑터/외부 입력에서 온 자유 텍스트를 UI 에 표시하기 전 거치는 sanitizer.
///
/// ## 책임
/// - **bidi controls 차단** (U+202A-E, U+2066-9): Trojan Source 류 텍스트 방향 spoof.
/// - **zero-width 차단** (U+200B-D, U+FEFF): 이름 중복 spoof.
/// - **제어 문자 → U+FFFD**: NUL/BEL 등이 다른 행 렌더에 영향 주지 않도록 가시화.
///
/// ## 적용 지점 (Phase 12 must-fix)
/// - `InboxStore.previewBody` (envelope.body)
/// - `AgentStatusStore.setActive(operation:)` / `.setError(message:)`
/// - `OrchestrationStatusModel.recordFailure(message:)`
///
/// `MarkdownRenderer.stripBidiControls` (Phase 8) 와 동일 정책 — 별도 함수로 분리한
/// 이유는 markdown 파싱이 필요 없는 짧은 inline 텍스트도 같은 보호를 받게 하기 위함.
public enum DisplayTextSanitizer {
    /// 입력을 표시 안전한 문자열로 변환. nil 입력은 nil 반환 (편의).
    public static func sanitize(_ text: String) -> String {
        var output = String()
        output.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            if dangerous.contains(scalar) { continue }
            if scalar.properties.generalCategory == .control && scalar != "\n" && scalar != "\t" {
                output.unicodeScalars.append(Unicode.Scalar(0xFFFD)!)
            } else {
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }

    public static func sanitize(_ text: String?) -> String? {
        guard let text else { return nil }
        return sanitize(text)
    }

    private static let dangerous: Set<Unicode.Scalar> = {
        let codepoints: [UInt32] = [
            0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
            0x2066, 0x2067, 0x2068, 0x2069,
            0x200B, 0x200C, 0x200D, 0xFEFF,
        ]
        return Set(codepoints.compactMap(Unicode.Scalar.init))
    }()
}
