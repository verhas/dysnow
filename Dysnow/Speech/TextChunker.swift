import NaturalLanguage

/// Cuts text into pieces to be spoken one after the other: playback starts
/// as soon as the first is made, while the rest are still being made.
enum TextChunker {
    /// Whole sentences, short ones joined to the next until a piece is at
    /// least `minimumLength` long; a sentence longer than `maximumLength` is
    /// cut between words, or anywhere in a script without spaces.
    static func chunks(_ text: String, minimumLength: Int = 40, maximumLength: Int = 400) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }

        var chunks: [String] = []
        var current = ""
        for sentence in sentences.flatMap({ split($0, maximumLength: maximumLength) }) {
            current = current.isEmpty ? sentence : current + " " + sentence
            if current.count >= minimumLength {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
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
