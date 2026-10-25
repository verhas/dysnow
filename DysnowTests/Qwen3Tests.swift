import XCTest
@testable import Dysnow

/// The download runs only when DYSNOW_QWEN3_DOWNLOAD_TO names a folder, the
/// speaking only where a model is: in DYSNOW_QWEN3_MODEL, or in the settings.
/// DYSNOW_SAMPLES names a folder to keep what was said in, to listen to.
final class Qwen3Tests: XCTestCase {
    private let environment = ProcessInfo.processInfo.environment

    private var modelFolder: URL? {
        if let path = environment["DYSNOW_QWEN3_MODEL"] { return URL(filePath: path) }
        return Qwen3Engine.isInstalled(Qwen3Engine.variant) ? Qwen3Engine.folder(of: Qwen3Engine.variant) : nil
    }

    func testDownloadsTheSmallModel() async throws {
        guard let path = environment["DYSNOW_QWEN3_DOWNLOAD_TO"] else { throw XCTSkip("no download asked for") }
        let parent = URL(filePath: path)
        try await HuggingFaceDownloader.install(Qwen3Variant.small.model, into: parent) { _ in }
        XCTAssertTrue(Qwen3Engine.holdsModel(Qwen3Engine.folder(of: .small, in: parent)))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: parent.appending(path: Qwen3Variant.small.model.folderName + ".partial").path))
    }

    func testEveryLanguageHasEverySpeaker() {
        let engine = Qwen3Engine()
        guard Qwen3Engine.isSupported else { return XCTAssertTrue(engine.languages.isEmpty) }
        XCTAssertEqual(engine.languages.count, 11)
        for language in engine.languages {
            XCTAssertEqual(engine.voices(for: language).count, 9, language.id)
        }
    }

    func testSpeaksAndIsToldTheMood() async throws {
        guard let folder = modelFolder else { throw XCTSkip("no Qwen3-TTS model here") }
        let engine = Qwen3Engine(directory: folder)
        XCTAssertTrue(engine.isAvailable)
        let english = try XCTUnwrap(engine.languages.first { $0.id == "en-us" })
        let ryan = try XCTUnwrap(engine.voices(for: english).first { $0.id == "Ryan" })
        let text = "We were two goals down, and then we scored three times in ten minutes!"

        let started = Date.now
        let neutral = try await engine.synthesize(text, voice: ryan, language: english, speed: 1)
        let firstCall = Date.now.timeIntervalSince(started)
        let excited = try await engine.synthesize(text, voice: ryan, language: english, speed: 1, mood: "excited")
        let sad = try await engine.synthesize(text, voice: ryan, language: english, speed: 1, mood: "sad")
        let fast = try await engine.synthesize(text, voice: ryan, language: english, speed: 1.5)
        let german = try XCTUnwrap(engine.languages.first { $0.id == "de" })
        let vivian = try XCTUnwrap(engine.voices(for: german).first { $0.id == "Vivian" })
        let greeting = try await engine.synthesize(Greeting.text(languageID: "de", name: "Vivian"), voice: vivian,
                                                   language: german, speed: 1)
        print("Qwen3-TTS: first call (with loading) \(firstCall) s for \(neutral.duration) s of speech")

        for audio in [neutral, excited, sad, greeting] {
            XCTAssertEqual(audio.sampleRate, 24_000)
            XCTAssertGreaterThan(audio.duration, 1)
        }
        // Generated anew each time, so only roughly two thirds as long.
        XCTAssertLessThan(fast.duration, neutral.duration * 0.85)

        if let samples = environment["DYSNOW_SAMPLES"] {
            let folder = URL(filePath: samples)
            for (name, audio) in [("neutral", neutral), ("excited", excited), ("sad", sad), ("fast", fast),
                                  ("german-greeting", greeting)] {
                try AudioExporter.write(audio, to: folder.appending(path: "qwen3-\(name).wav"))
            }
        }
    }
}

final class TimeStretchTests: XCTestCase {
    private let tone = SynthesizedAudio(samples: (0..<48_000).map { sin(Float($0) / 8) * 0.5 }, sampleRate: 24_000)

    func testFasterIsShorter() throws {
        let fast = try TimeStretch.apply(tone, rate: 2)
        XCTAssertEqual(fast.duration, 1, accuracy: 0.05)
        XCTAssertGreaterThan(fast.samples.map(abs).max() ?? 0, 0.1, "it is silence")
    }

    func testSlowerIsLonger() throws {
        XCTAssertEqual(try TimeStretch.apply(tone, rate: 0.5).duration, 4, accuracy: 0.1)
    }

    func testTheSameSpeedChangesNothing() throws {
        XCTAssertEqual(try TimeStretch.apply(tone, rate: 1).samples, tone.samples)
    }
}

final class Qwen3InstructionTests: XCTestCase {
    func testMoodsBecomeInstructions() {
        XCTAssertEqual(Qwen3Engine.instruction(for: "excited"), "very excited and energetic")
        XCTAssertEqual(Qwen3Engine.instruction(for: "whispering"), "in a whispering way")
        XCTAssertEqual(Qwen3Engine.instruction(for: "like a sports commentator"), "like a sports commentator")
    }
}
