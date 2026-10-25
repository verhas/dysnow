import AppKit
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

    var text = ""
    /// The part of the text selected in the editor: that is what is spoken
    /// when there is one, else the whole text.
    var selection: TextSelection?
    /// The file the text was opened from.
    private(set) var fileURL: URL?

    let engines: [any SpeechEngine] = [KokoroEngine.shared, PiperEngine.shared]
        + (Qwen3Engine.isSupported ? [Qwen3Engine.shared] : [])

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
    }

    init() {
        let defaults = UserDefaults.standard
        languageID = defaults.string(forKey: Keys.language) ?? "en-us"
        gender = defaults.string(forKey: Keys.gender).flatMap(SpeechGender.init(rawValue:)) ?? .female
        engineID = defaults.string(forKey: Keys.engine) ?? KokoroEngine.shared.id
        voiceID = defaults.string(forKey: Keys.voice) ?? "af_heart"
        speed = defaults.object(forKey: Keys.speed) as? Double ?? 1.0
        exportFormat = defaults.string(forKey: Keys.exportFormat).flatMap(ExportFormat.init(rawValue:)) ?? .m4a
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

    /// The engines with voices of the language and gender.
    var availableEngines: [any SpeechEngine] {
        engines.filter { !voices(of: $0, gender: gender).isEmpty }
    }

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
        guard let language = engine.languages.first(where: { $0.id == languageID }) else { return [] }
        return engine.voices(for: language).filter { $0.gender == gender }
    }

    private static func fitting<Value: Equatable>(_ value: Value, in values: [Value]) -> Value {
        values.contains(value) ? value : values.first ?? value
    }

    /// A speaker picked by hand: it says hello, so it can be heard.
    func chooseVoice(_ id: String) {
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
        guard let selection, case .selection(let range) = selection.indices, !range.isEmpty,
              range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else { return nil }
        return range
    }

    var selectionIsEmpty: Bool { selectedRange == nil }

    /// Where the cursor is, or where the selection starts.
    private var cursor: String.Index? {
        guard let selection, case .selection(let range) = selection.indices,
              range.lowerBound >= text.startIndex, range.lowerBound <= text.endIndex else { return nil }
        return range.lowerBound
    }

    /// The selected text, or the whole text when nothing is selected.
    var textToSpeak: String {
        selectedRange.map { String(text[$0]) } ?? text
    }

    var canSpeak: Bool {
        (voice.map(engine.isAvailable) ?? false)
            && !textToSpeak.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            text = try Self.read(url)
            selection = nil
            fileURL = url
            status = "Opened \(url.lastPathComponent)"
        } catch {
            errorMessage = "\(url.lastPathComponent) could not be opened: \(error.localizedDescription)"
        }
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
        return SpeechRequest(engineID: engine.id, language: language, voice: voice, speed: Float(speed), blocks: blocks)
    }

    /// The selection, with the markup open where it starts, or the whole text.
    private var blocksToSpeak: [SpokenBlock] {
        selectedRange.map { MarkdownReader.blocks(in: text, range: $0) } ?? MarkdownReader.blocks(in: text)
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
        play(MarkdownReader.blocks(in: text, from: cursor))
    }

    private func play(_ blocks: [SpokenBlock]) {
        stop()
        guard let request = request(blocks) else { return }
        let engine = engine
        task = Task {
            do {
                activity = .playing(made: 0)
                status = "Speaking with \(request.voice.name)" + Self.warning(about: request, for: engine)
                if let lastAudio, lastAudio.key == request {
                    try player.start(sampleRate: lastAudio.audio.sampleRate)
                    player.enqueue(lastAudio.audio.samples)
                    activity = .playing(made: 1)
                } else {
                    var started = false
                    let audio = try await Synthesizer.synthesize(request, with: engine) { [weak self] made, piece in
                        guard let self else { return }
                        if !started {
                            try player.start(sampleRate: piece.sampleRate)
                            started = true
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

    /// Speakers in `tts:speaker` tags that are not there: read in the voice
    /// chosen instead.
    private static func warning(about request: SpeechRequest, for engine: any SpeechEngine) -> String {
        let unknown = Synthesizer.unknownSpeakers(in: request, for: engine)
        guard !unknown.isEmpty else { return "" }
        return " -- no speaker called, or not downloaded: " + unknown.map { "\u{201C}\($0)\u{201D}" }.formatted(.list(type: .or))
            + ", read as \(request.voice.name)"
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

private extension AppModel.Activity {
    var isPaused: Bool {
        if case .paused = self { true } else { false }
    }
}
