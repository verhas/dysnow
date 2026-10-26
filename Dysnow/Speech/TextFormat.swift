import Foundation

/// How the text is written: what in it is markup, and how the speech tags
/// look in it. Picked in the toolbar, or by the extension of the file opened.
enum TextFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown, plain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: "Markdown"
        case .plain: "Plain Text"
        }
    }

    var syntax: MarkupSyntax {
        switch self {
        case .markdown: .markdown
        case .plain: .plain
        }
    }

    /// The format a file of this kind is written in; nil when the extension
    /// does not tell.
    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd": self = .markdown
        case "txt", "text": self = .plain
        default: return nil
        }
    }
}

/// How the speech tags are written in a format. In Markdown they are HTML
/// comments, which a Markdown viewer does not show:
///
///     <!-- tts:mood value="excited" --> ... <!-- /tts:mood -->
///
/// Plain text has no comments; the tags are in brackets there:
///
///     [tts:mood value="excited"] ... [/tts:mood]
struct MarkupSyntax: Sendable {
    /// What starts and what ends a tag: "<!--" and "-->".
    let opener: String
    let closer: String
    /// Between the opener and the tag, and the tag and the closer.
    let padding: String

    static let markdown = MarkupSyntax(opener: "<!--", closer: "-->", padding: " ")
    static let plain = MarkupSyntax(opener: "[", closer: "]", padding: "")

    /// The kinds of tag, in the order they are offered. `set` changes
    /// several things at once, and stays until the next one, or until its
    /// closing tag.
    static let kinds = ["speed", "speaker", "mood", "language", "set"]

    /// What a `set` tag may change, in the order they are offered.
    static let setAttributes = ["language", "model", "speaker", "speed", "mood"]

    func openingTag(_ kind: String, value: String) -> String {
        "\(opener)\(padding)tts:\(kind) value=\"\(value)\"\(padding)\(closer)"
    }

    func closingTag(_ kind: String) -> String {
        "\(opener)\(padding)/tts:\(kind)\(padding)\(closer)"
    }

    /// A speech tag found in a text.
    struct Tag {
        let range: Range<String.Index>
        let closing: Bool
        /// "mood", lowercased.
        let kind: String
        /// By name, lowercased: "value", or `set`'s "language", "model"...
        let attributes: [String: String]
    }

    /// The tags in a text.
    func tags(in text: String) -> [Tag] {
        text.matches(of: regex).map { match in
            var attributes: [String: String] = [:]
            for attribute in match.3.matches(of: Self.attribute) {
                attributes[attribute.1.lowercased()] = String(attribute.2 ?? attribute.3 ?? "")
            }
            return Tag(range: match.range, closing: !match.1.isEmpty, kind: match.2.lowercased(),
                       attributes: attributes)
        }
    }

    private var regex: Regex<(Substring, Substring, Substring, Substring)> {
        opener == "<!--" ? Self.markdownTag : Self.plainTag
    }

    // Groups: the slash of a closing tag, the kind, the attributes. After
    // the first, an attribute need not be spaced from the quote before it:
    // `language="Hungarian"speaker=""` is read as two.
    nonisolated(unsafe) private static let markdownTag =
        #/<!--\s*(/?)tts:([A-Za-z]+)((?:\s+[A-Za-z]+\s*=\s*(?:"[^"]*"|'[^']*')(?:\s*[A-Za-z]+\s*=\s*(?:"[^"]*"|'[^']*'))*)?)\s*-->/#
    nonisolated(unsafe) private static let plainTag =
        #/\[\s*(/?)tts:([A-Za-z]+)((?:\s+[A-Za-z]+\s*=\s*(?:"[^"]*"|'[^']*')(?:\s*[A-Za-z]+\s*=\s*(?:"[^"]*"|'[^']*'))*)?)\s*\]/#
    /// Groups: the name, the value in double or in single quotes.
    nonisolated(unsafe) private static let attribute = #/([A-Za-z]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/#
}
