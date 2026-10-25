import Foundation
import MLX
import MLXAudioCore
import MLXAudioTTS

/// A size of Qwen3-TTS's CustomVoice model: bigger follows the mood better.
struct Qwen3Variant: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let model: HuggingFaceModel

    static let small = Qwen3Variant(
        id: "0.6b", title: "0.6B: faster",
        model: HuggingFaceModel(repo: "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit",
                                revision: "049ef77fe8816b536193c0c25f9a214d17921282", megabytes: 1_882))
    static let large = Qwen3Variant(
        id: "1.7b", title: "1.7B: follows the mood better",
        model: HuggingFaceModel(repo: "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
                                revision: "41d3337e8b7f2843a75841595fc14e4b9a7a4b96", megabytes: 2_937))
    static let all = [small, large]

    static func withID(_ id: String?) -> Qwen3Variant? {
        all.first { $0.id == id }
    }
}

/// Qwen3-TTS, run on the Mac's GPU through MLX: an engine that can be told
/// the mood, in words. Its nine speakers speak all ten of its languages.
/// Apple silicon only.
final class Qwen3Engine: MoodAwareEngine, @unchecked Sendable {
    static let shared = Qwen3Engine()

    /// MLX runs on Apple silicon's GPU only.
    static var isSupported: Bool {
        #if arch(arm64)
            true
        #else
            false
        #endif
    }

    /// Where the models go unless the user picks another folder: beside the
    /// other engines' models.
    static var defaultDirectory: URL {
        DysnowHome.root.appending(path: "voices", directoryHint: .isDirectory)
    }

    /// The settings keys: the folder the user picked, absent for the default;
    /// the variant chosen.
    static let directoryKey = "qwen3.directory"
    static let variantKey = "qwen3.variant"

    /// The folder holding the models, each in a folder of its own.
    static var directory: URL {
        UserDefaults.standard.string(forKey: directoryKey).map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? defaultDirectory
    }

    static var variant: Qwen3Variant {
        Qwen3Variant.withID(UserDefaults.standard.string(forKey: variantKey)) ?? .small
    }

    static func folder(of variant: Qwen3Variant, in directory: URL = directory) -> URL {
        directory.appending(path: variant.model.folderName, directoryHint: .isDirectory)
    }

    /// Whether the folder has what the model is loaded from.
    static func holdsModel(_ folder: URL) -> Bool {
        ["config.json", "model.safetensors", "speech_tokenizer/model.safetensors", "vocab.json"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path)
        }
    }

    static func isInstalled(_ variant: Qwen3Variant) -> Bool {
        holdsModel(folder(of: variant))
    }

    /// The model's speakers, by its own names, with how they are shown.
    private static let speakers: [(id: String, name: String, gender: SpeechGender)] = [
        ("Vivian", "Vivian", .female), ("Serena", "Serena", .female), ("Ono_Anna", "Ono Anna", .female),
        ("Sohee", "Sohee", .female), ("Ryan", "Ryan", .male), ("Aiden", "Aiden", .male),
        ("Uncle_Fu", "Uncle Fu", .male), ("Eric", "Eric", .male), ("Dylan", "Dylan", .male),
    ]

    /// Dysnow's languages, with the model's name for each.
    private static let languageNames: [(language: SpeechLanguage, model: String)] = [
        (SpeechLanguage(id: "en-us", name: "English (US)"), "english"),
        (SpeechLanguage(id: "en-gb", name: "English (UK)"), "english"),
        (SpeechLanguage(id: "de", name: "German"), "german"),
        (SpeechLanguage(id: "es", name: "Spanish"), "spanish"),
        (SpeechLanguage(id: "fr", name: "French"), "french"),
        (SpeechLanguage(id: "it", name: "Italian"), "italian"),
        (SpeechLanguage(id: "pt-br", name: "Portuguese (Brazil)"), "portuguese"),
        (SpeechLanguage(id: "ru", name: "Russian"), "russian"),
        (SpeechLanguage(id: "ja", name: "Japanese"), "japanese"),
        (SpeechLanguage(id: "ko", name: "Korean"), "korean"),
        (SpeechLanguage(id: "zh", name: "Chinese (Mandarin)"), "chinese"),
    ]

    let id = "qwen3"
    let name = "Qwen3-TTS"
    let languages = Qwen3Engine.isSupported ? Qwen3Engine.languageNames.map(\.language) : []

    /// The model folder; nil to use the one in the settings.
    private let directory: URL?
    private let runner = Runner()

    init(directory: URL? = nil) {
        self.directory = directory
    }

    private var modelFolder: URL {
        directory ?? Self.folder(of: Self.variant)
    }

    var isAvailable: Bool {
        Self.isSupported && Self.holdsModel(modelFolder)
    }

    func voices(for language: SpeechLanguage) -> [SpeechVoice] {
        guard languages.contains(language) else { return [] }
        return Self.speakers.map {
            SpeechVoice(id: $0.id, name: $0.name, gender: $0.gender, languageID: language.id)
        }
    }

    /// Lets go of the loaded model, after another was chosen or it was removed.
    func unload() async {
        await runner.unload()
    }

    func synthesize(_ text: String, voice: SpeechVoice, language: SpeechLanguage,
                    speed: Float) async throws -> SynthesizedAudio {
        try await generate(text, prompt: voice.id, language: language, speed: speed)
    }

    func synthesize(_ text: String, voice: SpeechVoice, language: SpeechLanguage, speed: Float,
                    mood: String) async throws -> SynthesizedAudio {
        // The CustomVoice models take "speaker, instruction".
        try await generate(text, prompt: "\(voice.id), \(Self.instruction(for: mood))", language: language,
                           speed: speed)
    }

    /// What the model is told for a mood: the known ones in a few more
    /// words, another word as "in a … way", a phrase as it is written.
    static func instruction(for mood: String) -> String {
        switch mood {
        case "excited", "enthusiastic", "thrilled": "very excited and energetic"
        case "happy", "cheerful", "joyful", "glad": "happy and cheerful"
        case "angry", "annoyed", "furious": "angry, with a raised voice"
        case "fearful", "nervous", "anxious", "scared": "nervous and afraid"
        case "sad", "melancholic", "sorrowful": "sad and slow, with a heavy heart"
        case "calm", "gentle", "tender", "relaxed", "soothing": "calm and gentle"
        case "serious", "solemn", "formal": "serious and solemn"
        case "tired", "sleepy", "bored": "tired and sleepy"
        default: mood.contains(" ") ? mood : "in a \(mood) way"
        }
    }

    private func generate(_ text: String, prompt: String, language: SpeechLanguage,
                          speed: Float) async throws -> SynthesizedAudio {
        guard Self.isSupported else { throw SpeechError.failed("Qwen3-TTS needs a Mac with Apple silicon.") }
        guard let modelLanguage = Self.languageNames.first(where: { $0.language == language })?.model else {
            throw SpeechError.failed("Qwen3-TTS does not speak \(language.name).")
        }
        let folder = modelFolder
        guard Self.holdsModel(folder) else { throw SpeechError.unavailable(name) }
        let audio = try await runner.generate(text, prompt: prompt, language: modelLanguage, from: folder)
        return try TimeStretch.apply(audio, rate: speed)
    }

    /// Holds the model, and makes sure it does one thing at a time.
    private actor Runner {
        private var loaded: Loaded?

        func unload() {
            loaded = nil
            Memory.clearCache()
        }

        func generate(_ text: String, prompt: String, language: String,
                      from folder: URL) async throws -> SynthesizedAudio {
            if loaded?.folder != folder {
                unload()
                loaded = try await Loaded.load(from: folder)
            }
            guard let loaded else { throw SpeechError.unavailable("Qwen3-TTS") }
            return try await loaded.generate(text, prompt: prompt, language: language)
        }
    }

    /// The model, with the folder it was loaded from. MLXAudio's models are
    /// not marked as safe to share between threads; this one is only ever
    /// used by the `Runner`, one call at a time.
    private final class Loaded: @unchecked Sendable {
        let folder: URL
        private let model: SpeechGenerationModel

        private init(folder: URL, model: SpeechGenerationModel) {
            self.folder = folder
            self.model = model
        }

        static func load(from folder: URL) async throws -> Loaded {
            Loaded(folder: folder, model: try await TTS.loadModel(modelRepo: folder.path))
        }

        func generate(_ text: String, prompt: String, language: String) async throws -> SynthesizedAudio {
            let samples = try await model.generate(text: text, voice: prompt, refAudio: nil, refText: nil,
                                                   language: language)
            return SynthesizedAudio(samples: samples.asArray(Float.self), sampleRate: model.sampleRate)
        }
    }
}
