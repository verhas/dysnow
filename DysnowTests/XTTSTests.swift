import XCTest
@testable import Dysnow

final class XTTSEnvironmentTests: XCTestCase {
    func testTheLibrariesArePinned() throws {
        let url = try XCTUnwrap(XTTSEnvironment.requirements)
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").filter { !$0.hasPrefix("#") }
        XCTAssertGreaterThan(lines.count, 100)
        for line in lines {
            XCTAssertNotNil(line.wholeMatch(of: #/[A-Za-z0-9_.\-]+==[0-9A-Za-z.+]+/#), String(line))
        }
        XCTAssertTrue(lines.contains("TTS==0.22.0"))
        XCTAssertFalse(lines.contains { $0.lowercased().hasPrefix("pyqt5") })
    }

    func testTheServerIsInTheApp() {
        XCTAssertNotNil(XTTSEnvironment.server)
    }

    func testOnly311ForThisMacIsUsable() {
        let url = URL(filePath: "/x/python3")
        XCTAssertTrue(XTTSEnvironment.Python(url: url, version: "3.11.15", machine: XTTSEnvironment.Python.machine).isUsable)
        XCTAssertFalse(XTTSEnvironment.Python(url: url, version: "3.12.1", machine: XTTSEnvironment.Python.machine).isUsable)
        XCTAssertFalse(XTTSEnvironment.Python(url: url, version: "3.1.4", machine: XTTSEnvironment.Python.machine).isUsable)
        XCTAssertFalse(XTTSEnvironment.Python(url: url, version: "3.11.15", machine: "i386").isUsable)
    }

    /// Where there is one: on the developer's Mac, uv's.
    func testFindsPython311() async throws {
        let found = await XTTSEnvironment.findPython()
        guard let python = found.usable else { throw XCTSkip("no Python 3.11 here") }
        XCTAssertTrue(python.version.hasPrefix("3.11."))
        XCTAssertTrue(found.others.allSatisfy { !$0.isUsable })
    }

    func testAnEnvironmentDysnowMadeIsReadyOnlyWithTheSameRequirements() throws {
        // Not Dysnow's own environment: one picked is taken as it is.
        let folder = FileManager.default.temporaryDirectory.appending(path: "xtts-env-\(UUID().uuidString)")
        XCTAssertFalse(XTTSEnvironment.isReady(folder))
    }
}

/// Speaks with XTTS v2: needs DYSNOW_XTTS_ENVIRONMENT, a Python 3.11
/// environment with its libraries, and DYSNOW_XTTS_MODEL, the model's folder.
final class XTTSSpeakingTests: XCTestCase {
    func testSpeaksInABuiltInVoiceAndInARecordedOne() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let environment = env["DYSNOW_XTTS_ENVIRONMENT"].map({ URL(filePath: $0) }),
              let model = env["DYSNOW_XTTS_MODEL"].map({ URL(filePath: $0) }) else {
            throw XCTSkip("needs DYSNOW_XTTS_ENVIRONMENT and DYSNOW_XTTS_MODEL")
        }
        let library = MyVoiceLibrary(directory: FileManager.default.temporaryDirectory
            .appending(path: "xtts-voices-\(UUID().uuidString)"))
        // A voice of the user's, recorded by Kokoro when it is there.
        var mine: MyVoice?
        if KokoroEngine.isInstalled {
            let kokoro = KokoroEngine.shared
            let english = try XCTUnwrap(kokoro.languages.first { $0.id == "en-us" })
            let heart = try XCTUnwrap(kokoro.voices(for: english).first { $0.id == "af_heart" })
            let recording = try await kokoro.synthesize("This is my voice, recorded for a test of cloning. It is a "
                + "calm and clear voice.", voice: heart, language: english, speed: 1)
            mine = try library.add(name: "Heart", gender: .female, audio: recording, transcript: "")
        }
        let engine = XTTSEngine(library: library, environment: environment, model: model)
        XCTAssertTrue(engine.isAvailable)
        let check = try await engine.check(environment)
        XCTAssertEqual(check.python?.hasPrefix("3.11."), true)

        let english = try XCTUnwrap(engine.languages.first { $0.id == "en-us" })
        let ana = try XCTUnwrap(engine.voices(for: english).first { $0.id == "Ana Florence" })
        let audio = try await engine.synthesize("Hello from Dysnow.", voice: ana, language: english, speed: 1)
        XCTAssertEqual(audio.sampleRate, 24_000)
        XCTAssertGreaterThan(audio.duration, 0.8)

        let samples = env["DYSNOW_SAMPLES"].map { URL(filePath: $0) }
        if let samples { try AudioExporter.write(audio, to: samples.appending(path: "xtts-ana.wav")) }
        if let mine {
            let hungarian = try XCTUnwrap(engine.languages.first { $0.id == "hu" })
            let own = try XCTUnwrap(engine.voices(for: hungarian).first { $0.id == mine.id })
            let cloned = try await engine.synthesize("Jó reggelt, ez egy klónozott hang.", voice: own,
                                                     language: hungarian, speed: 1.2)
            XCTAssertGreaterThan(cloned.duration, 1)
            if let samples { try AudioExporter.write(cloned, to: samples.appending(path: "xtts-heart-hu.wav")) }
        }
        await engine.unload()
    }

    /// A voice picked says hello while the model is still loading: it waits
    /// for that load, and says until then that it is loading.
    func testSpeaksWhileTheModelLoads() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let environment = env["DYSNOW_XTTS_ENVIRONMENT"].map({ URL(filePath: $0) }),
              let model = env["DYSNOW_XTTS_MODEL"].map({ URL(filePath: $0) }) else {
            throw XCTSkip("needs DYSNOW_XTTS_ENVIRONMENT and DYSNOW_XTTS_MODEL")
        }
        let engine = XTTSEngine(environment: environment, model: model)
        let hungarian = try XCTUnwrap(engine.languages.first { $0.id == "hu" })
        let szofi = try XCTUnwrap(engine.voices(for: hungarian).first { $0.id == "Szofi Granger" })
        let before = await engine.startingNote()
        XCTAssertNotNil(before)
        async let prepared: Void = engine.prepare()
        let audio = try await engine.synthesize("Szia, Szofi Granger vagyok.", voice: szofi, language: hungarian,
                                                speed: 1)
        await prepared
        let after = await engine.startingNote()
        XCTAssertNil(after)
        XCTAssertGreaterThan(audio.duration, 1)
        // Faded out where the word said after it was cut off.
        XCTAssertLessThan(audio.samples.suffix(24).map(abs).max() ?? 1, 0.01)
        if let samples = env["DYSNOW_SAMPLES"] {
            try AudioExporter.write(audio, to: URL(filePath: samples).appending(path: "xtts-szofi-hu.wav"))
        }
        await engine.unload()
    }

    /// Each way of ending what XTTS says speaks the whole sentence.
    func testEndsEachWay() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let environment = env["DYSNOW_XTTS_ENVIRONMENT"].map({ URL(filePath: $0) }),
              let model = env["DYSNOW_XTTS_MODEL"].map({ URL(filePath: $0) }) else {
            throw XCTSkip("needs DYSNOW_XTTS_ENVIRONMENT and DYSNOW_XTTS_MODEL")
        }
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: XTTSEngine.endingKey)
        defer { defaults.set(saved, forKey: XTTSEngine.endingKey) }
        let engine = XTTSEngine(environment: environment, model: model)
        let hungarian = try XCTUnwrap(engine.languages.first { $0.id == "hu" })
        let szofi = try XCTUnwrap(engine.voices(for: hungarian).first { $0.id == "Szofi Granger" })
        for ending in XTTSEngine.Ending.allCases {
            defaults.set(ending.rawValue, forKey: XTTSEngine.endingKey)
            XCTAssertEqual(engine.speechSettings, "xtts.ending=" + ending.rawValue)
            let audio = try await engine.synthesize("Az egész délután ráment, de senki sem bánta.", voice: szofi,
                                                    language: hungarian, speed: 1)
            XCTAssertGreaterThan(audio.duration, 2, ending.rawValue)
            if let samples = env["DYSNOW_SAMPLES"] {
                try AudioExporter.write(audio, to: URL(filePath: samples).appending(path: "xtts-\(ending.rawValue).wav"))
            }
        }
        await engine.unload()
    }

    /// A paragraph goes to XTTS in a few pieces, not a sentence at a time.
    func testReadsAParagraphInPieces() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let environment = env["DYSNOW_XTTS_ENVIRONMENT"].map({ URL(filePath: $0) }),
              let model = env["DYSNOW_XTTS_MODEL"].map({ URL(filePath: $0) }) else {
            throw XCTSkip("needs DYSNOW_XTTS_ENVIRONMENT and DYSNOW_XTTS_MODEL")
        }
        let engine = XTTSEngine(environment: environment, model: model)
        let hungarian = try XCTUnwrap(engine.languages.first { $0.id == "hu" })
        let ana = try XCTUnwrap(engine.voices(for: hungarian).first { $0.id == "Ana Florence" })
        let text = "Az idő jó volt, ezért lesétáltunk a folyó mentén az öreg malomig és vissza. Az egész délután "
            + "ráment, de senki sem bánta. Este korán lefeküdtünk. Holnap reggel korán indulunk tovább, a hegyek felé."
        XCTAssertEqual(TextChunker.packed(text, maximumLength: try XCTUnwrap(engine.longestPiece(in: hungarian)),
                                          quickStart: true).count, 2)
        let request = SpeechRequest(engineID: engine.id, language: hungarian, voice: ana, speed: 1,
                                    blocks: TextReader.blocks(in: text))
        let audio = try await Synthesizer.synthesize(request, with: engine, engines: [engine])
        XCTAssertGreaterThan(audio.duration, 8)
        if let samples = env["DYSNOW_SAMPLES"] {
            try AudioExporter.write(audio, to: URL(filePath: samples).appending(path: "xtts-paragraph-hu.wav"))
        }
        let hindi = try XCTUnwrap(engine.languages.first { $0.id == "hi" })
        let said = try await engine.synthesize("नमस्ते, आप कैसे हैं?", voice: ana, language: hindi, speed: 1)
        XCTAssertGreaterThan(said.duration, 0.5)
        await engine.unload()
    }
}

/// Sets up the environment as the app does, into DYSNOW_HOME: only with
/// DYSNOW_XTTS_SETUP set, as pip downloads about a gigabyte.
final class XTTSSetUpTests: XCTestCase {
    func testSetsUpTheEnvironment() async throws {
        guard ProcessInfo.processInfo.environment["DYSNOW_XTTS_SETUP"] != nil,
              ProcessInfo.processInfo.environment["DYSNOW_HOME"] != nil else {
            throw XCTSkip("needs DYSNOW_XTTS_SETUP and DYSNOW_HOME")
        }
        let found = await XTTSEnvironment.findPython()
        let python = try XCTUnwrap(found.usable)
        let progress = ProgressLog()
        try await XTTSEnvironment.setUp(with: python) { line, fraction in progress.add(line, fraction) }
        XCTAssertTrue(XTTSEnvironment.isReady(XTTSEnvironment.defaultEnvironment))
        XCTAssertGreaterThan(progress.count, 100)
        XCTAssertEqual(progress.last, 1)
        let engine = XTTSEngine(environment: XTTSEnvironment.defaultEnvironment)
        let check = try await engine.check(XTTSEnvironment.defaultEnvironment)
        XCTAssertEqual(check.tts, "0.22.0")
        await engine.unload()
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines = 0
    private var fraction = 0.0

    func add(_ line: String, _ value: Double) {
        lock.withLock {
            lines += 1
            if value >= 0 { fraction = value }
        }
    }

    var count: Int { lock.withLock { lines } }
    var last: Double { lock.withLock { fraction } }
}
