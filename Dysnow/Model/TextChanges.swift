import Foundation

/// How a text differs from what it was: the parts changed, added and
/// deleted, word by word, for the editor to show.
enum TextChanges {
    /// One change. Ranges are in UTF-16 units, as the editor counts.
    struct Hunk: Equatable {
        /// Where it is in the text now; empty for a deletion.
        let current: NSRange
        /// Where it was in the original; empty for an addition.
        let original: NSRange
        /// What was there.
        let originalText: String

        var isDeletion: Bool { current.length == 0 }
        var isAddition: Bool { original.length == 0 }
    }

    /// The changes from `original` to `current`, a word, a run of spaces or
    /// a sign at a time, neighbouring ones joined: "e.g." to "for example" is
    /// one change.
    static func hunks(from original: String, to current: String) -> [Hunk] {
        guard original != current else { return [] }
        let old = tokens(original), new = tokens(current)
        // What is the same at both ends is left out of the diff: typing
        // changes little, and the diff is quick on what is left.
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let oldMiddle = Array(old[prefix..<(old.count - suffix)])
        let newMiddle = Array(new[prefix..<(new.count - suffix)])
        let difference = newMiddle.difference(from: oldMiddle)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset + prefix)
            case .insert(let offset, _, _): inserted.insert(offset + prefix)
            }
        }
        let oldStarts = starts(old), newStarts = starts(new)
        var hunks: [Hunk] = []
        var i = prefix, j = prefix
        while i < old.count - suffix || j < new.count - suffix {
            guard removed.contains(i) || inserted.contains(j) else {
                i += 1
                j += 1
                continue
            }
            let oldStart = i, newStart = j
            while removed.contains(i) || inserted.contains(j) {
                if removed.contains(i) { i += 1 }
                if inserted.contains(j) { j += 1 }
            }
            let hunk = Hunk(current: NSRange(location: newStarts[newStart], length: newStarts[j] - newStarts[newStart]),
                            original: NSRange(location: oldStarts[oldStart], length: oldStarts[i] - oldStarts[oldStart]),
                            originalText: old[oldStart..<i].joined())
            // Changes with only a space kept between them are one: "two
            // times four" for "2*4", not three.
            if let last = hunks.last, !last.isDeletion, !hunk.isDeletion,
               let gap = Range(NSRange(location: NSMaxRange(last.current),
                                       length: hunk.current.location - NSMaxRange(last.current)), in: current),
               current[gap].allSatisfy(\.isWhitespace), current[gap].count <= 1 {
                let merged = NSUnionRange(last.original, hunk.original)
                hunks[hunks.count - 1] = Hunk(current: NSUnionRange(last.current, hunk.current), original: merged,
                                              originalText: (original as NSString).substring(with: merged))
            } else {
                hunks.append(hunk)
            }
        }
        return hunks
    }

    /// The original with one change kept: the change is then part of it.
    static func keeping(_ hunk: Hunk, of original: String, current: String) -> String {
        let kept = (current as NSString).substring(with: hunk.current)
        return (original as NSString).replacingCharacters(in: hunk.original, with: kept)
    }

    /// Words (letters and digits), runs of white space, and single other
    /// characters.
    static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var kind = 0
        for character in text {
            let next = character.isLetter || character.isNumber ? 1 : character.isWhitespace ? 2 : 3
            if next != kind || next == 3, !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            current.append(character)
            kind = next
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Where each token starts, in UTF-16 units, and where the last ends.
    private static func starts(_ tokens: [String]) -> [Int] {
        var starts = [0]
        starts.reserveCapacity(tokens.count + 1)
        for token in tokens { starts.append(starts[starts.count - 1] + token.utf16.count) }
        return starts
    }
}
