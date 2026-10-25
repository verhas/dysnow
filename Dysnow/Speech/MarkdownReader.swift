import Foundation
import NaturalLanguage

/// Part of a block read in one way: one mood, one speaker, one speed.
struct SpokenRun: Equatable, Sendable {
    /// What is said: the Markdown and the symbols taken out.
    let text: String
    var style = SpeechStyle()
}

/// A piece of the text to be read on its own, followed by a pause: a
/// paragraph, a heading, a list item, a table row.
struct SpokenBlock: Equatable, Sendable {
    /// The block's text, cut where the markup changes how it is read.
    let runs: [SpokenRun]
    /// The silence after it, in seconds.
    let pauseAfter: Double
    /// Where it is in the text it was read from.
    let range: Range<String.Index>

    init(runs: [SpokenRun], pauseAfter: Double, range: Range<String.Index>) {
        self.runs = runs
        self.pauseAfter = pauseAfter
        self.range = range
    }

    /// Read all in one way.
    init(text: String, pauseAfter: Double, range: Range<String.Index>) {
        self.init(runs: [SpokenRun(text: text)], pauseAfter: pauseAfter, range: range)
    }

    var text: String { runs.map(\.text).joined(separator: " ") }
}

/// Reads text as Markdown -- which plain text is too -- into what is said:
/// "# Title" is "Title", "**bold**" is "bold", a link is its text, code
/// blocks are skipped, and symbols such as # or * are not spoken at all.
/// Paragraphs, separated by empty lines, are read with a pause between them;
/// lines of one paragraph run on as one. The `SpeechMarkup` tags in it set
/// how each part is read.
enum MarkdownReader {
    static let paragraphPause = 0.6
    static let listItemPause = 0.3
    static let tableRowPause = 0.25

    /// `markup` is the tags open where the source starts.
    static func blocks(in source: String, markup: SpeechMarkup.State = .init()) -> [SpokenBlock] {
        var reader = Reader(source: source, markup: markup)
        reader.read()
        return reader.blocks
    }

    /// The part of the source in the range, with the tags open before it.
    static func blocks(in source: String, range: Range<String.Index>) -> [SpokenBlock] {
        blocks(in: String(source[range]), markup: markup(in: source, before: range.lowerBound))
    }

    /// The tags open at a point of the source.
    static func markup(in source: String, before index: String.Index) -> SpeechMarkup.State {
        var reader = Reader(source: String(source[..<index]), markup: .init())
        reader.read()
        return reader.markup
    }

    /// From the sentence the cursor is in to the end.
    static func blocks(in source: String, from cursor: String.Index) -> [SpokenBlock] {
        let all = blocks(in: source)
        guard let index = all.firstIndex(where: { $0.range.upperBound >= cursor }) else { return [] }
        let block = all[index]
        let rest = Array(all[(index + 1)...])
        guard block.range.contains(cursor) || block.range.upperBound == cursor,
              cursor > block.range.lowerBound else { return Array(all[index...]) }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = source
        // At the very end of the block, the sentence is the one just before.
        let probe = cursor == block.range.upperBound ? source.index(before: cursor) : cursor
        let start = max(tokenizer.tokenRange(at: probe).lowerBound, block.range.lowerBound)
        let partial = blocks(in: source, range: start..<block.range.upperBound).map {
            // Its own text, but its place in the source and the pause of the
            // block it is the end of.
            SpokenBlock(runs: $0.runs, pauseAfter: $0.pauseAfter, range: start..<block.range.upperBound)
        }
        guard let last = partial.last else { return rest }
        return partial.dropLast()
            + [SpokenBlock(runs: last.runs, pauseAfter: block.pauseAfter, range: last.range)] + rest
    }

    /// The text of one block without its Markdown and the symbols nobody
    /// wants read out.
    static func speakable(_ markdown: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        var text = (try? AttributedString(markdown: markdown, options: options)).map { String($0.characters) }
            ?? markdown
        text = text.replacing(#/<!--.*?-->/#, with: " ")
            .replacing(#/https?:\/\/\S+/#, with: " ")
            .replacing(#/<\/?[A-Za-z][^>]*>/#, with: " ")
        var kept = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            kept.append(isSpoken(scalar) ? scalar : " ")
        }
        return String(kept)
            .replacing(#/\s+/#, with: " ")
            .replacing(#/ ([.,;:!?…。，、！？])/#) { $0.1 }
            .trimmingCharacters(in: .whitespaces)
    }

    /// Letters, digits, and the punctuation that tells a voice how to say
    /// things; currencies and per cent, which are read as words. Not markup,
    /// arrows, bullets, emoji and the like.
    private static func isSpoken(_ scalar: Unicode.Scalar) -> Bool {
        if "#*\\/@&|~`^_[]{}<>•·§¶†‡".unicodeScalars.contains(scalar) { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark,
             .decimalNumber, .letterNumber, .otherNumber,
             .spaceSeparator, .lineSeparator, .paragraphSeparator,
             .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation, .finalPunctuation,
             .otherPunctuation, .currencySymbol:
            return true
        default:
            return scalar == "\n" || scalar == "\t"
        }
    }

    /// Goes through the source line by line, gathering blocks.
    private struct Reader {
        let source: String
        var blocks: [SpokenBlock] = []
        /// The tags open at the point read to.
        private(set) var markup: SpeechMarkup.State
        /// The lines of the paragraph being gathered, and where it is.
        private var lines: [String] = []
        private var start: String.Index?
        private var end: String.Index?
        private var pause = MarkdownReader.paragraphPause
        /// The fence a code block was opened with, while in one.
        private var fence: String?

        init(source: String, markup: SpeechMarkup.State) {
            self.source = source
            self.markup = markup
        }

        mutating func read() {
            var lineRanges: [Range<String.Index>] = []
            source.enumerateSubstrings(in: source.startIndex..<source.endIndex, options: .byLines) { _, range, _, _ in
                lineRanges.append(range)
            }
            for range in lineRanges {
                readLine(String(source[range]), range: range)
            }
            flush()
        }

        private mutating func readLine(_ line: String, range: Range<String.Index>) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                return
            }
            if let match = trimmed.firstMatch(of: #/^(`{3,}|~{3,})/#) {
                flush()
                fence = String(match.1)
                return
            }
            if trimmed.isEmpty || trimmed.wholeMatch(of: #/([-*_=])(\s*\1){2,}/#) != nil
                || trimmed.wholeMatch(of: #/\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?/#) != nil {
                // An empty line, a rule, or a table's line under its header.
                flush()
                return
            }
            if let heading = trimmed.wholeMatch(of: #/#{1,6}(?:\s+(.*?))?(?:\s+#+)?\s*/#) {
                flush()
                add(String(heading.1 ?? ""), range: range, pause: MarkdownReader.paragraphPause)
                return
            }
            if trimmed.hasPrefix("|") {
                flush()
                let cells = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                add(cells.filter { !$0.isEmpty }.joined(separator: ", "), range: range,
                    pause: MarkdownReader.tableRowPause)
                return
            }
            var content = Substring(trimmed)
            if let quote = content.firstMatch(of: #/^(>\s?)+/#) {
                content = content[quote.range.upperBound...]
            }
            if let item = content.firstMatch(of: #/^([-*+]|\d{1,9}[.)])\s+(\[[ xX]\]\s+)?/#) {
                // A list item starts a block of its own; the lines after it
                // that are not items run on in it.
                flush()
                content = content[item.range.upperBound...]
                pause = MarkdownReader.listItemPause
            }
            if start == nil { start = range.lowerBound }
            end = range.upperBound
            lines.append(String(content))
        }

        private mutating func flush() {
            if let start, let end {
                add(lines.joined(separator: " "), range: start..<end, pause: pause)
            }
            lines = []
            start = nil
            end = nil
            pause = MarkdownReader.paragraphPause
        }

        /// Cuts the block where a tag is, each part read as the tags open
        /// there say; a block of nothing but tags only opens and closes them.
        private mutating func add(_ markdown: String, range: Range<String.Index>, pause: Double) {
            var runs: [SpokenRun] = []
            func say(_ part: Substring, as style: SpeechStyle) {
                let text = MarkdownReader.speakable(String(part))
                // Nothing but symbols: nothing to say.
                guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return }
                if let last = runs.last, last.style == style {
                    runs[runs.count - 1] = SpokenRun(text: last.text + " " + text, style: style)
                } else {
                    runs.append(SpokenRun(text: text, style: style))
                }
            }
            var rest = markdown[...]
            for tag in markdown.matches(of: SpeechMarkup.tag) {
                say(rest[..<tag.range.lowerBound], as: markup.style)
                markup.apply(closing: !tag.1.isEmpty, kind: String(tag.2), value: (tag.3 ?? tag.4).map(String.init))
                rest = markdown[tag.range.upperBound...]
            }
            say(rest, as: markup.style)
            guard !runs.isEmpty else { return }
            blocks.append(SpokenBlock(runs: runs, pauseAfter: pause, range: range))
        }
    }
}
