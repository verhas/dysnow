import Foundation

/// How a piece of text is to be read, set by markup in the text.
struct SpeechStyle: Hashable, Sendable {
    /// "excited", "sad": lowercased, as written.
    var mood: String?
    /// A speaker's name, "Fable", or the engine's id for it, "bm_fable".
    var speaker: String?
    /// A factor on the speed chosen in the app.
    var speed: Double = 1
}

/// The markup that sets how text is read: HTML comments, so a Markdown
/// viewer shows nothing of them.
///
///     <!-- tts:mood value="excited" --> ... <!-- /tts:mood -->
///     <!-- tts:speaker value="Fable" --> ... <!-- /tts:speaker -->
///     <!-- tts:speed value="1.2" --> ... <!-- /tts:speed -->
///
/// They may wrap a few words or many paragraphs, and nest: the innermost
/// mood and speaker win, speeds multiply. A speed is a factor, "1.2" or
/// "120%", on the speed chosen in the app.
enum SpeechMarkup {
    /// Groups: the slash of a closing tag, the kind, the value in double or
    /// in single quotes.
    nonisolated(unsafe) static let tag =
        #/<!--\s*(/?)tts:([A-Za-z]+)(?:\s+value\s*=\s*(?:"([^"]*)"|'([^']*)'))?\s*-->/#

    /// The tags open at some point of the text.
    struct State: Equatable, Sendable {
        private var moods: [String] = []
        private var speakers: [String] = []
        private var speeds: [Double] = []

        var style: SpeechStyle {
            SpeechStyle(mood: moods.last, speaker: speakers.last, speed: speeds.reduce(1, *))
        }

        /// Opens or closes a tag; tags of other kinds are left alone.
        mutating func apply(closing: Bool, kind: String, value: String?) {
            let value = value?.trimmingCharacters(in: .whitespaces) ?? ""
            switch kind.lowercased() {
            case "mood":
                if closing { _ = moods.popLast() } else { moods.append(value.lowercased()) }
            case "speaker":
                if closing { _ = speakers.popLast() } else { speakers.append(value) }
            case "speed":
                // One that cannot be read changes nothing, but is still the
                // one its closing tag closes.
                if closing { _ = speeds.popLast() } else { speeds.append(SpeechMarkup.speed(value) ?? 1) }
            default:
                break
            }
        }
    }

    /// "1.2", "1,2" and "120%" are all 1.2.
    static func speed(_ text: String) -> Double? {
        var text = text.replacingOccurrences(of: ",", with: ".")
        var scale = 1.0
        if text.hasSuffix("%") {
            text.removeLast()
            scale = 0.01
        }
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return value * scale
    }

    /// How a mood is told with what every engine has -- the pace, and the
    /// pauses -- for engines that cannot be told the mood itself.
    struct Prosody: Equatable {
        var speed = 1.0
        /// Extra silence after each sentence, in seconds.
        var sentencePause = 0.0
        /// A factor on the pause after a paragraph.
        var pauseScale = 1.0
    }

    static func prosody(for mood: String?) -> Prosody {
        switch mood {
        case "excited", "enthusiastic", "thrilled": Prosody(speed: 1.12, pauseScale: 0.8)
        case "happy", "cheerful", "joyful", "glad": Prosody(speed: 1.06, pauseScale: 0.9)
        case "angry", "annoyed", "furious": Prosody(speed: 1.08, pauseScale: 0.8)
        case "fearful", "nervous", "anxious", "scared": Prosody(speed: 1.1, sentencePause: 0.05, pauseScale: 0.8)
        case "sad", "melancholic", "sorrowful": Prosody(speed: 0.85, sentencePause: 0.25, pauseScale: 1.6)
        case "calm", "gentle", "tender", "relaxed", "soothing": Prosody(speed: 0.92, sentencePause: 0.15,
                                                                        pauseScale: 1.3)
        case "serious", "solemn", "formal": Prosody(speed: 0.94, sentencePause: 0.1, pauseScale: 1.2)
        case "tired", "sleepy", "bored": Prosody(speed: 0.82, sentencePause: 0.3, pauseScale: 1.5)
        default: Prosody()
        }
    }
}

/// An engine that can be told the mood a text is to be read in. The others
/// get it as `SpeechMarkup.prosody`: pace and pauses.
protocol MoodAwareEngine: SpeechEngine {
    func synthesize(_ text: String, voice: SpeechVoice, language: SpeechLanguage, speed: Float,
                    mood: String) throws -> SynthesizedAudio
}

extension SpeechEngine {
    /// The voice a `tts:speaker` tag names: by name or id, ignoring case,
    /// one of the language's own first -- "Alex" is both a Spanish and a
    /// Portuguese voice.
    func voice(named name: String, preferring language: SpeechLanguage) -> SpeechVoice? {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = { (voice: SpeechVoice) in voice.name.lowercased() == wanted || voice.id.lowercased() == wanted }
        if let own = voices(for: language).first(where: matches) { return own }
        for other in languages where other != language {
            if let voice = voices(for: other).first(where: matches) { return voice }
        }
        return nil
    }
}
