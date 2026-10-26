import AppKit
import FoundationModels
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The text, the voice it is read in, and what is being done with it.
@MainActor @Observable
final class AppModel {
    enum Activity: Equatable {
        case idle
        /// Playing; `made` is how much of the text has been made into speech
        /// so far, from 0 to 1.
        case playing(made: Double)
        case paused(made: Double)
    }

    var text = "" {
        didSet {
            // Pasted or dropped into an empty editor: changes are shown
            // against that from then on. Typed text is not.
            if original.isEmpty, oldValue.isEmpty, text.count > 1 { original = text }
        }
    }
    /// The text as it was opened, or pasted, or as changes were last kept:
    /// what the editor shows the changes against. Empty for none.
    var original = ""
    /// The part of the text selected in the editor, in UTF-16 units, as the
    /// editor has it: that is what is spoken when there is one, else the
    /// whole text. Empty, it is where the cursor is.
    var selection = NSRange(location: 0, length: 0)
    /// The file the text was opened from, or saved to.
    private(set) var fileURL: URL?
    /// The text as it was last opened or saved: when it differs, the text
    /// has changes not saved.
    private(set) var savedText = ""
    /// How far Apple Intelligence is in going through the text, from 0 to 1;
    /// nil when it is not.
    private(set) var preparing: Double?
    private var prepareTask: Task<Void, Never>?

    /// How the text is written: what in it is markup.
    var textFormat: TextFormat {
        didSet { UserDefaults.standard.set(textFormat.rawValue, forKey: Keys.textFormat) }
    }

    let engines = SpeechEngines.all

    // The voice is chosen in this order: the language, then the gender, then
    // the model among those having such voices, then the speaker. Each choice
    // keeps the next one fitting.

    var languageID: String {
        didSet {
            UserDefaults.standard.set(languageID, forKey: Keys.language)
            gender = Self.fitting(gender, in: genders)
        }
    }

    var gender: SpeechGender {
        didSet {
            UserDefaults.standard.set(gender.rawValue, forKey: Keys.gender)
            engineID = Self.fitting(engineID, in: availableEngines.map(\.id))
        }
    }

    var engineID: String {
        didSet {
            UserDefaults.standard.set(engineID, forKey: Keys.engine)
            voiceID = Self.fitting(voiceID, in: voices.map(\.id))
        }
    }

    var voiceID: String {
        didSet {
            UserDefaults.standard.set(voiceID, forKey: Keys.voice)
            prepareEngine()
        }
    }

    /// 1 is the voice's own pace.
    var speed: Double {
        didSet { UserDefaults.standard.set(speed, forKey: Keys.speed) }
    }

    private(set) var activity = Activity.idle
    /// Shown in the status bar: what was done last.
    private(set) var status = ""
    /// Shown as an alert.
    var errorMessage: String?

    /// The files being saved.
    let exports = ExportQueue(notifier: SystemNotifier.shared)
    /// Whether the list of files being saved is shown.
    var showsExports = false
    /// Set to ask for a recording to make a voice of.
    var voiceSheet: VoiceSheet?

    /// The kind of file speech was saved as last.
    var exportFormat: ExportFormat {
        didSet { UserDefaults.standard.set(exportFormat.rawValue, forKey: Keys.exportFormat) }
    }

    private let player = AudioPlayer()
    private var task: Task<Void, Never>?
    /// The speech made last, kept for saving it without making it again.
    private var lastAudio: (key: SpeechRequest, audio: SynthesizedAudio)?

    private enum Keys {
        static let engine = "speech.engine"
        static let language = "speech.language"
        static let gender = "speech.gender"
        static let voice = "speech.voice"
        static let speed = "speech.speed"
        static let exportFormat = "export.format"
        static let textFormat = "text.format"
    }

    /// The speaker picker's item for making a voice of the user's own.
    static let addVoiceTag = "add-voice"

    init() {
        let defaults = UserDefaults.standard
        languageID = defaults.string(forKey: Keys.language) ?? "en-us"
        gender = defaults.string(forKey: Keys.gender).flatMap(SpeechGender.init(rawValue:)) ?? .female
        engineID = defaults.string(forKey: Keys.engine) ?? KokoroEngine.shared.id
        voiceID = defaults.string(forKey: Keys.voice) ?? "af_heart"
        speed = defaults.object(forKey: Keys.speed) as? Double ?? 1.0
        exportFormat = defaults.string(forKey: Keys.exportFormat).flatMap(ExportFormat.init(rawValue:)) ?? .m4a
        textFormat = defaults.string(forKey: Keys.textFormat).flatMap(TextFormat.init(rawValue:)) ?? .markdown
        // The stored ones may no longer be offered; the observers do not run
        // in an initialiser, so the chain is followed here.
        languageID = Self.fitting(languageID, in: languages.map(\.id))
        gender = Self.fitting(gender, in: genders)
        engineID = Self.fitting(engineID, in: availableEngines.map(\.id))
        voiceID = Self.fitting(voiceID, in: voices.map(\.id))
        prepareEngine()
    }

    /// Has the chosen engine load what it needs now, rather than when asked
    /// to speak.
    func prepareEngine() {
        let engine = engine
        Task.detached(priority: .utility) { await engine.prepare() }
    }

    // MARK: Choices

    /// Every language any engine speaks, by name.
    var languages: [SpeechLanguage] {
        var seen = Set<String>()
        return engines.flatMap(\.languages).filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The genders there are voices of in the language.
    var genders: [SpeechGender] {
        SpeechGender.allCases.filter { gender in engines.contains { !voices(of: $0, gender: gender).isEmpty } }
    }

    /// The engines with voices of the language and gender; and those that
    /// speak the language in the user's own voices, even before there are
    /// any, so that some can be made.
    var availableEngines: [any SpeechEngine] {
        engines.filter { engine in
            !voices(of: engine, gender: gender).isEmpty
                || engine is SpeaksInOwnVoices && engine.languages.contains { $0.id == languageID }
        }
    }

    /// Whether the chosen engine speaks in the user's own voices.
    var engineTakesOwnVoices: Bool { engine is SpeaksInOwnVoices }

    var engine: any SpeechEngine {
        engines.first { $0.id == engineID } ?? engines[0]
    }

    /// The language as the chosen engine knows it.
    var language: SpeechLanguage? {
        engine.languages.first { $0.id == languageID }
    }

    /// The speakers to choose from.
    var voices: [SpeechVoice] {
        voices(of: engine, gender: gender)
    }

    var voice: SpeechVoice? {
        voices.first { $0.id == voiceID }
    }

    private func voices(of engine: any SpeechEngine, gender: SpeechGender) -> [SpeechVoice] {
        // Read so that the lists follow when the user's voices change.
        _ = MyVoiceStore.shared.voices
        guard let language = engine.languages.first(where: { $0.id == languageID }) else { return [] }
        return engine.voices(for: language).filter { $0.gender == gender }
    }

    /// Keeps the choices fitting after the user's voices changed: a voice
    /// added may be the first of its gender, one deleted may be the chosen.
    func voicesChanged(selecting id: String? = nil) {
        if let voice = id.flatMap({ id in MyVoiceStore.shared.voices.first { $0.id == id } }) {
            gender = voice.gender
            if let engine = availableEngines.first(where: { $0 is SpeaksInOwnVoices }), !engineTakesOwnVoices {
                engineID = engine.id
            }
            voiceID = voice.id
            return
        }
        gender = Self.fitting(gender, in: genders)
        voiceID = Self.fitting(voiceID, in: voices.map(\.id))
    }

    private static func fitting<Value: Equatable>(_ value: Value, in values: [Value]) -> Value {
        values.contains(value) ? value : values.first ?? value
    }

    /// A speaker picked by hand: it says hello, so it can be heard.
    func chooseVoice(_ id: String) {
        guard id != Self.addVoiceTag else {
            voiceSheet = .newVoice
            return
        }
        voiceID = id
        greet()
    }

    func greet() {
        guard let voice, engine.isAvailable(voice) else { return }
        let text = Greeting.text(languageID: languageID, name: voice.spokenName ?? voice.name)
        play([SpokenBlock(text: text, pauseAfter: 0, range: self.text.startIndex..<self.text.startIndex)])
    }

    // MARK: Text

    /// The selected part of the text; nil when only the cursor is there.
    private var selectedRange: Range<String.Index>? {
        guard selection.length > 0, let range = Range(selection, in: text) else { return nil }
        return range
    }

    var selectionIsEmpty: Bool { selectedRange == nil }

    /// Where the cursor is, or where the selection starts.
    private var cursor: String.Index? {
        Range(NSRange(location: selection.location, length: 0), in: text)?.lowerBound
    }

    /// The selected text, or the whole text when nothing is selected.
    var textToSpeak: String {
        selectedRange.map { String(text[$0]) } ?? text
    }

    var canSpeak: Bool {
        (voice.map(engine.isAvailable) ?? false)
            && !textToSpeak.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Starts a new text: the editor emptied, changes shown against what
    /// is pasted next. Asks first when the text has changes not saved.
    func newText() {
        if hasUnsavedChanges, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let alert = NSAlert()
            alert.messageText = "Start a new text?"
            alert.informativeText = "The text has changes that are not saved; they are lost."
            alert.addButton(withTitle: "New Text")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        stop()
        original = ""
        text = ""
        savedText = ""
        selection = NSRange(location: 0, length: 0)
        fileURL = nil
        status = "New text"
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.text, UTType("org.openxmlformats.wordprocessingml.document")]
            .compactMap { $0 }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        do {
            let read = try Self.read(url)
            original = read
            text = read
            savedText = read
            selection = NSRange(location: 0, length: 0)
            fileURL = url
            if let format = TextFormat(fileExtension: url.pathExtension) {
                textFormat = format
            }
            status = "Opened \(url.lastPathComponent)"
        } catch {
            errorMessage = "\(url.lastPathComponent) could not be opened: \(error.localizedDescription)"
        }
    }

    var hasUnsavedChanges: Bool { text != savedText }

    /// Saves to the file the text came from, when it is a text file;
    /// otherwise asks where.
    func saveText() {
        if let fileURL, (UTType(filenameExtension: fileURL.pathExtension) ?? .data).conforms(to: .plainText) {
            write(to: fileURL)
        } else {
            saveTextAs()
        }
    }

    /// Asks where to save the text: a .md file for Markdown, a .txt for plain
    /// text.
    func saveTextAs() {
        let panel = NSSavePanel()
        let type = textFormat == .markdown ? UTType(filenameExtension: "md") ?? .plainText : .plainText
        panel.allowedContentTypes = [type]
        panel.isExtensionHidden = false
        let name = fileURL?.deletingPathExtension().lastPathComponent ?? "Text"
        panel.nameFieldStringValue = name + "." + (textFormat == .markdown ? "md" : "txt")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(to: url)
    }

    private func write(to url: URL) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
            savedText = text
            status = "Saved \(url.lastPathComponent)"
        } catch {
            errorMessage = "\(url.lastPathComponent) could not be saved: \(error.localizedDescription)"
        }
    }

    // MARK: Apple Intelligence

    /// Has Apple Intelligence go through the text, a paragraph at a time,
    /// fixing typos and writing out abbreviations and signs as they are
    /// said. The text changes as it goes; the editor shows what changed.
    func prepareText() {
        if let reason = TextPreparer.unavailableReason {
            errorMessage = reason
            return
        }
        guard preparing == nil else { return }
        stop()
        let parts = TextPreparer.parts(of: text, format: textFormat)
        guard !parts.isEmpty else {
            status = "Nothing for Apple Intelligence to go through."
            return
        }
        if original.isEmpty { original = text }
        let format = textFormat
        preparing = 0
        prepareTask = Task {
            var offset = 0, changed = 0, kept = 0
            var problem: String?
            for (index, part) in parts.enumerated() {
                guard !Task.isCancelled else { break }
                // The text is not edited meanwhile: only what was changed
                // before this part moves it.
                let range = NSRange(location: part.range.location + offset, length: part.range.length)
                let before = (text as NSString).substring(with: range)
                do {
                    if let after = try await TextPreparer.prepare(before, format: format) {
                        if after != before, !Task.isCancelled {
                            text = (text as NSString).replacingCharacters(in: range, with: after)
                            offset += after.utf16.count - before.utf16.count
                            changed += 1
                        }
                    } else {
                        kept += 1
                    }
                } catch let error as LanguageModelSession.GenerationError {
                    if case .unsupportedLanguageOrLocale = error {
                        problem = "Apple Intelligence does not handle the language of this text."
                        break
                    }
                    // Its guardrails, or a part too long: left as it is.
                    kept += 1
                } catch {
                    problem = error.localizedDescription
                    break
                }
                preparing = Double(index + 1) / Double(parts.count)
            }
            preparing = nil
            prepareTask = nil
            if let problem { errorMessage = problem }
            status = "Apple Intelligence changed \(changed) of \(parts.count) paragraphs"
                + (kept > 0 ? "; \(kept) left as they were" : "")
                + (Task.isCancelled ? " before it was stopped" : "")
        }
    }

    func stopPreparing() {
        prepareTask?.cancel()
    }

    /// Plain text as it is, in whatever encoding it is in; rich text, HTML and
    /// Word documents as the text in them.
    private static func read(_ url: URL) throws -> String {
        let type = UTType(filenameExtension: url.pathExtension) ?? .plainText
        if !type.conforms(to: .plainText) {
            return try NSAttributedString(url: url, options: [:], documentAttributes: nil).string
        }
        var encoding = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &encoding) {
            return text
        }
        return try String(contentsOf: url, encoding: .isoLatin1)
    }

    // MARK: Speaking

    private func request(_ blocks: [SpokenBlock]) -> SpeechRequest? {
        guard let language, let voice, engine.isAvailable(voice) else { return nil }
        guard !blocks.isEmpty else {
            status = "Nothing to read: there are no words in the text."
            return nil
        }
        return SpeechRequest(engineID: engine.id, language: language, voice: voice, speed: Float(speed), blocks: blocks,
                             settings: engines.map(\.speechSettings).joined(separator: ","))
    }

    /// The selection, with the markup open where it starts, or the whole text.
    private var blocksToSpeak: [SpokenBlock] {
        selectedRange.map { TextReader.blocks(in: text, format: textFormat, range: $0) }
            ?? TextReader.blocks(in: text, format: textFormat)
    }

    func togglePlay() {
        switch activity {
        case .playing(let made):
            player.pause()
            activity = .paused(made: made)
        case .paused(let made):
            player.resume()
            activity = .playing(made: made)
        case .idle:
            play()
        }
    }

    /// Reads the selection, or the whole text.
    func play() {
        play(blocksToSpeak)
    }

    /// Reads from the sentence the cursor is in to the end.
    func playFromCursor() {
        guard let cursor else { return play() }
        play(TextReader.blocks(in: text, format: textFormat, from: cursor))
    }

    private func play(_ blocks: [SpokenBlock]) {
        stop()
        guard let request = request(blocks) else { return }
        let engine = engine
        task = Task {
            do {
                activity = .playing(made: 0)
                let speaking = "Speaking with \(request.voice.name)" + Self.warning(about: request, for: engine)
                status = speaking
                if let lastAudio, lastAudio.key == request {
                    try player.start(sampleRate: lastAudio.audio.sampleRate)
                    player.enqueue(lastAudio.audio.samples)
                    activity = .playing(made: 1)
                } else {
                    var started = false
                    if let note = await engine.startingNote() { status = note }
                    let audio = try await Synthesizer.synthesize(request, with: engine, engines: engines) {
                        [weak self] made, piece in
                        guard let self else { return }
                        if !started {
                            try player.start(sampleRate: piece.sampleRate)
                            started = true
                            status = speaking
                        }
                        player.enqueue(piece.samples)
                        activity = activity.isPaused ? .paused(made: made) : .playing(made: made)
                    }
                    lastAudio = (request, audio)
                }
                await player.drain()
                try Task.checkCancellation()
                activity = .idle
                status = "Done"
            } catch is CancellationError {
            } catch {
                player.stop()
                activity = .idle
                errorMessage = error.localizedDescription
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        player.stop()
        if activity != .idle { status = "Stopped" }
        activity = .idle
    }

    /// What in the markup could not be followed: speakers not there, read
    /// in the voice chosen instead; languages no model speaks, read in the
    /// one chosen; models there are none of.
    private static func warning(about request: SpeechRequest, for engine: any SpeechEngine) -> String {
        let quoted = { (names: [String]) in names.map { "\u{201C}\($0)\u{201D}" }.formatted(.list(type: .or)) }
        var speakers: [String] = [], languages: [String] = [], models: [String] = [], voiceless: [String] = []
        for problem in Synthesizer.problems(in: request, for: engine, engines: SpeechEngines.all) {
            switch problem {
            case .speaker(let name): speakers.append(name)
            case .language(let name): languages.append(name)
            case .model(let name): models.append(name)
            case .noVoice(let model, let language): voiceless.append("\(model) in \(language)")
            }
        }
        var warning = ""
        if !speakers.isEmpty {
            warning += " -- no speaker called, or not downloaded: \(quoted(speakers)), read as \(request.voice.name)"
        }
        if !languages.isEmpty {
            warning += " -- no model speaks \(quoted(languages)), read in \(request.language.name)"
        }
        if !models.isEmpty {
            warning += " -- no model called \(quoted(models)), read by \(engine.name)"
        }
        if !voiceless.isEmpty {
            warning += " -- no voice downloaded for \(voiceless.formatted(.list(type: .or))), read by \(engine.name)"
        }
        return warning
    }

    // MARK: Markup

    /// What Control-Space offers where the cursor is: the speakers are those
    /// there to speak for the model and the language read there -- as the
    /// markup before the cursor, or the `set` tag being written, says.
    func completer() -> MarkupCompleter {
        let engines = engines, main = engine
        let here = cursor.map { TextReader.markup(in: text, format: textFormat, before: $0).style } ?? SpeechStyle()
        let request = language.flatMap { language in
            voice.map { SpeechRequest(engineID: main.id, language: language, voice: $0, speed: 1, blocks: []) }
        }
        return MarkupCompleter(syntax: textFormat.syntax) { kind, tag in
            var style = here
            if let model = tag["model"], !model.isEmpty { style.model = model }
            if let language = tag["language"], !language.isEmpty { style.language = language }
            let reader = request.map { Synthesizer.reader(for: style, in: $0, engine: main, engines: engines).reader }
            var seen = Set<String>()
            let unique = { (names: [String]) in names.filter { seen.insert($0).inserted } }
            switch kind {
            case "speaker":
                guard let reader else { return [] }
                return unique(reader.engine.voices(for: reader.language).filter(reader.engine.isAvailable).map(\.name))
            case "mood":
                return SpeechMarkup.moods
            case "language":
                // A model named in the tag speaks its own; otherwise any
                // model's language may be asked for.
                if let model = tag["model"], !model.isEmpty, let reader { return reader.engine.languages.map(\.name) }
                return unique(engines.flatMap(\.languages).map(\.name))
            case "model":
                return engines.filter(\.isAvailable).map(\.name)
            default:
                return []
            }
        }
    }

    /// Asks where to save the speech of the selection, or of the whole text,
    /// and queues it to be made; playback goes on meanwhile.
    func saveAudio() {
        guard let request = request(blocksToSpeak) else { return }
        let name = fileURL?.deletingPathExtension().lastPathComponent ?? "Speech"
        guard let (url, format) = AudioSavePanel.run(name: name, format: exportFormat) else { return }
        exportFormat = format
        let made = lastAudio.flatMap { $0.key == request ? $0.audio : nil }
        exports.enqueue(request, engine: engine, to: url, audio: made)
        showsExports = true
    }
}

/// What a recording is asked for: a new voice, or a mood of one.
enum VoiceSheet: Identifiable, Equatable {
    case newVoice
    case mood(voiceID: String)

    var id: String {
        switch self {
        case .newVoice: "new"
        case .mood(let voiceID): "mood-\(voiceID)"
        }
    }
}

private extension AppModel.Activity {
    var isPaused: Bool {
        if case .paused = self { true } else { false }
    }
}
