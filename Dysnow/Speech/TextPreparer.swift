import Foundation
import FoundationModels
import NaturalLanguage

/// Makes a text ready to be read aloud with Apple Intelligence, on the Mac
/// itself: typos fixed, abbreviations and signs written out as they are
/// said -- "e.g." as "for example", "2*4" as "two times four". The text is
/// gone through a paragraph at a time; the speech tags and the code blocks
/// are left as they are.
@MainActor
enum TextPreparer {
    /// Why it cannot be used here, or nil when it can.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This Mac cannot run Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is turned off. It can be turned on in System Settings, Apple Intelligence & Siri."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still getting ready: its model is being downloaded."
        case .unavailable:
            return "Apple Intelligence is not available."
        }
    }

    /// A part of the text that is gone through on its own: a paragraph, or
    /// a few sentences of a long one.
    struct Part: Equatable {
        /// In UTF-16 units, in the text as it was when the parts were found.
        let range: NSRange
    }

    /// The parts of the text worth going through: not code blocks, not empty
    /// lines, not lines of nothing but tags.
    static func parts(of text: String, format: TextFormat) -> [Part] {
        let ns = text as NSString
        var parts: [Part] = []
        var paragraph: NSRange?
        var fence: String?
        func flush() {
            if let range = paragraph { parts += split(range, in: ns) }
            paragraph = nil
        }
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { line, range, _, _ in
            let trimmed = (line ?? "").trimmingCharacters(in: .whitespaces)
            if format == .markdown {
                if let open = fence {
                    if trimmed.hasPrefix(open) { fence = nil }
                    return
                }
                if let match = trimmed.firstMatch(of: #/^(`{3,}|~{3,})/#) {
                    flush()
                    fence = String(match.1)
                    return
                }
            }
            if trimmed.isEmpty {
                flush()
            } else {
                paragraph = paragraph.map { NSUnionRange($0, range) } ?? range
            }
        }
        flush()
        return parts.filter { part in
            var words = ns.substring(with: part.range)
            for tag in format.syntax.tags(in: words).reversed() { words.removeSubrange(tag.range) }
            return words.contains { $0.isLetter || $0.isNumber }
        }
    }

    /// A long paragraph in pieces of whole sentences: the model reads only so
    /// much at once.
    private static func split(_ range: NSRange, in text: NSString) -> [Part] {
        let limit = 1_200
        guard range.length > limit else { return [Part(range: range)] }
        let paragraph = text.substring(with: range)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = paragraph
        var parts: [Part] = []
        var start = 0, end = 0
        for sentence in tokenizer.tokens(for: paragraph.startIndex..<paragraph.endIndex) {
            let sentenceEnd = NSRange(sentence, in: paragraph).upperBound
            if sentenceEnd - start > limit, end > start {
                parts.append(Part(range: NSRange(location: range.location + start, length: end - start)))
                start = end
            }
            end = sentenceEnd
        }
        parts.append(Part(range: NSRange(location: range.location + start, length: range.length - start)))
        return parts
    }

    private static let instructions = """
        You prepare text to be read aloud by a speech synthesizer. Rewrite the text you are given so that it \
        reads well when spoken, and change nothing else.
        - Fix spelling mistakes and typos.
        - Write out abbreviations as the words they stand for: "e.g." becomes "for example", "etc." becomes \
        "and so on", "i.e." becomes "that is", "Dr." becomes "Doctor".
        - Write out mathematical expressions as they are spoken, numbers included: "2*4" becomes "two times \
        four", "x^2" becomes "x squared", "3/4" becomes "three quarters", "a = b + 1" becomes "a equals b plus one".
        - Write out signs that are read as words: "&" becomes "and", "%" becomes "percent", "°C" becomes \
        "degrees Celsius".
        - Keep the language of the text: write the words out in that language.
        - Keep the wording, the sentences and their order. Do not summarise, explain, answer, translate, or add \
        anything.
        - Keep the Markdown marks (#, *, -, >, links) as they are, and keep every marker like ⟦1⟧ exactly as \
        it is, where it is.
        Answer with the rewritten text only.
        """

    /// The part rewritten; nil when the model's answer cannot be trusted --
    /// a marker lost, or much more or less text than given -- and the part is
    /// best left as it was.
    static func prepare(_ part: String, format: TextFormat) async throws -> String? {
        // The tags are put out of the model's reach, as numbered markers.
        var tags: [String] = []
        var protected = ""
        var rest = part[...]
        for tag in format.syntax.tags(in: part) {
            protected += rest[..<tag.range.lowerBound]
            tags.append(String(part[tag.range]))
            protected += "⟦\(tags.count)⟧"
            rest = part[tag.range.upperBound...]
        }
        protected += rest
        let leading = protected.prefix { $0.isWhitespace }, trailing = String(protected.reversed().prefix { $0.isWhitespace }.reversed())
        let core = protected.trimmingCharacters(in: .whitespacesAndNewlines)

        let session = LanguageModelSession(instructions: instructions)
        var answer = try await session.respond(to: core, options: GenerationOptions(samplingMode: .greedy)).content
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard Double(answer.count) >= Double(core.count) * 0.5, Double(answer.count) <= Double(core.count) * 3 + 40
        else { return nil }
        for (index, tag) in tags.enumerated() {
            let marker = "⟦\(index + 1)⟧"
            guard answer.components(separatedBy: marker).count == 2 else { return nil }
            answer = answer.replacingOccurrences(of: marker, with: tag)
        }
        guard !answer.contains("⟦") else { return nil }
        return leading + answer + trailing
    }
}
