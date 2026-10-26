import Foundation

/// What to say and how: the same request makes the same speech.
struct SpeechRequest: Equatable, Sendable {
    let engineID: String
    let language: SpeechLanguage
    let voice: SpeechVoice
    let speed: Float
    let blocks: [SpokenBlock]
    /// The engines' settings it was made with: `SpeechEngine.speechSettings`.
    var settings = ""
}

/// Every engine the app has, in the order they are offered.
enum SpeechEngines {
    static let all: [any SpeechEngine] = [KokoroEngine.shared, PiperEngine.shared]
        + (Qwen3Engine.isSupported ? [Qwen3Engine.shared] : []) + [CloningEngine.zipVoice, CloningEngine.pocket]
        + [XTTSEngine.shared]
}

/// Makes speech piece by piece, for playing and for saving alike.
enum Synthesizer {
    /// One call to an engine: a sentence or a few, read in one way.
    private struct Piece: Sendable {
        let text: String
        let engine: any SpeechEngine
        let voice: SpeechVoice
        let language: SpeechLanguage
        let speed: Float
        /// For an engine that can be told it.
        let mood: String?
        /// The silence after it, in seconds.
        let pause: Double
    }

    /// Who reads a run: the engine, in which language, in which voice.
    struct Reader {
        let engine: any SpeechEngine
        let language: SpeechLanguage
        let voice: SpeechVoice
    }

    /// What in the markup could not be followed.
    enum Problem: Hashable {
        case speaker(String), language(String), model(String)
        /// The model has no voice there to speak the language.
        case noVoice(model: String, language: String)
    }

    /// Makes the speech off the main thread, handing each piece over as soon
    /// as it is made with how much of the text is done, from 0 to 1. Each
    /// run of a block is cut into sentences, read by its model, in its
    /// speaker's voice, in its language, at its speed, in its mood; the
    /// block's pause comes after its last. `engine` is the one chosen in the
    /// app; `engines` the others markup may switch to. Pieces of engines that
    /// make speech at other rates are converted to the rate of the first.
    /// Cancelling the calling task stops it between pieces.
    @MainActor
    static func synthesize(
        _ request: SpeechRequest, with engine: any SpeechEngine, engines: [any SpeechEngine] = [],
        piece: @MainActor (Double, SynthesizedAudio) throws -> Void = { _, _ in }
    ) async throws -> SynthesizedAudio {
        let pieces = Self.pieces(of: request, for: engine, engines: engines)
        var samples: [Float] = []
        var sampleRate = 0
        for (index, next) in pieces.enumerated() {
            try Task.checkCancellation()
            var audio = try await Task.detached(priority: .userInitiated) {
                if let mood = next.mood, let engine = next.engine as? any MoodAwareEngine {
                    return try await engine.synthesize(next.text, voice: next.voice, language: next.language,
                                                       speed: next.speed, mood: mood)
                }
                return try await next.engine.synthesize(next.text, voice: next.voice, language: next.language,
                                                        speed: next.speed)
            }.value
            try Task.checkCancellation()
            if sampleRate == 0 {
                sampleRate = audio.sampleRate
            } else if audio.sampleRate != sampleRate {
                audio = try AudioImporter.resampled(audio, to: sampleRate)
            }
            audio.samples += repeatElement(0, count: Int(next.pause * Double(audio.sampleRate)))
            samples += audio.samples
            try piece(Double(index + 1) / Double(pieces.count), audio)
        }
        return SynthesizedAudio(samples: samples, sampleRate: sampleRate)
    }

    /// Who reads a run of this style, and what of its markup could not be
    /// followed. A model named is used when there is one of that name. A
    /// language the model does not speak is looked for in the other models,
    /// unless the markup named the model: the first with a voice there to
    /// speak it reads it. A speaker named is looked for in the model; without
    /// one, the chosen voice reads when the model is the chosen one, else the
    /// model's first voice of the chosen voice's gender.
    static func reader(for style: SpeechStyle, in request: SpeechRequest, engine main: any SpeechEngine,
                       engines: [any SpeechEngine] = []) -> (reader: Reader, problems: [Problem]) {
        let all = [main] + engines.filter { $0.id != main.id }
        let chosen = Reader(engine: main, language: request.language, voice: request.voice)
        var problems: [Problem] = []
        var engine = main
        var modelNamed = false
        if let name = style.model {
            if let named = all.first(where: { matches(name, $0) }) {
                engine = named
                modelNamed = true
            } else {
                problems.append(.model(name))
            }
        }
        var language: SpeechLanguage?
        if let name = style.language {
            if let own = engine.language(named: name) {
                language = own
            } else if !modelNamed, let other = all.lazy.compactMap({ candidate -> (any SpeechEngine, SpeechLanguage)? in
                guard let found = candidate.language(named: name),
                      candidate.voices(for: found).contains(where: candidate.isAvailable) else { return nil }
                return (candidate, found)
            }).first {
                engine = other.0
                language = other.1
            } else {
                problems.append(.language(name))
            }
        }
        // A model switched to that does not speak the chosen language speaks
        // its first.
        guard let language = language ?? engine.languages.first(where: { $0.id == request.language.id })
            ?? engine.languages.first else { return (chosen, problems) }
        var voice: SpeechVoice?
        if let name = style.speaker {
            voice = engine.voice(named: name, preferring: language).flatMap { engine.isAvailable($0) ? $0 : nil }
            if voice == nil { problems.append(.speaker(name)) }
        }
        if voice == nil {
            if engine.id == main.id {
                voice = request.voice
            } else {
                let there = engine.voices(for: language).filter(engine.isAvailable)
                voice = there.first { $0.gender == request.voice.gender } ?? there.first
            }
        }
        guard let voice else {
            problems.append(.noVoice(model: engine.name, language: language.name))
            return (chosen, problems)
        }
        return (Reader(engine: engine, language: language, voice: voice), problems)
    }

    /// A model's name or id, ignoring case: "piper", "Qwen3-TTS"; or the
    /// start of it, "qwen".
    private static func matches(_ name: String, _ engine: any SpeechEngine) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        return [engine.id.lowercased(), engine.name.lowercased()].contains { $0 == wanted || $0.hasPrefix(wanted) }
            && !wanted.isEmpty
    }

    /// What in the request's markup could not be followed, each once.
    static func problems(in request: SpeechRequest, for engine: any SpeechEngine,
                         engines: [any SpeechEngine] = []) -> [Problem] {
        var seen = Set<SpeechStyle>(), found: [Problem] = []
        for style in request.blocks.flatMap(\.runs).map(\.style) where seen.insert(style).inserted {
            for problem in reader(for: style, in: request, engine: engine, engines: engines).problems
            where !found.contains(problem) {
                found.append(problem)
            }
        }
        return found
    }

    /// The speakers named in tags that there is no voice of.
    static func unknownSpeakers(in request: SpeechRequest, for engine: any SpeechEngine,
                                engines: [any SpeechEngine] = []) -> [String] {
        problems(in: request, for: engine, engines: engines).compactMap {
            if case .speaker(let name) = $0 { name } else { nil }
        }
    }

    /// The languages named in tags that no model speaks.
    static func unknownLanguages(in request: SpeechRequest, for engine: any SpeechEngine,
                                 engines: [any SpeechEngine] = []) -> [String] {
        problems(in: request, for: engine, engines: engines).compactMap {
            if case .language(let name) = $0 { name } else { nil }
        }
    }

    private static func pieces(of request: SpeechRequest, for main: any SpeechEngine,
                               engines: [any SpeechEngine]) -> [Piece] {
        var pieces: [Piece] = []
        for block in request.blocks {
            for (runIndex, run) in block.runs.enumerated() {
                let style = run.style
                let reader = reader(for: style, in: request, engine: main, engines: engines).reader
                // Told to the engine, or shown in pace and pauses.
                let moodAware = reader.engine as? any MoodAwareEngine
                let toldMoods = style.mood.map { moodAware?.knows(mood: $0, for: reader.voice) ?? false } ?? false
                let prosody = toldMoods ? SpeechMarkup.Prosody() : SpeechMarkup.prosody(for: style.mood)
                let speed = min(max(Double(request.speed) * style.speed * prosody.speed, 0.25), 4)
                let chunks = reader.engine.longestPiece(in: reader.language).map {
                    TextChunker.packed(run.text, maximumLength: $0, quickStart: pieces.isEmpty)
                } ?? TextChunker.chunks(run.text)
                let lastRun = runIndex == block.runs.count - 1
                for (index, chunk) in chunks.enumerated() {
                    let last = lastRun && index == chunks.count - 1
                    pieces.append(Piece(text: chunk, engine: reader.engine, voice: reader.voice,
                                        language: reader.language, speed: Float(speed),
                                        mood: toldMoods ? style.mood : nil,
                                        pause: last ? block.pauseAfter * prosody.pauseScale : prosody.sentencePause))
                }
            }
        }
        return pieces
    }
}
