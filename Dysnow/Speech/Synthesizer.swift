import Foundation

/// What to say and how: the same request makes the same speech.
struct SpeechRequest: Equatable, Sendable {
    let engineID: String
    let language: SpeechLanguage
    let voice: SpeechVoice
    let speed: Float
    let blocks: [SpokenBlock]
}

/// Makes speech piece by piece, for playing and for saving alike.
enum Synthesizer {
    /// One call to the engine: a sentence or a few, read in one way.
    private struct Piece: Sendable {
        let text: String
        let voice: SpeechVoice
        let speed: Float
        /// For an engine that can be told it.
        let mood: String?
        /// The silence after it, in seconds.
        let pause: Double
    }

    /// Makes the speech off the main thread, handing each piece over as soon
    /// as it is made with how much of the text is done, from 0 to 1. Each
    /// run of a block is cut into sentences, read in its speaker's voice, at
    /// its speed, in its mood; the block's pause comes after its last.
    /// Cancelling the calling task stops it between pieces.
    @MainActor
    static func synthesize(
        _ request: SpeechRequest, with engine: any SpeechEngine,
        piece: @MainActor (Double, SynthesizedAudio) throws -> Void = { _, _ in }
    ) async throws -> SynthesizedAudio {
        let pieces = Self.pieces(of: request, for: engine)
        var samples: [Float] = []
        var sampleRate = 0
        for (index, next) in pieces.enumerated() {
            try Task.checkCancellation()
            var audio = try await Task.detached(priority: .userInitiated) {
                if let mood = next.mood, let engine = engine as? any MoodAwareEngine {
                    return try engine.synthesize(next.text, voice: next.voice, language: request.language,
                                                 speed: next.speed, mood: mood)
                }
                return try engine.synthesize(next.text, voice: next.voice, language: request.language,
                                             speed: next.speed)
            }.value
            try Task.checkCancellation()
            audio.samples += repeatElement(0, count: Int(next.pause * Double(audio.sampleRate)))
            samples += audio.samples
            sampleRate = audio.sampleRate
            try piece(Double(index + 1) / Double(pieces.count), audio)
        }
        return SynthesizedAudio(samples: samples, sampleRate: sampleRate)
    }

    /// The speakers named in tags that the engine has no voice of.
    static func unknownSpeakers(in request: SpeechRequest, for engine: any SpeechEngine) -> [String] {
        var seen = Set<String>()
        return request.blocks.flatMap(\.runs).compactMap(\.style.speaker).filter {
            engine.voice(named: $0, preferring: request.language) == nil && seen.insert($0.lowercased()).inserted
        }
    }

    private static func pieces(of request: SpeechRequest, for engine: any SpeechEngine) -> [Piece] {
        let toldMoods = engine is any MoodAwareEngine
        var pieces: [Piece] = []
        for block in request.blocks {
            for (runIndex, run) in block.runs.enumerated() {
                let style = run.style
                let voice = style.speaker.flatMap { engine.voice(named: $0, preferring: request.language) }
                    ?? request.voice
                // Told to the engine, or shown in pace and pauses.
                let prosody = toldMoods ? SpeechMarkup.Prosody() : SpeechMarkup.prosody(for: style.mood)
                let speed = min(max(Double(request.speed) * style.speed * prosody.speed, 0.25), 4)
                let chunks = TextChunker.chunks(run.text)
                let lastRun = runIndex == block.runs.count - 1
                for (index, chunk) in chunks.enumerated() {
                    let last = lastRun && index == chunks.count - 1
                    pieces.append(Piece(text: chunk, voice: voice, speed: Float(speed),
                                        mood: toldMoods ? style.mood : nil,
                                        pause: last ? block.pauseAfter * prosody.pauseScale : prosody.sentencePause))
                }
            }
        }
        return pieces
    }
}
