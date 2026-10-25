import Foundation
import SherpaOnnx

/// One of Piper's voices: a model of its own, downloaded on its own.
struct PiperVoice: Hashable, Sendable {
    /// Piper's name for it, which its model file is named after.
    let id: String
    let name: String
    let gender: SpeechGender
    let language: SpeechLanguage
    let package: ModelPackage

    var speechVoice: SpeechVoice {
        SpeechVoice(id: id, name: name, gender: gender, languageID: language.id)
    }

    static let hungarian = SpeechLanguage(id: "hu", name: "Hungarian")

    /// The voices offered. All three are trained on CC0 recordings.
    static let all: [PiperVoice] = [
        PiperVoice(id: "hu_HU-anna-medium", name: "Anna", gender: .female, language: hungarian,
                   package: release("vits-piper-hu_HU-anna-medium",
                                    "c67b13e57b71eca19098fe499afc35ebce8f63a0b524017c786af2025821216a")),
        PiperVoice(id: "hu_HU-berta-medium", name: "Berta", gender: .female, language: hungarian,
                   package: release("vits-piper-hu_HU-berta-medium",
                                    "a00ba073fa7f8e1b2be58f881b24892e2dca16c3c5979ee4ea4bc6ccdd89dbc0")),
        PiperVoice(id: "hu_HU-imre-medium", name: "Imre", gender: .male, language: hungarian,
                   package: release("vits-piper-hu_HU-imre-medium",
                                    "7be44b928bb26b03e403660894cd8210828dd8a0e9dccc4bade4a1632fc4f8c4")),
    ]

    static func withID(_ id: String) -> PiperVoice? {
        all.first { $0.id == id }
    }

    /// From sherpa-onnx's model downloads, where Kokoro comes from too.
    private static func release(_ name: String, _ sha256: String) -> ModelPackage {
        ModelPackage(url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/\(name).tar.bz2")!,
                     sha256: sha256, megabytes: 64)
    }
}

/// Piper, run through sherpa-onnx: small models of one voice each, for the
/// languages Kokoro does not speak. Hungarian, to begin with.
final class PiperEngine: SpeechEngine, @unchecked Sendable {
    static let shared = PiperEngine()

    /// Where the voices go unless the user picks another folder: beside
    /// Kokoro's model.
    static var defaultDirectory: URL {
        DysnowHome.root.appending(path: "voices", directoryHint: .isDirectory)
    }

    /// The settings key of the folder the user picked; absent for the default.
    static let directoryKey = "piper.directory"

    /// The folder holding the voices, each in a folder of its own.
    static var directory: URL {
        UserDefaults.standard.string(forKey: directoryKey).map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? defaultDirectory
    }

    static func folder(of voice: PiperVoice, in directory: URL = directory) -> URL {
        directory.appending(path: voice.package.folderName, directoryHint: .isDirectory)
    }

    /// Whether the folder has everything the voice is loaded from.
    static func holds(_ voice: PiperVoice, in folder: URL) -> Bool {
        ["\(voice.id).onnx", "tokens.txt", "espeak-ng-data"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path)
        }
    }

    static func isInstalled(_ voice: PiperVoice) -> Bool {
        holds(voice, in: folder(of: voice))
    }

    let id = "piper"
    let name = "Piper"
    let languages: [SpeechLanguage] = {
        var seen = Set<String>()
        return PiperVoice.all.map(\.language).filter { seen.insert($0.id).inserted }
    }()

    /// The folder holding the voices; nil to use the one in the settings.
    private let directory: URL?
    /// One model per voice, loaded the first time it speaks.
    private var loaded: [String: OpaquePointer] = [:]
    /// One generation at a time: a model is not shared between threads.
    private let lock = NSLock()

    init(directory: URL? = nil) {
        self.directory = directory
    }

    deinit {
        loaded.values.forEach(SherpaOnnxDestroyOfflineTts)
    }

    private func folder(of voice: PiperVoice) -> URL {
        Self.folder(of: voice, in: directory ?? Self.directory)
    }

    /// Some voice is there.
    var isAvailable: Bool {
        PiperVoice.all.contains { Self.holds($0, in: folder(of: $0)) }
    }

    func isAvailable(_ voice: SpeechVoice) -> Bool {
        PiperVoice.withID(voice.id).map { Self.holds($0, in: folder(of: $0)) } ?? false
    }

    func voices(for language: SpeechLanguage) -> [SpeechVoice] {
        PiperVoice.all.filter { $0.language == language }.map(\.speechVoice)
    }

    /// Lets go of the loaded models, after voices were installed or removed.
    func unload() {
        lock.lock()
        defer { lock.unlock() }
        loaded.values.forEach(SherpaOnnxDestroyOfflineTts)
        loaded = [:]
    }

    func synthesize(_ text: String, voice: SpeechVoice, language: SpeechLanguage,
                    speed: Float) async throws -> SynthesizedAudio {
        try generate(text, voice: voice, language: language, speed: speed)
    }

    /// Blocks while the model works; one generation at a time.
    private func generate(_ text: String, voice: SpeechVoice, language: SpeechLanguage,
                          speed: Float) throws -> SynthesizedAudio {
        guard let piperVoice = PiperVoice.withID(voice.id) else { throw SpeechError.unknownVoice(voice.id) }
        lock.lock()
        defer { lock.unlock() }
        let tts = try model(for: piperVoice)
        let sampleRate = Int(SherpaOnnxOfflineTtsSampleRate(tts))
        var generation = SherpaOnnxGenerationConfig()
        generation.sid = 0
        generation.speed = speed
        generation.silence_scale = 0.2
        guard let audio = text.withCString({ text in
            SherpaOnnxOfflineTtsGenerateWithConfig(tts, text, &generation, nil, nil)
        }) else { throw SpeechError.failed("Piper could not speak the text.") }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
        let count = Int(audio.pointee.n)
        guard count > 0, let samples = audio.pointee.samples else {
            return SynthesizedAudio(samples: [], sampleRate: sampleRate)
        }
        return SynthesizedAudio(samples: Array(UnsafeBufferPointer(start: samples, count: count)),
                                sampleRate: sampleRate)
    }

    /// Called with the lock held.
    private func model(for voice: PiperVoice) throws -> OpaquePointer {
        if let tts = loaded[voice.id] { return tts }
        let folder = folder(of: voice)
        guard Self.holds(voice, in: folder) else {
            throw SpeechError.failed("\(voice.name)'s voice is not downloaded yet.")
        }
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
        config.model.vits.model = c(path("\(voice.id).onnx"))
        config.model.vits.tokens = c(path("tokens.txt"))
        config.model.vits.data_dir = c(path("espeak-ng-data"))
        config.model.vits.lexicon = c("")
        // Piper's own defaults.
        config.model.vits.noise_scale = 0.667
        config.model.vits.noise_scale_w = 0.8
        config.model.vits.length_scale = 1.0
        config.model.num_threads = KokoroEngine.defaultThreads
        config.model.provider = c("cpu")
        config.rule_fsts = c("")
        config.max_num_sentences = 1
        guard let tts = SherpaOnnxCreateOfflineTts(&config) else {
            throw SpeechError.failed("\(voice.name)'s voice could not be loaded.")
        }
        loaded[voice.id] = tts
        return tts
    }
}
