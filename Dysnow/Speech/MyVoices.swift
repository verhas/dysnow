import Foundation
import Observation

/// A voice of the user's own, made from a recording: ZipVoice and Pocket TTS
/// speak in it. A recording of it in a mood makes it speak in that mood.
struct MyVoice: Codable, Hashable, Identifiable, Sendable {
    /// A recording, and what is said in it.
    struct Sample: Codable, Hashable, Sendable {
        /// The file in the voice's folder.
        var file: String
        var transcript: String
    }

    let id: String
    var name: String
    var gender: SpeechGender
    /// How it sounds as a rule.
    var sample: Sample
    /// How it sounds in a mood, by the mood, lowercased: "excited".
    var moods: [String: Sample] = [:]

    func speechVoice(languageID: String) -> SpeechVoice {
        SpeechVoice(id: id, name: name, gender: gender, languageID: languageID)
    }
}

extension SpeechGender: Codable {}

/// The user's voices on the disk: a folder per voice, in
/// `~/.dysnow/my-voices`, holding its recordings and a voice.json. Read by
/// the engines on any thread.
final class MyVoiceLibrary: @unchecked Sendable {
    static let shared = MyVoiceLibrary(directory: DysnowHome.root.appending(path: "my-voices",
                                                                           directoryHint: .isDirectory))

    let directory: URL
    private let lock = NSLock()
    private var cached: [MyVoice]?
    /// The recordings read so far, by their path.
    private var samples: [String: SynthesizedAudio] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    /// Every voice, by name.
    var voices: [MyVoice] {
        lock.withLock {
            if let cached { return cached }
            let loaded = load()
            cached = loaded
            return loaded
        }
    }

    func voice(withID id: String) -> MyVoice? {
        voices.first { $0.id == id }
    }

    func folder(of id: String) -> URL {
        directory.appending(path: id, directoryHint: .isDirectory)
    }

    /// The recording the voice is made from in the mood, or as a rule when
    /// there is none of the mood; nil for no mood.
    func reference(for id: String, mood: String? = nil) throws -> (audio: SynthesizedAudio, transcript: String) {
        guard let voice = voice(withID: id) else { throw SpeechError.unknownVoice(id) }
        let sample = mood.flatMap { voice.moods[$0.lowercased()] } ?? voice.sample
        let url = folder(of: id).appending(path: sample.file)
        if let audio = lock.withLock({ samples[url.path] }) { return (audio, sample.transcript) }
        let audio = try AudioImporter.read(url)
        lock.withLock { samples[url.path] = audio }
        return (audio, sample.transcript)
    }

    /// Makes a new voice of a recording.
    @discardableResult
    func add(name: String, gender: SpeechGender, audio: SynthesizedAudio, transcript: String) throws -> MyVoice {
        let id = "my-" + UUID().uuidString.prefix(8).lowercased()
        let folder = folder(of: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try AudioExporter.write(audio, to: folder.appending(path: "voice.wav"))
        let voice = MyVoice(id: id, name: name, gender: gender, sample: .init(file: "voice.wav", transcript: transcript))
        try save(voice)
        return voice
    }

    /// Records how the voice sounds in a mood; another recording of the mood
    /// takes the place of the one before.
    func addMood(_ mood: String, to id: String, audio: SynthesizedAudio, transcript: String) throws {
        guard var voice = voice(withID: id) else { throw SpeechError.unknownVoice(id) }
        let mood = mood.trimmingCharacters(in: .whitespaces).lowercased()
        let file = "mood-" + mood.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined() + ".wav"
        try AudioExporter.write(audio, to: folder(of: id).appending(path: file))
        lock.withLock { samples[folder(of: id).appending(path: file).path] = nil }
        voice.moods[mood] = .init(file: file, transcript: transcript)
        try save(voice)
    }

    func removeMood(_ mood: String, from id: String) throws {
        guard var voice = voice(withID: id), let sample = voice.moods.removeValue(forKey: mood) else { return }
        try? FileManager.default.removeItem(at: folder(of: id).appending(path: sample.file))
        try save(voice)
    }

    /// Changes the name or the gender.
    func update(_ voice: MyVoice) throws {
        try save(voice)
    }

    func remove(_ id: String) throws {
        try FileManager.default.removeItem(at: folder(of: id))
        reload()
    }

    /// Reads the folder again on the next look.
    func reload() {
        lock.withLock {
            cached = nil
            samples = [:]
        }
    }

    private func save(_ voice: MyVoice) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(voice).write(to: folder(of: voice.id).appending(path: "voice.json"), options: .atomic)
        lock.withLock { cached = nil }
    }

    /// Called with the lock held.
    private func load() -> [MyVoice] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            (try? Data(contentsOf: folder.appending(path: "voice.json")))
                .flatMap { try? JSONDecoder().decode(MyVoice.self, from: $0) }
                .flatMap { $0.id == folder.lastPathComponent ? $0 : nil }
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// The user's voices, for the windows: changed here, so what shows them
/// follows.
@MainActor @Observable
final class MyVoiceStore {
    static let shared = MyVoiceStore(library: .shared)

    let library: MyVoiceLibrary
    private(set) var voices: [MyVoice]

    init(library: MyVoiceLibrary) {
        self.library = library
        voices = library.voices
    }

    func refresh() {
        library.reload()
        voices = library.voices
    }

    @discardableResult
    func add(name: String, gender: SpeechGender, audio: SynthesizedAudio, transcript: String) throws -> MyVoice {
        defer { voices = library.voices }
        return try library.add(name: name, gender: gender, audio: audio, transcript: transcript)
    }

    func addMood(_ mood: String, to id: String, audio: SynthesizedAudio, transcript: String) throws {
        defer { voices = library.voices }
        try library.addMood(mood, to: id, audio: audio, transcript: transcript)
    }

    func removeMood(_ mood: String, from id: String) throws {
        defer { voices = library.voices }
        try library.removeMood(mood, from: id)
    }

    func update(_ voice: MyVoice) throws {
        defer { voices = library.voices }
        try library.update(voice)
    }

    func remove(_ id: String) throws {
        defer { voices = library.voices }
        try library.remove(id)
    }
}
