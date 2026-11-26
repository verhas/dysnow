import Foundation

/// Speech made without the app's window: for the command line and the MCP
/// server. The voice is chosen from what is asked for, and what is not asked
/// for is taken from the app's own choices: the language, the model and the
/// speaker picked there last.
@MainActor
enum SpeechService {
    /// What is asked for; nil is "as the app has it", or anything fitting.
    struct VoiceChoice: Sendable {
        /// By id or name: "en-gb", "British English", "German".
        var language: String?
        /// A speaker's name or id: "Heart", "af_heart".
        var voice: String?
        /// A model's name or id, or the start of it: "kokoro", "Piper".
        var model: String?
        var gender: SpeechGender?
    }

    struct Job: Sendable {
        var text: String
        var format: TextFormat = .markdown
        var choice = VoiceChoice()
        /// 1 is the voice's own pace.
        var speed: Double = 1
        /// The sound file to write; its extension picks the kind.
        var output: URL?
    }

    struct Result: Sendable {
        let output: URL?
        let duration: TimeInterval
        let sampleRate: Int
        let model: String
        let language: SpeechLanguage
        let voice: SpeechVoice
        /// What in the text's markup could not be followed.
        let warnings: [String]

        var json: JSONValue {
            var object: [String: JSONValue] = [
                "duration": .number((duration * 1000).rounded() / 1000),
                "sample_rate": .number(Double(sampleRate)),
                "model": .string(model),
                "language": .string(language.id),
                "language_name": .string(language.name),
                "voice": .string(voice.name),
                "voice_id": .string(voice.id),
                "warnings": .array(warnings.map(JSONValue.string)),
            ]
            if let output { object["output"] = .string(output.path) }
            return .object(object)
        }
    }

    static var engines: [any SpeechEngine] { SpeechEngines.all }

    // MARK: Choosing

    /// The engine, the language and the voice that read: the model asked for,
    /// else the one chosen in the app, else the first that has a voice
    /// fitting the rest. Throws, saying why, when nothing fits.
    static func reader(for choice: VoiceChoice) throws -> Synthesizer.Reader {
        let defaults = UserDefaults.standard
        let storedEngine = defaults.string(forKey: AppModel.Keys.engine)
        let storedLanguage = defaults.string(forKey: AppModel.Keys.language) ?? "en-us"
        let storedVoice = defaults.string(forKey: AppModel.Keys.voice)

        var candidates = engines
        if let name = choice.model?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            candidates = engines.filter { Synthesizer.matches(name, $0) }
            guard !candidates.isEmpty else {
                throw SpeechError.failed("There is no model called \u{201C}\(name)\u{201D}. The models are "
                    + engines.map(\.name).formatted(.list(type: .and)) + ".")
            }
        } else if let stored = candidates.firstIndex(where: { $0.id == storedEngine }) {
            candidates.insert(candidates.remove(at: stored), at: 0)
        }
        let installed = candidates.filter(\.isAvailable)
        guard !installed.isEmpty else {
            let names = candidates.map(\.name).formatted(.list(type: .or))
            throw SpeechError.failed("\(names) is not installed. Open Dysnow and download it in its Settings.")
        }
        if let name = choice.language, !installed.contains(where: { $0.language(named: name) != nil }) {
            throw SpeechError.failed("No model speaks \u{201C}\(name)\u{201D}. `dysnow voices` lists the languages.")
        }

        for engine in installed {
            var language: SpeechLanguage?
            if let name = choice.language {
                guard let found = engine.language(named: name) else { continue }
                language = found
            }
            if let name = choice.voice {
                guard let preferred = language ?? engine.language(named: storedLanguage) ?? engine.languages.first,
                      let voice = engine.voice(named: name, preferring: preferred), engine.isAvailable(voice),
                      choice.gender == nil || voice.gender == choice.gender
                else { continue }
                // The voice's own language, unless another was asked for.
                let spoken = language ?? engine.languages.first { $0.id == voice.languageID } ?? preferred
                return Synthesizer.Reader(engine: engine, language: spoken, voice: voice)
            }
            guard let spoken = language ?? engine.languages.first(where: { $0.id == storedLanguage })
                ?? (choice.language == nil && candidates.count == 1 ? engine.languages.first : nil)
            else { continue }
            let voices = engine.voices(for: spoken).filter(engine.isAvailable)
                .filter { choice.gender == nil || $0.gender == choice.gender }
            guard let voice = voices.first(where: { $0.id == storedVoice }) ?? voices.first else { continue }
            return Synthesizer.Reader(engine: engine, language: spoken, voice: voice)
        }

        var asked: [String] = []
        if let model = choice.model { asked.append("model \u{201C}\(model)\u{201D}") }
        if let language = choice.language { asked.append("language \u{201C}\(language)\u{201D}") }
        if let voice = choice.voice { asked.append("voice \u{201C}\(voice)\u{201D}") }
        if let gender = choice.gender { asked.append(gender.rawValue + " voice") }
        if asked.isEmpty { asked.append("language \u{201C}\(storedLanguage)\u{201D}") }
        throw SpeechError.failed("No downloaded voice fits the \(asked.formatted(.list(type: .and))). "
            + "`dysnow voices` lists the voices there are.")
    }

    // MARK: Speaking

    /// Makes the speech of the job's text and writes it to its output, when
    /// it has one. `piece` is handed each piece as it is made, with how much
    /// of the text is done, from 0 to 1.
    static func speak(_ job: Job, note: (String) -> Void = { _ in },
                      piece: @MainActor (Double, SynthesizedAudio) throws -> Void = { _, _ in })
        async throws -> Result {
        if let output = job.output, ExportFormat(fileExtension: output.pathExtension) == nil {
            throw SpeechError.failed("Speech can be saved as "
                + ExportFormat.allCases.map { "." + $0.fileExtension }.formatted(.list(type: .or))
                + ", not \(output.pathExtension.isEmpty ? "a file without an extension" : "." + output.pathExtension).")
        }
        let reader = try reader(for: job.choice)
        let blocks = TextReader.blocks(in: job.text, format: job.format)
        guard !blocks.isEmpty else { throw SpeechError.failed("Nothing to read: there are no words in the text.") }
        let request = SpeechRequest(engineID: reader.engine.id, language: reader.language, voice: reader.voice,
                                    speed: Float(min(max(job.speed, 0.25), 4)), blocks: blocks)
        let warnings = Synthesizer.problems(in: request, for: reader.engine, engines: engines).map(describe)
        if let starting = await reader.engine.startingNote() { note(starting) }
        let audio = try await Synthesizer.synthesize(request, with: reader.engine, engines: engines, piece: piece)
        if let output = job.output {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try await Task.detached(priority: .userInitiated) { try AudioExporter.write(audio, to: output) }.value
        }
        return Result(output: job.output, duration: audio.duration, sampleRate: audio.sampleRate,
                      model: reader.engine.name, language: reader.language, voice: reader.voice, warnings: warnings)
    }

    static func describe(_ problem: Synthesizer.Problem) -> String {
        switch problem {
        case .speaker(let name): "No speaker called \u{201C}\(name)\u{201D}, or not downloaded; read in the voice chosen."
        case .language(let name): "No model speaks \u{201C}\(name)\u{201D}; read in the language chosen."
        case .model(let name): "No model called \u{201C}\(name)\u{201D}; read by the model chosen."
        case .noVoice(let model, let language): "\(model) has no voice downloaded for \(language); read by the model chosen."
        }
    }

    /// Lets go of what the engines started that outlives a request: XTTS's
    /// Python.
    static func shutDown() async {
        await XTTSEngine.shared.unload()
    }

    // MARK: Listing

    struct VoiceEntry: Sendable {
        let model: any SpeechEngine
        let language: SpeechLanguage
        let voice: SpeechVoice

        var json: JSONValue {
            ["model": .string(model.name), "model_id": .string(model.id), "language": .string(language.id),
             "language_name": .string(language.name), "voice": .string(voice.name), "voice_id": .string(voice.id),
             "gender": .string(voice.gender.rawValue)]
        }
    }

    /// The voices that can speak now, of the installed models: those of a
    /// language, a model or a gender when one is named.
    static func voices(language: String? = nil, model: String? = nil,
                       gender: SpeechGender? = nil) throws -> [VoiceEntry] {
        var chosen = engines.filter(\.isAvailable)
        if let model, !model.isEmpty {
            chosen = chosen.filter { Synthesizer.matches(model, $0) }
            if chosen.isEmpty, !engines.contains(where: { Synthesizer.matches(model, $0) }) {
                throw SpeechError.failed("There is no model called \u{201C}\(model)\u{201D}.")
            }
        }
        var entries: [VoiceEntry] = []
        for engine in chosen {
            let languages = language.map { name in engine.language(named: name).map { [$0] } ?? [] }
                ?? engine.languages
            for spoken in languages {
                for voice in engine.voices(for: spoken) where engine.isAvailable(voice)
                    && (gender == nil || voice.gender == gender) {
                    entries.append(VoiceEntry(model: engine, language: spoken, voice: voice))
                }
            }
        }
        return entries
    }

    /// Every model, whether it is installed, and the languages it speaks.
    static var models: [JSONValue] {
        engines.map { engine in
            ["name": .string(engine.name), "id": .string(engine.id), "installed": .bool(engine.isAvailable),
             "languages": .array(engine.languages.map { .string($0.id) })]
        }
    }
}
