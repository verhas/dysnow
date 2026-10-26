import XCTest
@testable import Dysnow

/// The user's voices on the disk, in a folder of the test's own.
final class MyVoiceLibraryTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appending(path: "dysnow-voices-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private let tone = SynthesizedAudio(samples: (0..<24_000).map { sin(Float($0) / 8) * 0.5 }, sampleRate: 24_000)

    func testVoicesAreKeptWithTheirMoods() throws {
        let library = MyVoiceLibrary(directory: folder)
        let voice = try library.add(name: "Peter", gender: .male, audio: tone, transcript: "Hello.")
        try library.addMood("Excited", to: voice.id, audio: tone, transcript: "Wow!")

        let again = MyVoiceLibrary(directory: folder)
        XCTAssertEqual(again.voices.map(\.name), ["Peter"])
        XCTAssertEqual(again.voices.first?.moods["excited"]?.transcript, "Wow!")
        let reference = try again.reference(for: voice.id, mood: "excited")
        XCTAssertEqual(reference.transcript, "Wow!")
        XCTAssertEqual(reference.audio.sampleRate, 24_000)
        XCTAssertEqual(reference.audio.duration, 1, accuracy: 0.01)
        XCTAssertEqual(try again.reference(for: voice.id, mood: "sad").transcript, "Hello.")

        try again.removeMood("excited", from: voice.id)
        XCTAssertNil(again.voices.first?.moods["excited"])
        try again.remove(voice.id)
        XCTAssertTrue(again.voices.isEmpty)
    }

    func testTheEnginesOfferEveryVoiceInEachOfTheirLanguages() throws {
        let library = MyVoiceLibrary(directory: folder)
        let voice = try library.add(name: "Ann", gender: .female, audio: tone, transcript: "Hi.")
        try library.addMood("sad", to: voice.id, audio: tone, transcript: "Oh.")
        let engine = CloningEngine(model: .pocket, directory: folder, library: library)
        for language in engine.languages {
            XCTAssertEqual(engine.voices(for: language).map(\.name), ["Ann"])
        }
        let ann = engine.voices(for: engine.languages[0])[0]
        XCTAssertTrue(engine.knows(mood: "sad", for: ann))
        XCTAssertFalse(engine.knows(mood: "excited", for: ann))
        XCTAssertFalse(engine.isAvailable(ann), "there is no model in the folder")
    }

    func testRecordingsAreTrimmedOfSilence() {
        let silence = [Float](repeating: 0, count: 24_000)
        let audio = SynthesizedAudio(samples: silence + tone.samples + silence, sampleRate: 24_000)
        XCTAssertEqual(AudioImporter.trimmed(audio).duration, 1.2, accuracy: 0.01)
        XCTAssertEqual(AudioImporter.trimmed(tone, maximum: 0.5).duration, 0.5, accuracy: 0.01)
    }
}

/// Speaks in a voice made from Kokoro's: runs only where the models are,
/// in DYSNOW_CLONING_MODELS, a folder holding both models' folders, and
/// Kokoro's in the settings. DYSNOW_SAMPLES names a folder to keep what was
/// said in, to listen to.
final class CloningTests: XCTestCase {
    private let environment = ProcessInfo.processInfo.environment

    func testSpeaksInAVoiceMadeOfARecording() async throws {
        guard let models = environment["DYSNOW_CLONING_MODELS"].map({ URL(filePath: $0) }), KokoroEngine.isInstalled
        else { throw XCTSkip("needs DYSNOW_CLONING_MODELS and Kokoro") }
        let folder = FileManager.default.temporaryDirectory.appending(path: "dysnow-voices-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = MyVoiceLibrary(directory: folder)

        // Kokoro's Michael says it; ZipVoice and Pocket TTS say something
        // else as him.
        let kokoro = KokoroEngine.shared
        let english = try XCTUnwrap(kokoro.languages.first { $0.id == "en-us" })
        let michael = try XCTUnwrap(kokoro.voices(for: english).first { $0.id == "am_michael" })
        let transcript = "The weather was fine, so we walked along the river to the old mill and back."
        let recording = try await kokoro.synthesize(transcript, voice: michael, language: english, speed: 1)
        let voice = try library.add(name: "Mike", gender: .male, audio: AudioImporter.trimmed(recording),
                                    transcript: transcript)

        let text = "In 1848, a railroad foreman named Phineas Gage was packing powder into a hole."
        for model in CloningModel.allCases {
            let engine = CloningEngine(model: model, directory: models.appending(path: model.package.folderName),
                                       library: library)
            XCTAssertTrue(engine.isAvailable, model.name)
            let mike = try XCTUnwrap(engine.voices(for: english).first)
            XCTAssertEqual(mike.id, voice.id)
            let started = Date.now
            let audio = try await engine.synthesize(text, voice: mike, language: english, speed: 1)
            let took = Date.now.timeIntervalSince(started)
            let fast = try await engine.synthesize(text, voice: mike, language: english, speed: 1.5)
            print("\(model.name): \(took) s for \(audio.duration) s; at 1.5: \(fast.duration) s")
            XCTAssertEqual(audio.sampleRate, 24_000, model.name)
            XCTAssertGreaterThan(audio.duration, 2, model.name)
            XCTAssertLessThan(fast.duration, audio.duration * 0.85, "\(model.name) is not faster at 1.5")
            if let samples = environment["DYSNOW_SAMPLES"] {
                try AudioExporter.write(audio, to: URL(filePath: samples).appending(path: "\(model.rawValue).wav"))
                try AudioExporter.write(fast, to: URL(filePath: samples).appending(path: "\(model.rawValue)-fast.wav"))
            }
        }
    }
}
