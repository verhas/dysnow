import NaturalLanguage

/// Cuts text into pieces to be spoken one after the other: playback starts
/// as soon as the first is made, while the rest are still being made.
enum TextChunker {
    /// Whole sentences, short ones joined to the next until a piece is at
    /// least `minimumLength` long; a sentence longer than `maximumLength` is
    /// cut between words, or anywhere in a script without spaces.
    static func chunks(_ text: String, minimumLength: Int = 40, maximumLength: Int = 400) -> [String] {
        var chunks: [String] = []
        var current = ""
        for sentence in sentences(of: text).flatMap({ split($0, maximumLength: maximumLength) }) {
            current = current.isEmpty ? sentence : current + " " + sentence
            if current.count >= minimumLength {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// As many whole sentences as fit in `maximumLength` a piece, for a
    /// model that ends what it is given abruptly but makes the pauses
    /// between the sentences of a piece itself: XTTS. With `quickStart`, the
    /// first piece is short, as `chunks` makes them, for playback to start.
    static func packed(_ text: String, maximumLength: Int, quickStart: Bool = false) -> [String] {
        var chunks: [String] = []
        var current = ""
        var starting = quickStart
        for sentence in sentences(of: text).flatMap({ split($0, maximumLength: maximumLength) }) {
            let full = current.count + 1 + sentence.count > maximumLength
            if !current.isEmpty, full || starting && current.count >= 40 {
                chunks.append(current)
                current = ""
                starting = false
            }
            current = current.isEmpty ? sentence : current + " " + sentence
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func sentences(of text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }
        return sentences
    }

    private static func split(_ sentence: String, maximumLength: Int) -> [String] {
        guard sentence.count > maximumLength else { return [sentence] }
        var pieces: [String] = []
        var current = ""
        for word in sentence.split(separator: " ", omittingEmptySubsequences: true) {
            if !current.isEmpty, current.count + 1 + word.count > maximumLength {
                pieces.append(current)
                current = ""
            }
            current = current.isEmpty ? String(word) : current + " " + word
            while current.count > maximumLength {
                pieces.append(String(current.prefix(maximumLength)))
                current = String(current.dropFirst(maximumLength))
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}
