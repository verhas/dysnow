import Foundation
import SherpaOnnx

/// One of Piper's models, as sherpa-onnx publishes it: a download of its
/// own, of one voice or a few. All of them are in `PiperCatalog.swift`.
struct PiperModel: Hashable, Sendable, Identifiable {
    /// Piper's name for it, which its model file is named after:
    /// "hu_HU-anna-medium".
    let id: String
    let language: SpeechLanguage
    /// "x_low", "low", "medium" or "high"; empty when the name does not say.
    let quality: String
    let package: ModelPackage
    /// What its model card says of its licence: for information only.
    let licence: String
    /// Its model card, or where it comes from.
    let source: URL

    init(id: String, language: SpeechLanguage, quality: String, sha256: String, megabytes: Int,
         licence: String, source: String) {
        self.id = id
        self.language = language
        self.quality = quality
        package = ModelPackage(
            url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-\(id).tar.bz2")!,
            sha256: sha256, megabytes: megabytes)
        self.licence = licence
        self.source = URL(string: source)!
    }

    /// Its voices: most models have one.
    var voices: [PiperVoice] { PiperVoice.byModel[id] ?? [] }

    var qualityTitle: String {
        quality.isEmpty ? "" : quality.replacingOccurrences(of: "_", with: "-").capitalized + " quality"
    }

    var isNonCommercial: Bool { licence.localizedCaseInsensitiveContains("non-commercial") }

    static func withID(_ id: String) -> PiperModel? { byID[id] }

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// The languages there are models of, by name.
    static let languages: [SpeechLanguage] = {
        var seen = Set<String>()
        return all.map(\.language).filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    /// The language offered before any model is downloaded: the one Piper
    /// is in Dysnow for, which the other models do not speak.
    static let hungarian = SpeechLanguage(id: "hu", name: "Hungarian")
}

/// One of Piper's voices: a model, or one of the speakers of a model of
/// several.
struct PiperVoice: Hashable, Sendable {
    /// The model's id for its first speaker -- the one most models have --
    /// and "model#speaker" for the others.
    let id: String
    let name: String
    let gender: SpeechGender
    let modelID: String
    /// The speaker's number in the model.
    let speaker: Int

    init(model: String, speaker: Int, name: String, gender: SpeechGender) {
        id = speaker == 0 || PiperVoice.firstSpeakerIsNot0.contains(model) ? model : "\(model)#\(speaker)"
        self.name = name
        self.gender = gender
        modelID = model
        self.speaker = speaker
    }

    /// Models whose voice offered first is not speaker 0: Thorsten's
    /// emotional one speaks plainly as speaker 4.
    private static let firstSpeakerIsNot0: Set<String> = ["de_DE-thorsten_emotional-medium"]

    var model: PiperModel { PiperModel.withID(modelID)! }
    var language: SpeechLanguage { model.language }
    var package: ModelPackage { model.package }

    var speechVoice: SpeechVoice {
        SpeechVoice(id: id, name: name, gender: gender, languageID: language.id)
    }

    static func withID(_ id: String) -> PiperVoice? { byID[id] }

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    fileprivate static let byModel = Dictionary(grouping: all, by: \.modelID)
}

/// Piper, run through sherpa-onnx: small models of a voice or a few each, in
/// some forty languages. Each is downloaded on its own, in the Settings.
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

    static func folder(of model: PiperModel, in directory: URL = directory) -> URL {
        directory.appending(path: model.package.folderName, directoryHint: .isDirectory)
    }

    /// Whether the folder has everything the model is loaded from. Most
    /// have eSpeak's data; the Chinese ones a lexicon instead.
    static func holds(_ model: PiperModel, in folder: URL) -> Bool {
        ["\(model.id).onnx", "tokens.txt"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path)
        }
    }

    static func isInstalled(_ model: PiperModel) -> Bool {
        holds(model, in: folder(of: model))
    }

    /// The models downloaded into the folder.
    static func installedModels(in directory: URL = directory) -> Set<String> {
        Set(PiperModel.all.filter { holds($0, in: folder(of: $0, in: directory)) }.map(\.id))
    }

    let id = "piper"
    let name = "Piper"

    /// Hungarian, and the languages of the models downloaded.
    var languages: [SpeechLanguage] {
        let installed = installed
        return PiperModel.languages.filter { language in
            language == PiperModel.hungarian
                || PiperModel.all.contains { $0.language == language && installed.contains($0.id) }
        }
    }

    /// The folder holding the voices; nil to use the one in the settings.
    private let directory: URL?
    /// One per model, loaded the first time it speaks.
    private var loaded: [String: OpaquePointer] = [:]
    /// The models downloaded, as last looked.
    private var installedModels: Set<String>?
    /// One generation at a time: a model is not shared between threads.
    private let lock = NSLock()

    init(directory: URL? = nil) {
        self.directory = directory
    }

    deinit {
        loaded.values.forEach(SherpaOnnxDestroyOfflineTts)
    }

    private func folder(of model: PiperModel) -> URL {
        Self.folder(of: model, in: directory ?? Self.directory)
    }

    private var installed: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        if let installedModels { return installedModels }
        let found = Self.installedModels(in: directory ?? Self.directory)
        installedModels = found
        return found
    }

    /// Some model is there.
    var isAvailable: Bool {
        !installed.isEmpty
    }

    func isAvailable(_ voice: SpeechVoice) -> Bool {
        PiperVoice.withID(voice.id).map { installed.contains($0.modelID) } ?? false
    }

    /// All the voices of the language, downloaded or not: the one picked is
    /// offered to be downloaded.
    func voices(for language: SpeechLanguage) -> [SpeechVoice] {
        guard languages.contains(language) else { return [] }
        return PiperVoice.all.filter { $0.language == language }.map(\.speechVoice)
    }

    /// Lets go of the loaded models, and looks again for those downloaded,
    /// after models were installed or removed.
    func unload() {
        lock.lock()
        defer { lock.unlock() }
        loaded.values.forEach(SherpaOnnxDestroyOfflineTts)
        loaded = [:]
        installedModels = nil
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
        let tts = try model(for: piperVoice.model, voice: piperVoice)
        let sampleRate = Int(SherpaOnnxOfflineTtsSampleRate(tts))
        var generation = SherpaOnnxGenerationConfig()
        generation.sid = Int32(piperVoice.speaker)
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
    private func model(for model: PiperModel, voice: PiperVoice) throws -> OpaquePointer {
        if let tts = loaded[model.id] { return tts }
        let folder = folder(of: model)
        guard Self.holds(model, in: folder) else {
            throw SpeechError.failed("\(voice.name)'s voice is not downloaded yet.")
        }
        let path = { (name: String) in folder.appending(path: name).path }
        let has = { (name: String) in FileManager.default.fileExists(atPath: path(name)) }
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
        config.model.vits.model = c(path("\(model.id).onnx"))
        config.model.vits.tokens = c(path("tokens.txt"))
        config.model.vits.data_dir = c(has("espeak-ng-data") ? path("espeak-ng-data") : "")
        config.model.vits.lexicon = c(has("lexicon.txt") ? path("lexicon.txt") : "")
        // Piper's own defaults.
        config.model.vits.noise_scale = 0.667
        config.model.vits.noise_scale_w = 0.8
        config.model.vits.length_scale = 1.0
        config.model.num_threads = KokoroEngine.defaultThreads
        config.model.provider = c("cpu")
        // The Chinese models' rules for numbers, dates and phone numbers.
        config.rule_fsts = c(["phone.fst", "date.fst", "number.fst"].filter(has).map(path).joined(separator: ","))
        config.max_num_sentences = 1
        guard let tts = SherpaOnnxCreateOfflineTts(&config) else {
            throw SpeechError.failed("\(voice.name)'s voice could not be loaded.")
        }
        loaded[model.id] = tts
        return tts
    }
}
