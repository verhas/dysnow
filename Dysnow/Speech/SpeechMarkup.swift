import Foundation

/// How a piece of text is to be read, set by markup in the text.
struct SpeechStyle: Hashable, Sendable {
    /// "excited", "sad": lowercased, as written.
    var mood: String?
    /// A speaker's name, "Fable", or the engine's id for it, "bm_fable".
    var speaker: String?
    /// A factor on the speed chosen in the app.
    var speed: Double = 1
    /// The language it is read in, by id or name, "de" or "German", when it
    /// is not the one chosen in the app.
    var language: String?
    /// The model that reads it, by id or name, "piper" or "Piper", when it is
    /// not the one chosen in the app.
    var model: String?
}

/// The markup that sets how text is read, written as the text's format
/// writes it (see `MarkupSyntax`); in Markdown, HTML comments, so a Markdown
/// viewer shows nothing of them.
///
///     <!-- tts:mood value="excited" --> ... <!-- /tts:mood -->
///     <!-- tts:speaker value="Fable" --> ... <!-- /tts:speaker -->
///     <!-- tts:speed value="1.2" --> ... <!-- /tts:speed -->
///     <!-- tts:language value="German" --> ... <!-- /tts:language -->
///     <!-- tts:set language="hu" model="Piper" speaker="Anna" speed="" mood="" -->
///
/// They may wrap a few words or many paragraphs, and nest: the innermost
/// mood, speaker and language win, speeds multiply. A speed is a factor,
/// "1.2" or "120%", on the speed chosen in the app. `set` changes what its
/// attributes say -- one left out or empty changes nothing -- from there on,
/// until another `set` changes it again or its own closing tag ends it; its
/// speed replaces the one before instead of multiplying it.
enum SpeechMarkup {
    /// The moods every engine shows in some way, in groups read alike.
    static let moodGroups = [
        ["excited", "enthusiastic", "thrilled"], ["happy", "cheerful", "joyful", "glad"],
        ["angry", "annoyed", "furious"], ["fearful", "nervous", "anxious", "scared"],
        ["sad", "melancholic", "sorrowful"], ["calm", "gentle", "tender", "relaxed", "soothing"],
        ["serious", "solemn", "formal"], ["tired", "sleepy", "bored"],
    ]

    /// The moods offered when writing a tag: the first of each group first.
    static let moods = moodGroups.map { $0[0] } + moodGroups.flatMap { $0.dropFirst() }

    /// The first mood of the group a mood is in, "excited" for "thrilled";
    /// the mood itself when it is in none.
    static func prosodyGroup(of mood: String) -> String {
        moodGroups.first { $0.contains(mood) }?[0] ?? mood
    }

    /// The tags open at some point of the text.
    struct State: Equatable, Sendable {
        /// What one open tag changes.
        private struct Frame: Equatable, Sendable {
            let kind: String
            var mood: String?
            var speaker: String?
            var speed: Double?
            var language: String?
            var model: String?
        }

        /// In the order they were opened.
        private var frames: [Frame] = []

        var style: SpeechStyle {
            var style = SpeechStyle()
            for frame in frames {
                if let mood = frame.mood { style.mood = mood }
                if let speaker = frame.speaker { style.speaker = speaker }
                if let language = frame.language { style.language = language }
                if let model = frame.model { style.model = model }
                if let speed = frame.speed { style.speed = frame.kind == "set" ? speed : style.speed * speed }
            }
            return style
        }

        /// Opens or closes a tag; tags of other kinds are left alone. A
        /// closing tag closes the last open one of its kind.
        mutating func apply(closing: Bool, kind: String, attributes: [String: String]) {
            let kind = kind.lowercased()
            guard MarkupSyntax.kinds.contains(kind) else { return }
            if closing {
                if let index = frames.lastIndex(where: { $0.kind == kind }) { frames.remove(at: index) }
                return
            }
            // An empty value changes nothing.
            func value(_ name: String) -> String? {
                attributes[name].map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
            }
            var frame = Frame(kind: kind)
            switch kind {
            case "mood": frame.mood = value("value")?.lowercased()
            case "speaker": frame.speaker = value("value")
            // One that cannot be read changes nothing, but is still the one
            // its closing tag closes.
            case "speed": frame.speed = value("value").flatMap(SpeechMarkup.speed)
            case "language": frame.language = value("value")
            default:
                frame.mood = value("mood")?.lowercased()
                frame.speaker = value("speaker")
                frame.speed = value("speed").flatMap(SpeechMarkup.speed)
                frame.language = value("language")
                frame.model = value("model")
            }
            frames.append(frame)
        }

        /// The same with a single value, as most tags have it.
        mutating func apply(closing: Bool, kind: String, value: String?) {
            apply(closing: closing, kind: kind, attributes: value.map { ["value": $0] } ?? [:])
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
/// An engine that speaks in the user's own voices, from My Voices.
protocol SpeaksInOwnVoices: SpeechEngine {}

protocol MoodAwareEngine: SpeechEngine {
    /// Whether the voice can be told this mood; when not, it is shown in
    /// pace and pauses as for other engines.
    func knows(mood: String, for voice: SpeechVoice) -> Bool
    func synthesize(_ text: String, voice: SpeechVoice, language: SpeechLanguage, speed: Float,
                    mood: String) async throws -> SynthesizedAudio
}

extension MoodAwareEngine {
    func knows(mood: String, for voice: SpeechVoice) -> Bool { true }
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

    /// The language a `tts:language` tag names, by id or name, ignoring
    /// case: "de", "German"; "English" is the first English one.
    func language(named name: String) -> SpeechLanguage? {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return nil }
        return languages.first { $0.id.lowercased() == wanted || $0.name.lowercased() == wanted }
            ?? languages.first { $0.id.lowercased().hasPrefix(wanted + "-") || $0.name.lowercased().hasPrefix(wanted + " ") }
    }
}
