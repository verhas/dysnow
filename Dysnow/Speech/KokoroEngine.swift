import Foundation
import SherpaOnnx

/// One of Kokoro's voices: "af_heart" is an American woman's, "bm_george" a
/// British man's. The first letter is the language, the second the sex.
struct KokoroVoice: Hashable, Sendable {
    let name: String
    /// The speaker number in the model.
    let speaker: Int32

    var isFemale: Bool { name.dropFirst().first == "f" }

    var language: KokoroLanguage? {
        KokoroLanguage.all.first { $0.voicePrefix == name.first }
    }

    /// "Heart", for the voice picker.
    var title: String {
        let base = name.split(separator: "_").last.map(String.init) ?? name
        return base.prefix(1).uppercased() + base.dropFirst()
    }

    var speechVoice: SpeechVoice {
        SpeechVoice(id: name, name: title, spokenName: Self.spokenNames[name], gender: isFemale ? .female : .male,
                    languageID: language?.id ?? "")
    }

    /// The names in the script of the voice's language, for it to introduce
    /// itself with: espeak-ng would spell "Gongitsune" out in Japanese.
    private static let spokenNames = [
        "hf_alpha": "अल्फ़ा", "hf_beta": "बीटा", "hm_omega": "ओमेगा", "hm_psi": "साई",
        "jf_alpha": "アルファ", "jf_gongitsune": "ごんぎつね", "jf_nezumi": "ねずみ", "jf_tebukuro": "てぶくろ",
        "jm_kumo": "くも",
        "zf_xiaobei": "小贝", "zf_xiaoni": "小妮", "zf_xiaoxiao": "晓晓", "zf_xiaoyi": "晓伊",
        "zm_yunjian": "云健", "zm_yunxi": "云希", "zm_yunxia": "云夏", "zm_yunyang": "云扬",
    ]

    /// The model's speakers, in its own order: they are 0 to 52.
    static let all: [KokoroVoice] = [
        "af_alloy", "af_aoede", "af_bella", "af_heart", "af_jessica", "af_kore", "af_nicole", "af_nova",
        "af_river", "af_sarah", "af_sky", "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam", "am_michael",
        "am_onyx", "am_puck", "am_santa", "bf_alice", "bf_emma", "bf_isabella", "bf_lily", "bm_daniel", "bm_fable",
        "bm_george", "bm_lewis", "ef_dora", "em_alex", "ff_siwis", "hf_alpha", "hf_beta", "hm_omega", "hm_psi",
        "if_sara", "im_nicola", "jf_alpha", "jf_gongitsune", "jf_nezumi", "jf_tebukuro", "jm_kumo", "pf_dora",
        "pm_alex", "pm_santa", "zf_xiaobei", "zf_xiaoni", "zf_xiaoxiao", "zf_xiaoyi", "zm_yunjian", "zm_yunxi",
        "zm_yunxia", "zm_yunyang",
    ].enumerated().map { KokoroVoice(name: $1, speaker: Int32($0)) }

    static func named(_ name: String) -> KokoroVoice? {
        all.first { $0.name == name }
    }
}

/// A language Kokoro speaks, and how sherpa-onnx is set up for it: the
/// language is part of the model's configuration, so each one is a model
/// loaded of its own.
struct KokoroLanguage: Hashable, Sendable {
    let id: String
    let name: String
    /// The first letter of its voices' names.
    let voicePrefix: Character
    /// The espeak-ng voice file that turns the text into phonemes: "en" is
    /// British English -- there is no file called "en-gb".
    let espeak: String
    /// Pronunciations looked up before espeak-ng is asked, in the model folder.
    var lexicons: [String] = []
    /// Text normalisation rules, in the model folder: numbers and dates.
    var ruleFsts: [String] = []

    var speechLanguage: SpeechLanguage { SpeechLanguage(id: id, name: name) }

    static let all: [KokoroLanguage] = [
        KokoroLanguage(id: "en-us", name: "English (US)", voicePrefix: "a", espeak: "en-us",
                       lexicons: ["lexicon-us-en.txt"]),
        KokoroLanguage(id: "en-gb", name: "English (UK)", voicePrefix: "b", espeak: "en",
                       lexicons: ["lexicon-gb-en.txt"]),
        KokoroLanguage(id: "es", name: "Spanish", voicePrefix: "e", espeak: "es"),
        KokoroLanguage(id: "fr", name: "French", voicePrefix: "f", espeak: "fr"),
        KokoroLanguage(id: "hi", name: "Hindi", voicePrefix: "h", espeak: "hi"),
        KokoroLanguage(id: "it", name: "Italian", voicePrefix: "i", espeak: "it"),
        KokoroLanguage(id: "ja", name: "Japanese", voicePrefix: "j", espeak: "ja"),
        KokoroLanguage(id: "pt-br", name: "Portuguese (Brazil)", voicePrefix: "p", espeak: "pt-br"),
        KokoroLanguage(id: "zh", name: "Chinese (Mandarin)", voicePrefix: "z", espeak: "zh",
                       lexicons: ["lexicon-us-en.txt", "lexicon-zh.txt"],
                       ruleFsts: ["date-zh.fst", "phone-zh.fst", "number-zh.fst"]),
    ]
}

/// Kokoro, an open neural speech model, run on the Mac through sherpa-onnx.
/// The model is downloaded once; making speech takes a fraction of the time
/// it plays for, and is done off the main thread.
final class KokoroEngine: SpeechEngine, @unchecked Sendable {
    static let shared = KokoroEngine()

    /// The model release, from sherpa-onnx's model downloads: the full
    /// precision one, which is five times faster than real time on Apple
    /// silicon where the 8-bit one barely keeps up.
    static let modelName = "kokoro-multi-lang-v1_0"
    static let package = ModelPackage(
        url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/\(modelName).tar.bz2")!,
        sha256: "c5f7e2d2caf082bc1d20fb70334a61d99d20b484500aad32e7cf84c128ea3298",
        megabytes: 350)
    /// About the size of the download, for telling the user.
    static var downloadMegabytes: Int { package.megabytes }

    /// Where the model goes unless the user picks another folder.
    static var defaultDirectory: URL {
        DysnowHome.root.appending(path: "voices/\(modelName)", directoryHint: .isDirectory)
    }

    /// The settings key of the folder the user picked; absent for the default.
    static let directoryKey = "kokoro.modelDirectory"

    /// The model's folder: the one picked in the settings, or the default.
    /// Read from the settings each time, so a folder picked takes effect at
    /// once.
    static var directory: URL {
        UserDefaults.standard.string(forKey: directoryKey).map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? defaultDirectory
    }

    static var isInstalled: Bool { holdsModel(directory) }

    /// Whether the folder has everything the model is loaded from.
    static func holdsModel(_ folder: URL) -> Bool {
        ["model.onnx", "voices.bin", "tokens.txt", "espeak-ng-data"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path)
        }
    }

    /// The performance cores: the efficiency ones only slow it down.
    static var defaultThreads: Int32 {
        var cores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &cores, &size, nil, 0) == 0, cores > 0 {
            return min(cores, 8)
        }
        return Int32(max(2, ProcessInfo.processInfo.activeProcessorCount / 2))
    }

    let id = "kokoro"
    let name = "Kokoro"
    let languages = KokoroLanguage.all.map(\.speechLanguage)

    /// The model folder; nil to use the one in the settings.
    private let directory: URL?
    /// One model per language, loaded the first time it is spoken.
    private var loaded: [String: OpaquePointer] = [:]
    /// One generation at a time: the model is not shared between threads.
    private let lock = NSLock()

    init(directory: URL? = nil) {
        self.directory = directory
    }

    deinit {
        loaded.values.forEach(SherpaOnnxDestroyOfflineTts)
    }

    var isAvailable: Bool {
        Self.holdsModel(directory ?? Self.directory)
    }

    func voices(for language: SpeechLanguage) -> [SpeechVoice] {
        KokoroVoice.all.filter { $0.language?.id == language.id }.map(\.speechVoice)
    }

    /// Lets go of the loaded models, after the model was installed or removed.
    func unload() {
        lock.lock()
        defer { lock.unlock() }
        loaded.values.forEach(SherpaOnnxDestroyOfflineTts)
        loaded = [:]
    }

    func synthesize(_ text: String, voice: SpeechVoice, language: SpeechLanguage,
                    speed: Float) throws -> SynthesizedAudio {
        guard let kokoroVoice = KokoroVoice.named(voice.id) else { throw SpeechError.unknownVoice(voice.id) }
        guard let kokoroLanguage = KokoroLanguage.all.first(where: { $0.id == language.id }) else {
            throw SpeechError.failed("Kokoro does not speak \(language.name).")
        }
        lock.lock()
        defer { lock.unlock() }
        let tts = try model(for: kokoroLanguage)
        let sampleRate = Int(SherpaOnnxOfflineTtsSampleRate(tts))
        var generation = SherpaOnnxGenerationConfig()
        generation.sid = kokoroVoice.speaker
        generation.speed = speed
        generation.silence_scale = 0.2
        guard let audio = text.withCString({ text in
            SherpaOnnxOfflineTtsGenerateWithConfig(tts, text, &generation, nil, nil)
        }) else { throw SpeechError.failed("Kokoro could not speak the text.") }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
        let count = Int(audio.pointee.n)
        guard count > 0, let samples = audio.pointee.samples else {
            return SynthesizedAudio(samples: [], sampleRate: sampleRate)
        }
        return SynthesizedAudio(samples: Array(UnsafeBufferPointer(start: samples, count: count)),
                                sampleRate: sampleRate)
    }

    /// Called with the lock held.
    private func model(for language: KokoroLanguage) throws -> OpaquePointer {
        if let tts = loaded[language.id] { return tts }
        let directory = directory ?? Self.directory
        guard Self.holdsModel(directory) else { throw SpeechError.unavailable(name) }
        let path = { (name: String) in directory.appending(path: name).path }
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
        config.model.kokoro.model = c(path("model.onnx"))
        config.model.kokoro.voices = c(path("voices.bin"))
        config.model.kokoro.tokens = c(path("tokens.txt"))
        config.model.kokoro.data_dir = c(path("espeak-ng-data"))
        config.model.kokoro.lexicon = c(language.lexicons.map(path).joined(separator: ","))
        config.model.kokoro.lang = c(language.espeak)
        config.model.kokoro.length_scale = 1.0
        config.model.num_threads = Self.defaultThreads
        config.model.provider = c("cpu")
        config.rule_fsts = c(language.ruleFsts.map(path).joined(separator: ","))
        config.max_num_sentences = 1
        guard let tts = SherpaOnnxCreateOfflineTts(&config) else {
            throw SpeechError.failed("Kokoro's model for \(language.name) could not be loaded.")
        }
        loaded[language.id] = tts
        return tts
    }
}
