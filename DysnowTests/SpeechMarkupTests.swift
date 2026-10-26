import XCTest
@testable import Dysnow

/// Remembers how it was asked to speak each piece.
private class RecordingEngine: SpeechEngine, @unchecked Sendable {
    struct Call: Equatable {
        let text: String
        let voice: String
        let speed: Float
        var mood: String?
        var language = "en-us"
    }

    var id: String { "recording" }
    var name: String { "Recording" }
    var languages: [SpeechLanguage] { [SpeechLanguage(id: "en-us", name: "English (US)"),
                                       SpeechLanguage(id: "es", name: "Spanish")] }
    let isAvailable = true
    private let lock = NSLock()
    private var recorded: [Call] = []

    var calls: [Call] { lock.withLock { recorded } }

    func voices(for language: SpeechLanguage) -> [SpeechVoice] {
        language.id == "es"
            ? [SpeechVoice(id: "em_alex", name: "Alex", gender: .male, languageID: "es")]
            : [SpeechVoice(id: "af_heart", name: "Heart", gender: .female, languageID: "en-us"),
               SpeechVoice(id: "bm_fable", name: "Fable", gender: .male, languageID: "en-us")]
    }

    func synthesize(_ text: String, voice: SpeechVoice, language: SpeechLanguage,
                    speed: Float) async throws -> SynthesizedAudio {
        record(Call(text: text, voice: voice.id, speed: speed, language: language.id))
    }

    func record(_ call: Call) -> SynthesizedAudio {
        lock.withLock { recorded.append(call) }
        return SynthesizedAudio(samples: [0.1, 0.1], sampleRate: 10)
    }
}

/// Is told the mood instead of having it shown in pace and pauses.
private final class MoodRecordingEngine: RecordingEngine, MoodAwareEngine, @unchecked Sendable {
    func synthesize(_ text: String, voice: SpeechVoice, language: SpeechLanguage, speed: Float,
                    mood: String) async throws -> SynthesizedAudio {
        record(Call(text: text, voice: voice.id, speed: speed, mood: mood, language: language.id))
    }
}

/// Speaks Hungarian only, at another sample rate.
private final class HungarianEngine: RecordingEngine, @unchecked Sendable {
    override var id: String { "other" }
    override var name: String { "Other" }
    override var languages: [SpeechLanguage] { [SpeechLanguage(id: "hu", name: "Hungarian")] }

    override func voices(for language: SpeechLanguage) -> [SpeechVoice] {
        language.id == "hu" ? [SpeechVoice(id: "anna", name: "Anna", gender: .female, languageID: "hu"),
                               SpeechVoice(id: "imre", name: "Imre", gender: .male, languageID: "hu")] : []
    }

    override func synthesize(_ text: String, voice: SpeechVoice, language: SpeechLanguage,
                             speed: Float) async throws -> SynthesizedAudio {
        _ = record(Call(text: text, voice: voice.id, speed: speed, language: language.id))
        return SynthesizedAudio(samples: [0.1, 0.1, 0.1, 0.1], sampleRate: 20)
    }
}

final class SpeechMarkupTests: XCTestCase {
    private func runs(_ source: String) -> [[SpokenRun]] {
        TextReader.blocks(in: source).map(\.runs)
    }

    func testTagsAreNotReadAndCutTheText() {
        let source = #"We won! <!-- tts:mood value="Excited" -->Hooray!<!-- /tts:mood --> Back to normal."#
        XCTAssertEqual(runs(source), [[
            SpokenRun(text: "We won!"),
            SpokenRun(text: "Hooray!", style: SpeechStyle(mood: "excited")),
            SpokenRun(text: "Back to normal."),
        ]])
    }

    func testTagsSpanParagraphsAndNest() {
        let source = """
        <!-- tts:speaker value="Fable" -->
        First paragraph.

        <!-- tts:speed value="120%" --><!-- tts:speed value='0,5' -->Slow and Fable.<!-- /tts:speed -->
        Faster.<!-- /tts:speed -->

        <!-- /tts:speaker -->
        Heart again.
        """
        XCTAssertEqual(runs(source), [
            [SpokenRun(text: "First paragraph.", style: SpeechStyle(speaker: "Fable"))],
            [SpokenRun(text: "Slow and Fable.", style: SpeechStyle(speaker: "Fable", speed: 0.6)),
             SpokenRun(text: "Faster.", style: SpeechStyle(speaker: "Fable", speed: 1.2))],
            [SpokenRun(text: "Heart again.")],
        ])
    }

    func testUnreadableSpeedChangesNothing() {
        let source = #"<!-- tts:speed value="fast" -->Same.<!-- /tts:speed -->"#
        XCTAssertEqual(runs(source), [[SpokenRun(text: "Same.")]])
    }

    func testTagsInCodeBlocksAreIgnored() {
        let source = """
        ```
        <!-- tts:mood value="sad" -->
        ```
        Plain.
        """
        XCTAssertEqual(runs(source), [[SpokenRun(text: "Plain.")]])
    }

    func testFromCursorKeepsTheTagsOpenBeforeIt() {
        let source = #"<!-- tts:mood value="sad" -->One. Two.<!-- /tts:mood --> Three."#
        let cursor = source.range(of: "Two")!.lowerBound
        XCTAssertEqual(TextReader.blocks(in: source, from: cursor).map(\.runs), [[
            SpokenRun(text: "Two.", style: SpeechStyle(mood: "sad")),
            SpokenRun(text: "Three."),
        ]])
    }

    func testSelectionKeepsTheTagsOpenBeforeIt() {
        let source = #"<!-- tts:speaker value="Fable" -->One. Two."#
        let range = source.range(of: "Two.")!
        XCTAssertEqual(TextReader.blocks(in: source, range: range).map(\.runs),
                       [[SpokenRun(text: "Two.", style: SpeechStyle(speaker: "Fable"))]])
    }

    private func request(_ source: String, for engine: RecordingEngine, speed: Float = 1) -> SpeechRequest {
        let language = engine.languages[0]
        return SpeechRequest(engineID: engine.id, language: language, voice: engine.voices(for: language)[0],
                             speed: speed, blocks: TextReader.blocks(in: source))
    }

    @MainActor
    func testSpeakersSpeedsAndMoodsReachTheEngine() async throws {
        let engine = RecordingEngine()
        let source = """
        Plain sentence here. <!-- tts:speaker value="fable" -->Fable speaks.<!-- /tts:speaker -->
        <!-- tts:speaker value="Alex" --><!-- tts:speed value="1.5" -->Alex, quickly.<!-- /tts:speed -->
        <!-- /tts:speaker --><!-- tts:mood value="sad" -->A sad one.<!-- /tts:mood -->
        """
        _ = try await Synthesizer.synthesize(request(source, for: engine, speed: 1.2), with: engine)
        let calls = engine.calls
        XCTAssertEqual(calls.map(\.text), ["Plain sentence here.", "Fable speaks.", "Alex, quickly.", "A sad one."])
        // Alex is a Spanish voice, found though English is spoken.
        XCTAssertEqual(calls.map(\.voice), ["af_heart", "bm_fable", "em_alex", "af_heart"])
        let speeds = [1.2, 1.2, 1.8, 1.2 * SpeechMarkup.prosody(for: "sad").speed]
        for (call, speed) in zip(calls, speeds) {
            XCTAssertEqual(Double(call.speed), speed, accuracy: 0.0001, call.text)
        }
    }

    @MainActor
    func testAnEngineThatKnowsMoodsIsToldThem() async throws {
        let engine = MoodRecordingEngine()
        let source = #"<!-- tts:mood value="excited" -->Yes!<!-- /tts:mood -->"#
        _ = try await Synthesizer.synthesize(request(source, for: engine), with: engine)
        XCTAssertEqual(engine.calls, [.init(text: "Yes!", voice: "af_heart", speed: 1, mood: "excited")])
    }

    @MainActor
    func testTheLanguageChangesWhereTheTextSays() async throws {
        let engine = RecordingEngine()
        let source = #"""
        Hello. <!-- tts:language value="Spanish" -->Hola, <!-- tts:speaker value="Alex" -->amigos.
        <!-- /tts:speaker --><!-- /tts:language --> Bye. <!-- tts:language value="Klingon" -->Qapla'!
        """#
        let request = request(source, for: engine)
        XCTAssertEqual(Synthesizer.unknownLanguages(in: request, for: engine), ["Klingon"])
        _ = try await Synthesizer.synthesize(request, with: engine)
        XCTAssertEqual(engine.calls.map(\.language), ["en-us", "es", "es", "en-us", "en-us"])
        XCTAssertEqual(engine.calls.map(\.voice), ["af_heart", "af_heart", "em_alex", "af_heart", "af_heart"])
    }

    func testSetChangesWhatItSaysUntilTheNext() {
        let source = #"""
        <!-- tts:set language="hu" model="Piper" speaker="" -->A <!-- tts:speed value="2" -->b<!-- /tts:speed -->
        <!-- tts:set speed="0.5" mood="sad" -->c <!-- tts:set speed="1.5" -->d<!-- /tts:set --> e
        """#
        XCTAssertEqual(runs(source), [[
            SpokenRun(text: "A", style: SpeechStyle(language: "hu", model: "Piper")),
            SpokenRun(text: "b", style: SpeechStyle(speed: 2, language: "hu", model: "Piper")),
            SpokenRun(text: "c", style: SpeechStyle(mood: "sad", speed: 0.5, language: "hu", model: "Piper")),
            SpokenRun(text: "d", style: SpeechStyle(mood: "sad", speed: 1.5, language: "hu", model: "Piper")),
            SpokenRun(text: "e", style: SpeechStyle(mood: "sad", speed: 0.5, language: "hu", model: "Piper")),
        ]])
    }

    @MainActor
    func testLanguagesOfAnotherModelAreReadByIt() async throws {
        let engine = RecordingEngine(), other = HungarianEngine()
        let source = #"""
        Hello. <!-- tts:set language="Hungarian" -->Szia. <!-- tts:set speaker="Imre" -->Szervusz.
        <!-- tts:set language="en-us" model="recording" speaker="Fable" -->Back.
        """#
        let request = request(source, for: engine)
        XCTAssertEqual(Synthesizer.problems(in: request, for: engine, engines: [engine, other]), [])
        let audio = try await Synthesizer.synthesize(request, with: engine, engines: [engine, other])
        XCTAssertEqual(engine.calls.map(\.text), ["Hello.", "Back."])
        XCTAssertEqual(engine.calls.map(\.voice), ["af_heart", "bm_fable"])
        XCTAssertEqual(other.calls.map(\.text), ["Szia.", "Szervusz."])
        // The chosen voice is a woman's: so is the other model's first pick.
        XCTAssertEqual(other.calls.map(\.voice), ["anna", "imre"])
        XCTAssertEqual(other.calls.map(\.language), ["hu", "hu"])
        // Its speech, at 20 Hz, is joined to the rest at 10.
        XCTAssertEqual(audio.sampleRate, 10)
    }

    @MainActor
    func testWhatCannotBeFollowedIsReported() {
        let engine = RecordingEngine(), other = HungarianEngine()
        let request = request(#"<!-- tts:set model="Nope" language="Klingon" -->Hm. <!-- tts:set model="other" language="es" -->Hola."#,
                              for: engine)
        XCTAssertEqual(Synthesizer.problems(in: request, for: engine, engines: [engine, other]),
                       [.model("Nope"), .language("Klingon"), .language("es")])
    }

    @MainActor
    func testUnknownSpeakersAreReportedAndReadInTheChosenVoice() async throws {
        let engine = RecordingEngine()
        let request = request(#"<!-- tts:speaker value="Fabel" -->Who?"#, for: engine)
        XCTAssertEqual(Synthesizer.unknownSpeakers(in: request, for: engine), ["Fabel"])
        _ = try await Synthesizer.synthesize(request, with: engine)
        XCTAssertEqual(engine.calls.map(\.voice), ["af_heart"])
    }
}
