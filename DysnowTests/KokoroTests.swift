import XCTest
@testable import Dysnow

/// Runs only where the model is: the folder in DYSNOW_KOKORO_MODEL, or the
/// one in the settings.
final class KokoroTests: XCTestCase {
    private var directory: URL? {
        if let path = ProcessInfo.processInfo.environment["DYSNOW_KOKORO_MODEL"] {
            return URL(filePath: path)
        }
        return KokoroEngine.isInstalled ? KokoroEngine.directory : nil
    }

    func testEveryVoiceHasALanguage() {
        XCTAssertEqual(KokoroVoice.all.count, 53)
        for voice in KokoroVoice.all {
            XCTAssertNotNil(voice.language, voice.name)
        }
        for language in KokoroLanguage.all {
            XCTAssertFalse(KokoroEngine.shared.voices(for: language.speechLanguage).isEmpty, language.id)
        }
    }

    func testSpeaksEveryLanguage() throws {
        guard let directory else { throw XCTSkip("no Kokoro model here") }
        let engine = KokoroEngine(directory: directory)
        let samples: [String: String] = [
            "en-us": "Hello there, this is a test.",
            "en-gb": "Good morning, this is a test.",
            "es": "Hola, esto es una prueba.",
            "fr": "Bonjour, ceci est un essai.",
            "hi": "नमस्ते, यह एक परीक्षण है।",
            "it": "Ciao, questa è una prova.",
            "ja": "こんにちは、これはテストです。",
            "pt-br": "Olá, isto é um teste.",
            "zh": "你好，这是一个测试。",
        ]
        for language in KokoroLanguage.all {
            let speechLanguage = language.speechLanguage
            let voice = try XCTUnwrap(engine.voices(for: speechLanguage).first)
            let text = try XCTUnwrap(samples[language.id])
            do {
                let audio = try engine.synthesize(text, voice: voice, language: speechLanguage, speed: 1)
                XCTAssertEqual(audio.sampleRate, 24_000)
                XCTAssertGreaterThan(audio.duration, 0.5, "\(language.id) with \(voice.id)")
            } catch {
                XCTFail("\(language.id) with \(voice.id): \(error.localizedDescription)")
            }
        }
    }

    func testEveryVoiceGreetsInItsLanguage() throws {
        guard let directory else { throw XCTSkip("no Kokoro model here") }
        let engine = KokoroEngine(directory: directory)
        for language in engine.languages {
            for voice in engine.voices(for: language) {
                let text = Greeting.text(languageID: language.id, name: voice.spokenName ?? voice.name)
                let audio = try engine.synthesize(text, voice: voice, language: language, speed: 1)
                XCTAssertGreaterThan(audio.duration, 1, "\(voice.id): \(text)")
            }
        }
    }

    func testSavesEveryFormat() throws {
        let audio = SynthesizedAudio(samples: (0..<24_000).map { sin(Float($0) / 10) * 0.5 }, sampleRate: 24_000)
        let folder = FileManager.default.temporaryDirectory.appending(path: "dysnow-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["speech.wav", "speech.m4a", "speech.aiff", "speech.flac"] {
            let url = folder.appending(path: name)
            try AudioExporter.write(audio, to: url)
            let size = try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            XCTAssertGreaterThan(size, 1000, name)
        }
    }
}
