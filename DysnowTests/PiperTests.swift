import XCTest
@testable import Dysnow

/// Runs only where a voice is: in the folder in DYSNOW_PIPER_VOICES, or in
/// the one in the settings.
final class PiperTests: XCTestCase {
    private var directory: URL {
        ProcessInfo.processInfo.environment["DYSNOW_PIPER_VOICES"].map { URL(filePath: $0) } ?? PiperEngine.directory
    }

    func testEveryVoiceIsInADownloadOfItsOwn() {
        XCTAssertEqual(Set(PiperVoice.all.map(\.package.folderName)).count, PiperVoice.all.count)
        for voice in PiperVoice.all {
            XCTAssertEqual(voice.package.folderName, "vits-piper-\(voice.id)")
            XCTAssertEqual(voice.package.sha256.count, 64)
        }
    }

    func testSpeaksHungarianAtTheSpeedAsked() async throws {
        let engine = PiperEngine(directory: directory)
        let installed = PiperVoice.all.map(\.speechVoice).filter(engine.isAvailable)
        guard !installed.isEmpty else { throw XCTSkip("no Piper voice here") }
        let language = PiperVoice.hungarian
        let text = MarkdownReader.blocks(in: "# Árvíztűrő tükörfúrógép\n\nEz egy **próba**: hogy szól a magyar szöveg?")
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
                                            language: PiperVoice.hungarian, speed: 1)
            XCTFail("a voice not downloaded spoke")
        } catch {}
    }
}
