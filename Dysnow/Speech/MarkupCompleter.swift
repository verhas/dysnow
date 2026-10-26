import Foundation

/// What Control-Space offers at the cursor, for writing speech tags.
///
/// Outside a tag it offers the kinds of tag; picking one puts a tag of that
/// kind around the selection, with the cursor in its empty value, where the
/// values are offered next. In a tag written halfway it offers only what is
/// missing: the rest of the kind, the value, the end of the tag.
struct MarkupCompleter {
    let syntax: MarkupSyntax
    /// The values offered for a kind of tag, or an attribute of a `set`
    /// tag: the speakers, the moods, the languages, the models. None for
    /// speeds, which are numbers. Given what else the `set` tag being written
    /// says, "language" and "model", which the speakers depend on.
    let values: (String, [String: String]) -> [String]

    init(syntax: MarkupSyntax, values: @escaping (String, [String: String]) -> [String]) {
        self.syntax = syntax
        self.values = values
    }

    /// For values that depend on nothing else.
    init(syntax: MarkupSyntax, values: @escaping (String) -> [String]) {
        self.init(syntax: syntax) { kind, _ in values(kind) }
    }

    /// What a pick does to the text: puts `replacement` in place of `range`
    /// and selects `selection`, in UTF-16 units from where the replacement
    /// starts.
    struct Edit: Equatable {
        let range: Range<String.Index>
        let replacement: String
        let selection: Range<Int>

        /// The text with the edit made, and what is selected then.
        func applied(to text: String) -> (text: String, selection: NSRange) {
            let start = NSRange(range, in: text).location
            var edited = text
            edited.replaceSubrange(range, with: replacement)
            return (edited, NSRange(location: start + selection.lowerBound, length: selection.count))
        }
    }

    struct Choice: Equatable {
        /// Shown in the menu: "speaker", "Liam".
        let title: String
        let edit: Edit
        /// Whether to complete again after it is made: after a kind, for its
        /// value.
        let completesFurther: Bool
    }

    /// The speed put in when there is none: its digits are selected, to be
    /// typed over.
    static let speedSuggestion = "120%"

    func choices(in text: String, selection: Range<String.Index>) -> [Choice] {
        let cursor = selection.lowerBound
        let lineStart = text[..<cursor].lastIndex(where: \.isNewline).map(text.index(after:)) ?? text.startIndex
        let lineEnd = text[cursor...].firstIndex(where: \.isNewline) ?? text.endIndex
        let before = text[lineStart..<cursor]
        if selection.isEmpty, let opener = before.range(of: syntax.opener, options: .backwards),
           !before[opener.upperBound...].contains(syntax.closer),
           let inside = choicesInside(text, fragment: before[opener.upperBound...], lineEnd: lineEnd) {
            return inside
        }
        return skeletons(in: text, selection: selection, lineStart: lineStart)
    }

    // MARK: Outside a tag

    /// A tag of each kind around the selection; a start of an opener just
    /// typed, "<!-", is made the whole of it.
    private func skeletons(in text: String, selection: Range<String.Index>,
                           lineStart: String.Index) -> [Choice] {
        var range = selection
        if selection.isEmpty {
            let before = text[lineStart..<selection.lowerBound]
            if let typed = (1..<syntax.opener.count).reversed().map({ String(syntax.opener.prefix($0)) })
                .first(where: { before.hasSuffix($0) }) {
                range = text.index(selection.lowerBound, offsetBy: -typed.count)..<selection.upperBound
            }
        }
        let selected = String(text[selection])
        return (selection.isEmpty ? closings(before: selection.lowerBound, in: text, range: range) : [])
            + MarkupSyntax.kinds.map { kind in
            if kind == "set" {
                // It changes things from here on: closed only around a
                // selection.
                let head = syntax.opener + syntax.padding + "tts:set "
                let closing = selected.isEmpty ? "" : selected + syntax.closingTag(kind)
                return Choice(title: kind,
                              edit: Edit(range: range, replacement: head + syntax.padding + syntax.closer + closing,
                                         selection: head.utf16.count..<head.utf16.count),
                              completesFurther: true)
            }
            let opening = syntax.openingTag(kind, value: "")
            let quote = opening.utf16.count - syntax.padding.utf16.count - syntax.closer.utf16.count - 1
            return Choice(title: kind,
                          edit: Edit(range: range, replacement: opening + selected + syntax.closingTag(kind),
                                     selection: quote..<quote),
                          completesFurther: true)
        }
    }

    /// The tags open at the cursor, the innermost first: each choice closes
    /// one of them and every one opened inside it.
    private func closings(before cursor: String.Index, in text: String, range: Range<String.Index>) -> [Choice] {
        var open: [String] = []
        for tag in syntax.tags(in: String(text[..<cursor])) where MarkupSyntax.kinds.contains(tag.kind) {
            if !tag.closing {
                open.append(tag.kind)
            } else if let index = open.lastIndex(of: tag.kind) {
                open.remove(at: index)
            }
        }
        var closed = ""
        var titles: [String] = []
        return open.reversed().map { kind in
            closed += syntax.closingTag(kind)
            titles.append("/tts:\(kind)")
            return Choice(title: "Close " + titles.joined(separator: " "),
                          edit: Edit(range: range, replacement: closed,
                                     selection: closed.utf16.count..<closed.utf16.count),
                          completesFurther: false)
        }
    }

    // MARK: Inside a tag

    /// What is missing from the tag the cursor is in; nil when what follows
    /// the opener is not the start of a speech tag.
    private func choicesInside(_ text: String, fragment: Substring, lineEnd: String.Index) -> [Choice]? {
        let cursor = fragment.endIndex
        let after = text[cursor..<lineEnd]
        // The end of the tag, when it is already written.
        let closer = after.range(of: syntax.closer).flatMap { closer in
            after.range(of: syntax.opener).map { $0.lowerBound < closer.lowerBound } == true ? nil : closer
        }
        let ending = closer == nil ? syntax.padding + syntax.closer : ""

        // "<!-- ", "<!-- /tt", "<!-- tts:spe"
        if let match = fragment.wholeMatch(of: #/(\s*)(/?)(?:t(?:t(?:s(?::([A-Za-z]*))?)?)?)?/#) {
            let closing = !match.2.isEmpty
            let start = match.2.endIndex
            let partial = match.3.map(String.init) ?? ""
            let lead = match.1.isEmpty && match.2.isEmpty ? syntax.padding : ""
            return kinds(matching: partial).map { kind in
                if closer != nil, let typed = match.3 {
                    // Only the kind is missing: the rest of the tag is there.
                    let wordEnd = after.firstIndex { !$0.isLetter } ?? after.endIndex
                    return Choice(title: kind, edit: Edit(range: typed.startIndex..<wordEnd, replacement: kind,
                                                          selection: kind.utf16.count..<kind.utf16.count),
                                  completesFurther: false)
                }
                if closing {
                    let replacement = "tts:\(kind)" + ending
                    return Choice(title: kind, edit: Edit(range: start..<cursor, replacement: replacement,
                                                          selection: replacement.utf16.count..<replacement.utf16.count),
                                  completesFurther: false)
                }
                if kind == "set" {
                    let head = lead + "tts:set "
                    return Choice(title: kind, edit: Edit(range: start..<cursor, replacement: head + ending,
                                                          selection: head.utf16.count..<head.utf16.count),
                                  completesFurther: true)
                }
                let head = lead + "tts:\(kind) value=\""
                return Choice(title: kind, edit: Edit(range: start..<cursor, replacement: head + "\"" + ending,
                                                      selection: head.utf16.count..<head.utf16.count),
                              completesFurther: true)
            }
        }
        // "<!-- /tts:mood "
        if let match = fragment.wholeMatch(of: #/\s*/tts:([A-Za-z]+)\s*/#) {
            guard known(match.1), closer == nil else { return [] }
            let replacement = (match.output.0.last?.isWhitespace == true ? "" : syntax.padding) + syntax.closer
            return [Choice(title: syntax.closer, edit: Edit(range: cursor..<cursor, replacement: replacement,
                                                           selection: replacement.utf16.count..<replacement.utf16.count),
                           completesFurther: false)]
        }
        // "<!-- tts:set language="hu" mod"
        if let match = fragment.wholeMatch(of: #/\s*tts:set(\s.*)?/#.ignoresCase()) {
            return setChoices(text, attributes: match.1 ?? fragment[cursor...], after: after, closer: closer,
                              ending: ending)
        }
        // "<!-- tts:mood ", "<!-- tts:mood val", "<!-- tts:mood value="
        if let match = fragment.wholeMatch(of: #/\s*tts:([A-Za-z]+)(\s+)([A-Za-z]*\s*=?\s*)/#) {
            let typed = match.3.filter { !$0.isWhitespace }
            guard known(match.1), "value=".hasPrefix(typed) || typed == "value=" else { return [] }
            let head = "value=\""
            return [Choice(title: "value", edit: Edit(range: match.3.startIndex..<cursor, replacement: head + "\"" + ending,
                                                      selection: head.utf16.count..<head.utf16.count),
                           completesFurther: true)]
        }
        // "<!-- tts:mood value="ex"
        if let match = fragment.wholeMatch(of: #/\s*tts:([A-Za-z]+)\s+value\s*=\s*(["'])([^"']*)/#) {
            guard known(match.1) else { return [] }
            return valueChoices(text, of: match.1.lowercased(), context: [:], quote: Character(String(match.2)),
                                partial: match.3, after: after, closer: closer, ending: ending)
        }
        // "<!-- tts:mood value="excited" "
        if let match = fragment.wholeMatch(of: #/\s*tts:([A-Za-z]+)\s+value\s*=\s*(?:"[^"]*"|'[^']*')(\s*)/#) {
            guard known(match.1), closer == nil else { return [] }
            let replacement = (match.2.isEmpty ? syntax.padding : "") + syntax.closer
            return [Choice(title: syntax.closer, edit: Edit(range: cursor..<cursor, replacement: replacement,
                                                           selection: replacement.utf16.count..<replacement.utf16.count),
                           completesFurther: false)]
        }
        return nil
    }

    /// The value being written, up to the cursor: the values that start so,
    /// or for a speed, `speedSuggestion` to be typed over.
    private func valueChoices(_ text: String, of kind: String, context: [String: String], quote: Character,
                              partial typed: Substring, after: Substring, closer: Range<String.Index>?,
                              ending: String) -> [Choice] {
        let cursor = typed.endIndex
        let partial = String(typed)
        // The rest of the value, up to its closing quote, is replaced too.
        let closingQuote = after.firstIndex(of: quote).flatMap { index in
            closer.map { index < $0.lowerBound } ?? true ? index : nil
        }
        let end = closingQuote.map { closer == nil ? after.index(after: $0) : $0 } ?? cursor
        let tail = closingQuote == nil || closer == nil ? String(quote) + ending : ""
        // After a pick the cursor goes past the tag, to what it is about.
        let past = closer.map { text.utf16.distance(from: end, to: $0.upperBound) } ?? 0
        if kind == "speed" {
            let value = partial.isEmpty ? Self.speedSuggestion : partial
            let selection = partial.isEmpty ? 0..<(value.utf16.count - 1)
                : (value + tail).utf16.count + past ..< (value + tail).utf16.count + past
            return [Choice(title: value, edit: Edit(range: typed.startIndex..<end, replacement: value + tail,
                                                    selection: selection),
                           completesFurther: false)]
        }
        return values(kind, context).filter { $0.lowercased().hasPrefix(partial.lowercased()) }.map { value in
            let replacement = value + tail
            let caret = replacement.utf16.count + past
            return Choice(title: value, edit: Edit(range: typed.startIndex..<end, replacement: replacement,
                                                   selection: caret..<caret),
                          completesFurther: false)
        }
    }

    /// In a `set` tag: the attributes not written yet, the `=""` after one,
    /// its value, or the end of the tag.
    private func setChoices(_ text: String, attributes: Substring, after: Substring, closer: Range<String.Index>?,
                            ending: String) -> [Choice] {
        let cursor = attributes.endIndex
        var rest = attributes
        var written: [String: String] = [:]
        while let attribute = rest.prefixMatch(of: #/\s*([A-Za-z]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/#) {
            written[attribute.1.lowercased()] = String(attribute.2 ?? attribute.3 ?? "")
            rest = rest[attribute.range.upperBound...]
        }
        // "language="hu" mo", or nothing yet
        if let match = rest.wholeMatch(of: #/(\s*)([A-Za-z]*)/#) {
            let unwritten = MarkupSyntax.setAttributes.filter { written[$0] == nil }
            let names = unwritten.filter { $0.hasPrefix(match.2.lowercased()) }
            if names.isEmpty {
                guard closer == nil, match.2.isEmpty else { return [] }
                let replacement = (match.1.isEmpty ? syntax.padding : "") + syntax.closer
                return [Choice(title: syntax.closer, edit: Edit(range: cursor..<cursor, replacement: replacement,
                                                               selection: replacement.utf16.count..<replacement.utf16.count),
                               completesFurther: false)]
            }
            let space = match.1.isEmpty && rest.startIndex != text.startIndex
                && !text[text.index(before: rest.startIndex)].isWhitespace ? " " : ""
            return names.map { name in
                let head = space + name + "=\""
                return Choice(title: name, edit: Edit(range: match.2.startIndex..<cursor,
                                                      replacement: head + "\"" + gap(before: after) + ending,
                                                      selection: head.utf16.count..<head.utf16.count),
                              completesFurther: true)
            }
        }
        // "language", "language="
        if let match = rest.wholeMatch(of: #/\s*([A-Za-z]+)(\s*=?\s*)/#) {
            guard MarkupSyntax.setAttributes.contains(match.1.lowercased()) else { return [] }
            return [Choice(title: "=\"\"", edit: Edit(range: match.2.startIndex..<cursor,
                                                     replacement: "=\"\"" + gap(before: after) + ending,
                                                     selection: 2..<2),
                           completesFurther: true)]
        }
        // "language="h"
        if let match = rest.wholeMatch(of: #/\s*([A-Za-z]+)\s*=\s*(["'])([^"']*)/#) {
            let name = match.1.lowercased()
            guard MarkupSyntax.setAttributes.contains(name) else { return [] }
            return valueChoices(text, of: name, context: written, quote: Character(String(match.2)),
                                partial: match.3, after: after, closer: closer, ending: ending)
        }
        return []
    }

    /// A space when an attribute follows right after the cursor: written
    /// before "speaker", "language" is to be kept apart from it.
    private func gap(before after: Substring) -> String {
        after.first?.isLetter == true ? " " : ""
    }

    private func kinds(matching partial: String) -> [String] {
        MarkupSyntax.kinds.filter { $0.hasPrefix(partial.lowercased()) }
    }

    private func known(_ kind: Substring) -> Bool {
        MarkupSyntax.kinds.contains(kind.lowercased())
    }
}
