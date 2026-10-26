import XCTest
@testable import Dysnow

/// Runs only where a voice is: in the folder in DYSNOW_PIPER_VOICES, or in
/// the one in the settings.
final class PiperTests: XCTestCase {
    private var directory: URL {
        ProcessInfo.processInfo.environment["DYSNOW_PIPER_VOICES"].map { URL(filePath: $0) } ?? PiperEngine.directory
    }

    func testEveryModelIsADownloadOfItsOwn() {
        XCTAssertEqual(Set(PiperModel.all.map(\.package.folderName)).count, PiperModel.all.count)
        for model in PiperModel.all {
            XCTAssertEqual(model.package.folderName, "vits-piper-\(model.id)")
            XCTAssertEqual(model.package.sha256.count, 64, model.id)
            XCTAssertFalse(model.voices.isEmpty, "\(model.id) has no voice")
            XCTAssertFalse(model.licence.isEmpty, model.id)
        }
        XCTAssertEqual(Set(PiperVoice.all.map(\.id)).count, PiperVoice.all.count)
        XCTAssertTrue(PiperVoice.all.allSatisfy { PiperModel.withID($0.modelID) != nil })
    }

    func testTheHungarianVoicesKeepTheirIDs() {
        // Saved in the settings, and in voice tags.
        XCTAssertEqual(PiperVoice.all.filter { $0.language == PiperModel.hungarian }.map(\.id),
                       ["hu_HU-anna-medium", "hu_HU-berta-medium", "hu_HU-imre-medium"])
        XCTAssertEqual(PiperVoice.withID("hu_HU-imre-medium")?.gender, .male)
    }

    func testTheVoicesOfSeveralSpeakers() throws {
        let upmc = try XCTUnwrap(PiperModel.withID("fr_FR-upmc-medium"))
        XCTAssertEqual(upmc.voices.map(\.name), ["Jessica", "Pierre"])
        XCTAssertEqual(upmc.voices.map(\.speaker), [0, 1])
        XCTAssertEqual(upmc.voices.map(\.id), ["fr_FR-upmc-medium", "fr_FR-upmc-medium#1"])
        // Thorsten's emotional model speaks plainly as speaker 4.
        XCTAssertEqual(PiperVoice.withID("de_DE-thorsten_emotional-medium")?.speaker, 4)
    }

    func testOnlyHungarianIsOfferedBeforeAnythingIsDownloaded() {
        let engine = PiperEngine(directory: FileManager.default.temporaryDirectory.appending(path: "no-voices-here"))
        XCTAssertEqual(engine.languages, [PiperModel.hungarian])
        XCTAssertEqual(engine.voices(for: PiperModel.hungarian).count, 3)
        XCTAssertTrue(engine.voices(for: SpeechLanguage(id: "pl", name: "Polish")).isEmpty)
    }

    /// Every model in the folder speaks: DYSNOW_PIPER_VOICES, with the
    /// speech in DYSNOW_SAMPLES/piper when that is set.
    func testEveryModelDownloadedSpeaks() async throws {
        let engine = PiperEngine(directory: directory)
        let installed = PiperEngine.installedModels(in: directory)
        guard !installed.isEmpty else { throw XCTSkip("no Piper voice here") }
        let samples = ProcessInfo.processInfo.environment["DYSNOW_SAMPLES"].map {
            URL(filePath: $0).appending(path: "piper", directoryHint: .isDirectory)
        }
        if let samples { try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true) }
        for voice in PiperVoice.all where installed.contains(voice.modelID) {
            let text = Greeting.text(languageID: voice.language.id, name: voice.name)
            let audio = try await engine.synthesize(text + " 1, 2, 3.", voice: voice.speechVoice,
                                                    language: voice.language, speed: 1)
            XCTAssertGreaterThan(audio.duration, 1, voice.id)
            if let samples {
                try AudioExporter.write(audio, to: samples.appending(path: voice.id.replacingOccurrences(of: "#", with: "_") + ".wav"))
            }
        }
    }

    func testSpeaksHungarianAtTheSpeedAsked() async throws {
        let engine = PiperEngine(directory: directory)
        let language = PiperModel.hungarian
        let installed = PiperVoice.all.filter { $0.language == language }.map(\.speechVoice).filter(engine.isAvailable)
        guard !installed.isEmpty else { throw XCTSkip("no Hungarian Piper voice here") }
        let text = TextReader.blocks(in: "# Árvíztűrő tükörfúrógép\n\nEz egy **próba**: hogy szól a magyar szöveg?")
            .map(\.text).joined(separator: " ")
        for voice in installed {
            let normal = try await engine.synthesize(text, voice: voice, language: language, speed: 1)
            let fast = try await engine.synthesize(text, voice: voice, language: language, speed: 2)
            XCTAssertEqual(normal.sampleRate, 22_050)
            XCTAssertGreaterThan(normal.duration, 2, voice.name)
            XCTAssertLessThan(fast.duration, normal.duration * 0.7, "\(voice.name) is not faster at speed 2")
            let greeting = Greeting.text(languageID: language.id, name: voice.name)
            let greeted = try await engine.synthesize(greeting, voice: voice, language: language, speed: 1)
            XCTAssertGreaterThan(greeted.duration, 1)
        }
    }

    func testAMissingVoiceIsNotAvailable() async {
        let engine = PiperEngine(directory: FileManager.default.temporaryDirectory.appending(path: "no-voices-here"))
        XCTAssertFalse(engine.isAvailable)
        do {
            _ = try await engine.synthesize("Szia", voice: PiperVoice.all[0].speechVoice,
                                            language: PiperModel.hungarian, speed: 1)
            XCTFail("a voice not downloaded spoke")
        } catch {}
    }

    /// Kokoro reads the English, Piper the Hungarian, into one file.
    @MainActor
    func testMixesKokoroAndPiper() async throws {
        let engine = PiperEngine(directory: directory)
        let hungarian = PiperVoice.all.filter { $0.language == PiperModel.hungarian }.map(\.speechVoice)
        guard KokoroEngine.isInstalled, hungarian.contains(where: engine.isAvailable)
        else { throw XCTSkip("needs Kokoro and a Piper voice") }
        let kokoro = KokoroEngine.shared
        let english = try XCTUnwrap(kokoro.languages.first { $0.id == "en-us" })
        let heart = try XCTUnwrap(kokoro.voices(for: english).first { $0.id == "af_heart" })
        let source = #"""
        Good morning, this part is English. <!-- tts:set language="Hungarian" -->Jó reggelt, ez a rész magyar.
        <!-- tts:set language="en-us" model="Kokoro" -->And English again.
        """#
        let request = SpeechRequest(engineID: kokoro.id, language: english, voice: heart, speed: 1,
                                    blocks: TextReader.blocks(in: source))
        XCTAssertEqual(Synthesizer.problems(in: request, for: kokoro, engines: SpeechEngines.all), [])
        let audio = try await Synthesizer.synthesize(request, with: kokoro, engines: SpeechEngines.all)
        XCTAssertEqual(audio.sampleRate, 24_000)
        XCTAssertGreaterThan(audio.duration, 5)
        if let samples = ProcessInfo.processInfo.environment["DYSNOW_SAMPLES"] {
            try AudioExporter.write(audio, to: URL(filePath: samples).appending(path: "mixed.mp3"))
        }
    }
}
