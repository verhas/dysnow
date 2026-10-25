import Foundation

/// A language an engine speaks: "en-us", "American English".
struct SpeechLanguage: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
}

enum SpeechGender: String, CaseIterable, Sendable, Identifiable {
    case female, male

    var id: String { rawValue }

    var title: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        }
    }
}

/// One of an engine's voices. The id is the engine's own name for it, unique
/// within that engine.
struct SpeechVoice: Hashable, Sendable, Identifiable {
    let id: String
    /// "Liam", for the speaker picker.
    let name: String
    /// The name as the voice says it in its own language, when it is written
    /// otherwise there: "晓晓" for Xiaoxiao.
    var spokenName: String?
    let gender: SpeechGender
    let languageID: String
}

/// Mono speech samples, from -1 to 1.
struct SynthesizedAudio: Sendable {
    var samples: [Float]
    let sampleRate: Int

    var duration: TimeInterval { Double(samples.count) / Double(sampleRate) }
}

/// Something that turns text into speech. Kokoro is the first; others will
/// follow, each a type of its own behind this.
protocol SpeechEngine: AnyObject, Sendable {
    /// Kept in the settings: "kokoro".
    var id: String { get }
    /// Shown in the engine picker: "Kokoro".
    var name: String { get }
    var languages: [SpeechLanguage] { get }
    func voices(for language: SpeechLanguage) -> [SpeechVoice]
    /// False while what the engine needs -- a model, say -- is not there yet.
    var isAvailable: Bool { get }
    /// Whether this voice can speak: an engine whose voices are downloaded
    /// one by one says so per voice.
    func isAvailable(_ voice: SpeechVoice) -> Bool
    /// Blocks until the speech is made: called off the main thread.
    func synthesize(_ text: String, voice: SpeechVoice, language: SpeechLanguage,
                    speed: Float) throws -> SynthesizedAudio
}

extension SpeechEngine {
    func isAvailable(_ voice: SpeechVoice) -> Bool { isAvailable }
}

enum SpeechError: LocalizedError {
    case unavailable(String)
    case unknownVoice(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let engine): "\(engine) is not ready: its voice model is not installed."
        case .unknownVoice(let voice): "There is no voice called \(voice)."
        case .failed(let reason): reason
        }
    }
}
