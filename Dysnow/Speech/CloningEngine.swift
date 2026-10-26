import Foundation
import SherpaOnnx

/// A model that has no voices of its own: it speaks in the voice of a
/// recording, the user's voices. Both run through sherpa-onnx.
enum CloningModel: String, CaseIterable, Sendable {
    /// Chinese and English; wants to know what is said in the recording.
    case zipVoice = "zipvoice"
    /// English only; small and quick.
    case pocket

    var name: String {
        switch self {
        case .zipVoice: "ZipVoice"
        case .pocket: "Pocket TTS"
        }
    }

    var package: ModelPackage {
        switch self {
        case .zipVoice: release("sherpa-onnx-zipvoice-distill-int8-zh-en-emilia",
                                "77219c8b40f4ee8d73a7f902305ff6c1128ef9b54461c41b4ca6ed890b6c2803", megabytes: 104)
        case .pocket: release("sherpa-onnx-pocket-tts-int8-2026-01-26",
                              "2f3b88823cbbb9bf0b2477ec8ae7b3fec417b3a87b6bb5f256dba66f2ad967cb", megabytes: 94)
        }
    }

    /// A file the model needs that is published apart from it: ZipVoice's
    /// vocoder, which turns what it makes into sound. It is put in the
    /// model's folder.
    var extraFile: ModelFile? {
        switch self {
        case .zipVoice: ModelFile(
            url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/vocoder-models/vocos_24khz.onnx")!,
            sha256: "bcb3b970e384161c4d634f0bb9e999ff1c471b34c9bc0b1049a5014065ed3cc0", megabytes: 52)
        case .pocket: nil
        }
    }

    var megabytes: Int { package.megabytes + (extraFile?.megabytes ?? 0) }

    /// What the folder must hold for the model to load.
    var files: [String] {
        switch self {
        case .zipVoice: ["encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt", "lexicon.txt", "espeak-ng-data",
                         "vocos_24khz.onnx"]
        case .pocket: ["lm_flow.int8.onnx", "lm_main.int8.onnx", "encoder.onnx", "decoder.int8.onnx",
                       "text_conditioner.onnx", "vocab.json", "token_scores.json"]
        }
    }

    var languages: [SpeechLanguage] {
        let english = [SpeechLanguage(id: "en-us", name: "English (US)"),
                       SpeechLanguage(id: "en-gb", name: "English (UK)")]
        switch self {
        case .zipVoice: return english + [SpeechLanguage(id: "zh", name: "Chinese (Mandarin)")]
        case .pocket: return english
        }
    }

    /// Whether the model needs the words of the recording.
    var needsTranscript: Bool { self == .zipVoice }

    /// What the user should know about using it, shown in the settings.
    var note: String? {
        switch self {
        case .zipVoice: nil
        case .pocket: "Its makers allow it for non-commercial use only."
        }
    }

    /// Where the model goes unless the user picks another folder.
    var defaultDirectory: URL {
        DysnowHome.root.appending(path: "voices/\(package.folderName)", directoryHint: .isDirectory)
    }

    /// The settings key of the folder the user picked; absent for the default.
    var directoryKey: String { "\(rawValue).modelDirectory" }

    var directory: URL {
        UserDefaults.standard.string(forKey: directoryKey).map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? defaultDirectory
    }

    func holdsModel(_ folder: URL) -> Bool {
        files.allSatisfy { FileManager.default.fileExists(atPath: folder.appending(path: $0).path) }
    }

    private func release(_ name: String, _ sha256: String, megabytes: Int) -> ModelPackage {
        ModelPackage(url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/\(name).tar.bz2")!,
                     sha256: sha256, megabytes: megabytes)
    }
}

/// ZipVoice or Pocket TTS, speaking in the user's voices. A voice with a
/// recording of a mood speaks in that mood: it is told by example.
final class CloningEngine: MoodAwareEngine, SpeaksInOwnVoices, @unchecked Sendable {
    static let zipVoice = CloningEngine(model: .zipVoice)
    static let pocket = CloningEngine(model: .pocket)

    static func shared(_ model: CloningModel) -> CloningEngine {
        switch model {
        case .zipVoice: zipVoice
        case .pocket: pocket
        }
    }

    let model: CloningModel
    let library: MyVoiceLibrary
    /// The model folder; nil to use the one in the settings.
    private let directory: URL?
    private var loaded: OpaquePointer?
    /// One generation at a time: the model is not shared between threads.
    private let lock = NSLock()

    init(model: CloningModel, directory: URL? = nil, library: MyVoiceLibrary = .shared) {
        self.model = model
        self.directory = directory
        self.library = library
    }

    deinit {
        loaded.map(SherpaOnnxDestroyOfflineTts)
    }

    var id: String { model.rawValue }
    var name: String { model.name }
    var languages: [SpeechLanguage] { model.languages }

    private var folder: URL { directory ?? model.directory }

    var isAvailable: Bool { model.holdsModel(folder) }

    func isAvailable(_ voice: SpeechVoice) -> Bool {
        isAvailable && library.voice(withID: voice.id) != nil
    }

    /// The user's voices, every one in every language: the accent is the
    /// recording's.
    func voices(for language: SpeechLanguage) -> [SpeechVoice] {
        guard languages.contains(language) else { return [] }
        return library.voices.map { $0.speechVoice(languageID: language.id) }
    }

    func knows(mood: String, for voice: SpeechVoice) -> Bool {
        library.voice(withID: voice.id)?.moods[mood.lowercased()] != nil
    }

    /// Lets go of the loaded model, after it was installed or moved.
    func unload() {
        lock.withLock {
            loaded.map(SherpaOnnxDestroyOfflineTts)
            loaded = nil
        }
    }

    func synthesize(_ text: String, voice: SpeechVoice, language: SpeechLanguage,
                    speed: Float) async throws -> SynthesizedAudio {
        try generate(text, voice: voice, mood: nil, language: language, speed: speed)
    }

    func synthesize(_ text: String, voice: SpeechVoice, language: SpeechLanguage, speed: Float,
                    mood: String) async throws -> SynthesizedAudio {
        try generate(text, voice: voice, mood: mood, language: language, speed: speed)
    }

    /// Blocks while the model works; one generation at a time.
    private func generate(_ text: String, voice: SpeechVoice, mood: String?, language: SpeechLanguage,
                          speed: Float) throws -> SynthesizedAudio {
        let reference = try library.reference(for: voice.id, mood: mood)
        if model.needsTranscript, reference.transcript.trimmingCharacters(in: .whitespaces).isEmpty {
            throw SpeechError.failed("\(name) needs the words said in \(voice.name)'s recording: "
                + "write them in Settings, My Voices.")
        }
        let spelled = NumberSpeller.spell(text, languageID: language.id)
        lock.lock()
        defer { lock.unlock() }
        let tts = try loadedModel()
        let sampleRate = Int(SherpaOnnxOfflineTtsSampleRate(tts))
        let audio: UnsafePointer<SherpaOnnxGeneratedAudio>? = reference.audio.samples.withUnsafeBufferPointer { samples in
            reference.transcript.withCString { transcript in
                // The reference is cut to this many seconds, at most.
                "{\"max_reference_audio_len\": 15.0}".withCString { extra in
                    var generation = SherpaOnnxGenerationConfig()
                    generation.sid = 0
                    // Pocket TTS does not follow it, ZipVoice garbles the
                    // words: the speech is made faster or slower afterwards.
                    generation.speed = 1
                    generation.silence_scale = 0.2
                    generation.reference_audio = samples.baseAddress
                    generation.reference_audio_len = Int32(samples.count)
                    generation.reference_sample_rate = Int32(reference.audio.sampleRate)
                    generation.reference_text = transcript
                    if model == .zipVoice {
                        // What the distilled model is made for.
                        generation.num_steps = 4
                    } else {
                        generation.extra = extra
                    }
                    return spelled.withCString { text in
                        SherpaOnnxOfflineTtsGenerateWithConfig(tts, text, &generation, nil, nil)
                    }
                }
            }
        }
        guard let audio else { throw SpeechError.failed("\(name) could not speak the text.") }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
        let count = Int(audio.pointee.n)
        guard count > 0, let samples = audio.pointee.samples else {
            return SynthesizedAudio(samples: [], sampleRate: sampleRate)
        }
        return try TimeStretch.apply(SynthesizedAudio(samples: Array(UnsafeBufferPointer(start: samples, count: count)),
                                                      sampleRate: sampleRate), rate: speed)
    }

    /// Called with the lock held.
    private func loadedModel() throws -> OpaquePointer {
        if let loaded { return loaded }
        let folder = folder
        guard model.holdsModel(folder) else { throw SpeechError.unavailable(name) }
        let path = { (name: String) in folder.appending(path: name).path }
        // The library copies the configuration: the strings only have to last
        // through the call.
        var owned: [UnsafeMutablePointer<CChar>] = []
        defer { owned.forEach { free($0) } }
        func c(_ text: String) -> UnsafePointer<CChar> {
            let copy = strdup(text)!
            owned.append(copy)
            return UnsafePointer(copy)
        }
        var config = SherpaOnnxOfflineTtsConfig()
        switch model {
        case .zipVoice:
            config.model.zipvoice.tokens = c(path("tokens.txt"))
            config.model.zipvoice.encoder = c(path("encoder.int8.onnx"))
            config.model.zipvoice.decoder = c(path("decoder.int8.onnx"))
            config.model.zipvoice.vocoder = c(path("vocos_24khz.onnx"))
            config.model.zipvoice.data_dir = c(path("espeak-ng-data"))
            config.model.zipvoice.lexicon = c(path("lexicon.txt"))
            // sherpa-onnx's defaults.
            config.model.zipvoice.feat_scale = 0.1
            config.model.zipvoice.t_shift = 0.5
            config.model.zipvoice.target_rms = 0.1
            config.model.zipvoice.guidance_scale = 1.0
        case .pocket:
            config.model.pocket.lm_flow = c(path("lm_flow.int8.onnx"))
            config.model.pocket.lm_main = c(path("lm_main.int8.onnx"))
            config.model.pocket.encoder = c(path("encoder.onnx"))
            config.model.pocket.decoder = c(path("decoder.int8.onnx"))
            config.model.pocket.text_conditioner = c(path("text_conditioner.onnx"))
            config.model.pocket.vocab_json = c(path("vocab.json"))
            config.model.pocket.token_scores_json = c(path("token_scores.json"))
            // A voice and its moods.
            config.model.pocket.voice_embedding_cache_capacity = 16
        }
        config.model.num_threads = KokoroEngine.defaultThreads
        config.model.provider = c("cpu")
        config.rule_fsts = c("")
        config.max_num_sentences = 1
        guard let tts = SherpaOnnxCreateOfflineTts(&config) else {
            throw SpeechError.failed("\(name)'s model could not be loaded.")
        }
        loaded = tts
        return tts
    }
}
