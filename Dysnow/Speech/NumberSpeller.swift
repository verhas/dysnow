import Foundation

/// Writes the numbers in a text out in words, for engines that stumble on
/// digits: "In 1848" is "In eighteen forty-eight", "3.5" is "three point
/// five", in German "drei Komma fünf". In English a four-digit number that
/// can be a year is read as one.
enum NumberSpeller {
    /// `languageID` is Dysnow's: "en-us", "de".
    static func spell(_ text: String, languageID: String) -> String {
        let locale = Locale(identifier: languageID)
        let english = languageID.hasPrefix("en")
        let decimalSeparator = Character(locale.decimalSeparator ?? ".")
        let groupingSeparator = Character(locale.groupingSeparator ?? ",")
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .spellOut
        // Without the soft hyphens macOS puts into long German numbers as
        // places to break the line: they are not for a voice.
        func words(_ number: Double) -> String? {
            formatter.string(from: number as NSNumber)?.replacingOccurrences(of: "\u{AD}", with: "")
        }

        func spoken(_ number: String) -> String {
            var parts = number.split(separator: decimalSeparator, omittingEmptySubsequences: false)
            // "3.5" in English and "3,5" in German have a decimal part; a
            // number with several of them, "1.2.3", is not one number.
            guard parts.count <= 2 else { return number }
            let fraction = parts.count == 2 ? String(parts.removeLast()) : nil
            let whole = parts[0].filter { $0 != groupingSeparator && $0 != "'" }
            guard whole.allSatisfy(\.isNumber), let integer = Int(whole), fraction?.allSatisfy(\.isNumber) ?? true
            else { return number }
            if let fraction {
                return words(Double("\(integer).\(fraction)") ?? Double(integer)) ?? number
            }
            if english, whole.count == 4, number.count == 4, let year = englishYear(integer) {
                return year
            }
            return words(Double(integer)) ?? number
        }

        // Digits, maybe with separators between them; not inside a word, like
        // "MP3" or "4K". What comes before is matched too, as Swift's regular
        // expressions cannot look behind, and is put back.
        return text.replacing(#/(^|[^\p{L}\d])(\d+(?:[.,']\d+)*)(?![\p{L}\d])/#) { match in
            String(match.1) + spoken(String(match.2))
        }
    }

    /// 1848 as "eighteen forty-eight", 1905 as "nineteen oh five", 1900 as
    /// "nineteen hundred", 2026 as "twenty twenty-six"; 2000 to 2009 as
    /// "two thousand five". Nil for numbers that are not read as years.
    static func englishYear(_ value: Int) -> String? {
        guard (1100...2099).contains(value) else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en-US")
        formatter.numberStyle = .spellOut
        func words(_ number: Int) -> String { formatter.string(from: number as NSNumber) ?? String(number) }
        let century = value / 100, rest = value % 100
        if (2000...2009).contains(value) { return words(value) }
        if rest == 0 { return words(century) + " hundred" }
        if rest < 10 { return words(century) + " oh " + words(rest) }
        return words(century) + " " + words(rest)
    }
}
