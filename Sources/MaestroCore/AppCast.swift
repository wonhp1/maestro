import Foundation

/// Sparkle appcast XML 의 단일 release 항목.
public struct AppCastItem: Sendable, Equatable, Hashable {
    public let title: String
    public let version: AppVersion
    /// .dmg 다운로드 URL (Sparkle `<enclosure url="...">`)
    public let downloadURL: URL
    /// optional release notes URL
    public let releaseNotesURL: URL?
    /// EdDSA signature (Sparkle `sparkle:edSignature` attribute)
    public let edSignature: String?
    /// 다운로드 크기 (bytes), 0 이면 unknown
    public let length: Int

    public init(
        title: String,
        version: AppVersion,
        downloadURL: URL,
        releaseNotesURL: URL? = nil,
        edSignature: String? = nil,
        length: Int = 0
    ) {
        self.title = title
        self.version = version
        self.downloadURL = downloadURL
        self.releaseNotesURL = releaseNotesURL
        self.edSignature = edSignature
        self.length = max(0, length)
    }
}

/// 최소 Sparkle appcast XML 파서 — 외부 라이브러리 의존 없이 우리 용도만 지원.
///
/// ## 지원 구조
/// ```xml
/// <rss>
///   <channel>
///     <item>
///       <title>1.2.0</title>
///       <sparkle:version>1.2.0</sparkle:version>
///       <sparkle:releaseNotesLink>https://...</sparkle:releaseNotesLink>
///       <enclosure url="..." sparkle:edSignature="..." length="123" />
///     </item>
///   </channel>
/// </rss>
/// ```
///
/// 신뢰 boundary: 네트워크에서 받은 XML — `<enclosure url>` 은 https 만 허용.
/// edSignature 미검증 항목은 표시하되, `UpdateChecker` 는 있을 때만 install 진행 의도.
public enum AppCastParser {
    public static func parse(data: Data) -> [AppCastItem] {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return delegate.items
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var items: [AppCastItem] = []
        private var currentTitle: String?
        private var currentVersionString: String?
        private var currentReleaseNotes: URL?
        private var currentEnclosureURL: URL?
        private var currentEdSignature: String?
        private var currentLength: Int = 0
        private var currentText: String = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            currentText = ""
            switch elementName {
            case "item":
                resetCurrentItem()
            case "enclosure":
                if let urlString = attributeDict["url"], let url = URL(string: urlString),
                   url.scheme == "https" {
                    currentEnclosureURL = url
                }
                currentEdSignature = attributeDict["sparkle:edSignature"]
                if let lengthStr = attributeDict["length"], let l = Int(lengthStr) {
                    currentLength = l
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentText.append(string)
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "title":
                if currentTitle == nil { currentTitle = trimmed }
            case "sparkle:version":
                currentVersionString = trimmed
            case "sparkle:releaseNotesLink":
                if let url = URL(string: trimmed), url.scheme == "https" {
                    currentReleaseNotes = url
                }
            case "item":
                if let v = currentVersionString.flatMap(AppVersion.init(string:)),
                   let u = currentEnclosureURL {
                    items.append(AppCastItem(
                        title: currentTitle ?? v.description,
                        version: v,
                        downloadURL: u,
                        releaseNotesURL: currentReleaseNotes,
                        edSignature: currentEdSignature,
                        length: currentLength
                    ))
                }
                resetCurrentItem()
            default:
                break
            }
            currentText = ""
        }

        private func resetCurrentItem() {
            currentTitle = nil
            currentVersionString = nil
            currentReleaseNotes = nil
            currentEnclosureURL = nil
            currentEdSignature = nil
            currentLength = 0
        }
    }
}
