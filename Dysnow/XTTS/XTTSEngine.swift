import Foundation

/// Coqui's XTTS v2 model: its files, where they are, and getting them.
enum XTTSModel {
    /// The files the model is loaded from; the repository also has what only
    /// training needs.
    static let files: Set<String> = ["config.json", "model.pth", "vocab.json", "speakers_xtts.pth", "LICENSE.txt"]

    static let huggingFace = HuggingFaceModel(repo: "coqui/XTTS-v2", revision: "6c2b0d75eae4b7047358e3b6bd9325f857d43f77",
                                              megabytes: 1_880, files: files)

    static let directoryKey = "xtts.model"

    static var defaultDirectory: URL {
        XTTSEnvironment.root.appending(path: huggingFace.folderName, directoryHint: .isDirectory)
    }

    /// Where Coqui TTS itself keeps it: there when another XTTS program
    /// downloaded it.
    static var coquiDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/tts/tts_models--multilingual--multi-dataset--xtts_v2",
                       directoryHint: .isDirectory)
    }

    /// The folder picked; else Dysnow's own, or Coqui's when only that one
    /// holds the model.
    static var directory: URL {
        if let picked = UserDefaults.standard.string(forKey: directoryKey) {
            return URL(filePath: picked, directoryHint: .isDirectory)
        }
        return !holds(defaultDirectory) && holds(coquiDirectory) ? coquiDirectory : defaultDirectory
    }

    static func holds(_ folder: URL) -> Bool {
        ["config.json", "model.pth", "vocab.json", "speakers_xtts.pth"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path)
        }
    }

    static var isInstalled: Bool { holds(directory) }
}

/// XTTS v2, run in Python by `XTTSServer`: 58 speakers of its own, and the
/// user's own voices, in 17 languages. A voice of the user's with a
/// recording of a mood speaks in that mood.
final class XTTSEngine: MoodAwareEngine, SpeaksInOwnVoices, @unchecked Sendable {
    static let shared = XTTSEngine()

    let id = "xtts"
    let name = "XTTS v2"
    let library: MyVoiceLibrary
    private let server = XTTSServer()
    /// The environment and the model folder; nil to use those in the settings.
    private let environmentOverride: URL?
    private let modelOverride: URL?

    init(library: MyVoiceLibrary = .shared, environment: URL? = nil, model: URL? = nil) {
        self.library = library
        environmentOverride = environment
        modelOverride = model
    }

    private var environment: URL { environmentOverride ?? XTTSEnvironment.environment }
    private var model: URL { modelOverride ?? XTTSModel.directory }

    /// The app's languages, and what XTTS calls them.
    static let languageCodes: [(language: SpeechLanguage, code: String)] = [
        (SpeechLanguage(id: "en-us", name: "English (US)"), "en"),
        (SpeechLanguage(id: "en-gb", name: "English (UK)"), "en"),
        (SpeechLanguage(id: "es", name: "Spanish"), "es"),
        (SpeechLanguage(id: "fr", name: "French"), "fr"),
        (SpeechLanguage(id: "de", name: "German"), "de"),
        (SpeechLanguage(id: "it", name: "Italian"), "it"),
        (SpeechLanguage(id: "pt-br", name: "Portuguese (Brazil)"), "pt"),
        (SpeechLanguage(id: "pt-pt", name: "Portuguese (Portugal)"), "pt"),
        (SpeechLanguage(id: "pl", name: "Polish"), "pl"),
        (SpeechLanguage(id: "tr", name: "Turkish"), "tr"),
        (SpeechLanguage(id: "ru", name: "Russian"), "ru"),
        (SpeechLanguage(id: "nl", name: "Dutch"), "nl"),
        (SpeechLanguage(id: "cs", name: "Czech"), "cs"),
        (SpeechLanguage(id: "ar", name: "Arabic"), "ar"),
        (SpeechLanguage(id: "zh", name: "Chinese (Mandarin)"), "zh-cn"),
        (SpeechLanguage(id: "hu", name: "Hungarian"), "hu"),
        (SpeechLanguage(id: "ko", name: "Korean"), "ko"),
        (SpeechLanguage(id: "ja", name: "Japanese"), "ja"),
        (SpeechLanguage(id: "hi", name: "Hindi"), "hi"),
    ]

    var languages: [SpeechLanguage] { Self.languageCodes.map(\.language) }

    /// How the end of what it says is made: XTTS cuts the last sound short.
    enum Ending: String, CaseIterable, Identifiable {
        /// As XTTS makes it.
        case cut
        /// The last sound made to die away.
        case fade
        /// Its last word said again after it, and cut off; now and then
        /// it is kept.
        case word

        var id: String { rawValue }

        var title: String {
            switch self {
            case .cut: "Cut Short, as XTTS Ends"
            case .fade: "Faded Out"
            case .word: "Last Word Said Again, Cut Off (Experimental)"
            }
        }
    }

    static let endingKey = "xtts.ending"

    var ending: Ending {
        UserDefaults.standard.string(forKey: Self.endingKey).flatMap(Ending.init(rawValue:)) ?? .fade
    }

    var speechSettings: String { "xtts.ending=" + ending.rawValue }

    /// How much text XTTS reads at once, by its language code: its own
    /// limits, and one for Hindi, which it has none for.
    private static let characterLimits = ["en": 250, "de": 253, "fr": 273, "es": 239, "it": 213, "pt": 203,
                                          "pl": 224, "zh-cn": 82, "ar": 166, "cs": 186, "ru": 182, "nl": 251,
                                          "tr": 226, "ja": 71, "hu": 224, "ko": 95, "hi": 150]

    /// XTTS ends what it is given abruptly, but makes the pauses between the
    /// sentences of a piece well itself: it is given as many sentences at
    /// once as it reads well, a little under its limit.
    func longestPiece(in language: SpeechLanguage) -> Int? {
        Self.languageCodes.first { $0.language == language }
            .flatMap { Self.characterLimits[$0.code] }
            .map { $0 * 9 / 10 }
    }

    /// The model's own speakers. Each speaks every language, in the accent
    /// of its recordings. Their names are made up and do not always tell:
    /// the genders were heard from their speech, with a gender classifier
    /// and its pitch -- Andrew Chipper's voice is a woman's.
    static let speakers: [(name: String, gender: SpeechGender)] = [
        ("Aaron Dreschner", .male), ("Abrahan Mack", .male), ("Adde Michal", .male),
        ("Alexandra Hisakawa", .female), ("Alison Dietlinde", .female), ("Alma María", .female),
        ("Ana Florence", .female), ("Andrew Chipper", .female), ("Annmarie Nele", .female), ("Asya Anara", .female),
        ("Badr Odhiambo", .female), ("Baldur Sanjin", .male), ("Barbora MacLean", .female), ("Brenda Stern", .female),
        ("Camilla Holmström", .female), ("Chandra MacFarland", .female), ("Claribel Dervla", .female),
        ("Craig Gutsy", .male), ("Daisy Studious", .female), ("Damien Black", .male), ("Damjan Chapman", .male),
        ("Dionisio Schuyler", .male), ("Eugenio Mataracı", .male), ("Ferran Simen", .male),
        ("Filip Traverse", .male), ("Gilberto Mathias", .male), ("Gitta Nikolina", .female),
        ("Gracie Wise", .female), ("Henriette Usha", .female), ("Ige Behringer", .male), ("Ilkin Urbano", .male),
        ("Kazuhiko Atallah", .male), ("Kumar Dahl", .male), ("Lidiya Szekeres", .female),
        ("Lilya Stainthorpe", .female), ("Ludvig Milivoj", .male), ("Luis Moray", .male), ("Maja Ruoho", .female),
        ("Marcos Rudaski", .male), ("Narelle Moon", .female), ("Nova Hogarth", .female),
        ("Rosemary Okafor", .female), ("Royston Min", .male), ("Sofia Hellen", .female), ("Suad Qasim", .female),
        ("Szofi Granger", .female), ("Tammie Ema", .female), ("Tammy Grit", .female), ("Tanja Adelina", .female),
        ("Torcull Diarmuid", .male), ("Uta Obando", .female), ("Viktor Eka", .male), ("Viktor Menelaos", .male),
        ("Vjollca Johnnie", .female), ("Wulf Carlevaro", .male), ("Xavier Hayasaka", .male),
        ("Zacharie Aimilios", .male), ("Zofija Kendrick", .female),
    ]

    /// Its speakers' ids are their names; the user's voices', "my-…".
    private static let speakerNames = Set(speakers.map(\.name))

    var isAvailable: Bool {
        XTTSEnvironment.isReady(environment) && XTTSModel.holds(model) && XTTSEnvironment.server != nil
    }

    func isAvailable(_ voice: SpeechVoice) -> Bool {
        isAvailable && (Self.speakerNames.contains(voice.id) || library.voice(withID: voice.id) != nil)
    }

    /// The user's voices first, then the model's.
    func voices(for language: SpeechLanguage) -> [SpeechVoice] {
        guard languages.contains(language) else { return [] }
        return library.voices.map { $0.speechVoice(languageID: language.id) }
            + Self.speakers.map { SpeechVoice(id: $0.name, name: $0.name, gender: $0.gender, languageID: language.id) }
    }

    func knows(mood: String, for voice: SpeechVoice) -> Bool {
        library.voice(withID: voice.id)?.moods[mood.lowercased()] != nil
    }

    /// Starts Python and loads the model, which takes a while: ten seconds
    /// or more.
    func prepare() async {
        guard isAvailable else { return }
        _ = try? await server.load(model, in: environment)
    }

    func startingNote() async -> String? {
        guard isAvailable, await !server.isLoaded(model, in: environment) else { return nil }
        return "XTTS v2 is loading its model, which takes about half a minute once after Dysnow starts"
    }

    /// Lets the server go, after the environment or the model changed.
    func unload() async {
        await server.stop()
    }

    /// What the libraries are: whether the environment works.
    func check(_ environment: URL) async throws -> XTTSServer.Answer {
        try await server.send(XTTSServer.Request(command: "check"), in: environment)
    }

    func synthesize(_ text: String, voice: SpeechVoice, language: SpeechLanguage,
                    speed: Float) async throws -> SynthesizedAudio {
        try await generate(text, voice: voice, mood: nil, language: language, speed: speed)
    }

    func synthesize(_ text: String, voice: SpeechVoice, language: SpeechLanguage, speed: Float,
                    mood: String) async throws -> SynthesizedAudio {
        try await generate(text, voice: voice, mood: mood, language: language, speed: speed)
    }

    private func generate(_ text: String, voice: SpeechVoice, mood: String?, language: SpeechLanguage,
                          speed: Float) async throws -> SynthesizedAudio {
        guard isAvailable else { throw SpeechError.unavailable("XTTS v2 is not set up yet: see Settings.") }
        guard let code = Self.languageCodes.first(where: { $0.language == language })?.code else {
            throw SpeechError.failed("XTTS v2 does not speak \(language.name).")
        }
        _ = try await server.load(model, in: environment)
        let output = FileManager.default.temporaryDirectory.appending(path: "dysnow-xtts-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: output) }
        var request = XTTSServer.Request(command: "speak", text: text, language: code, speed: Double(speed),
                                         ending: ending.rawValue, output: output.path)
        if let own = library.voice(withID: voice.id) {
            let sample = mood.flatMap { own.moods[$0.lowercased()] } ?? own.sample
            request.reference = [library.folder(of: own.id).appending(path: sample.file).path]
        } else if Self.speakerNames.contains(voice.id) {
            request.speaker = voice.id
        } else {
            throw SpeechError.unknownVoice(voice.id)
        }
        _ = try await server.send(request, in: environment)
        return try AudioImporter.read(output)
    }
}
