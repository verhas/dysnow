import XCTest
@testable import Dysnow

/// Makes a tenth of a second of silence per piece, taking a while about it.
private final class SlowEngine: SpeechEngine {
    let id = "slow"
    let name = "Slow"
    let languages = [SpeechLanguage(id: "en-us", name: "English (US)")]
    let isAvailable = true
    let delay: Duration

    init(delay: Duration = .milliseconds(30)) {
        self.delay = delay
    }

    func voices(for language: SpeechLanguage) -> [SpeechVoice] {
        [SpeechVoice(id: "v", name: "Vic", gender: .male, languageID: language.id)]
    }

    func synthesize(_ text: String, voice: SpeechVoice, language: SpeechLanguage,
                    speed: Float) async throws -> SynthesizedAudio {
        try await Task.sleep(for: delay)
        return SynthesizedAudio(samples: Array(repeating: 0.1, count: 2_400), sampleRate: 24_000)
    }
}

@MainActor
private final class RecordingNotifier: Notifier {
    var posted: [String] = []
    func prepare() {}
    func post(title: String, body: String, fileURL: URL?) {
        posted.append(title)
    }
}

@MainActor
final class ExportQueueTests: XCTestCase {
    private var folder: URL!
    private let engine = SlowEngine()

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "dysnow-queue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func request(sentences: Int) -> SpeechRequest {
        let text = (1...sentences).map { "This is sentence number \($0) of the test text." }.joined(separator: " ")
        let language = engine.languages[0]
        return SpeechRequest(engineID: engine.id, language: language, voice: engine.voices(for: language)[0],
                             speed: 1, blocks: TextReader.blocks(in: text))
    }

    private func waitUntilIdle(_ queue: ExportQueue) async throws {
        let deadline = Date.now.addingTimeInterval(20)
        while queue.isBusy {
            guard Date.now < deadline else { return XCTFail("the queue did not finish") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testJobsRunOneAfterTheOtherInOrder() async throws {
        let queue = ExportQueue(notifier: RecordingNotifier())
        let urls = ["a.wav", "b.m4a", "c.flac"].map { folder.appending(path: $0) }
        for url in urls { queue.enqueue(request(sentences: 3), engine: engine, to: url) }
        XCTAssertEqual(queue.jobs.map(\.state), [.running(0), .waiting, .waiting])
        XCTAssertEqual(queue.waitingCount, 2)
        try await waitUntilIdle(queue)
        for (job, url) in zip(queue.jobs, urls) {
            guard case .finished = job.state else { return XCTFail("\(job.url.lastPathComponent): \(job.state)") }
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testStoppingTheRunningJobGoesOnWithTheNext() async throws {
        let queue = ExportQueue(notifier: RecordingNotifier())
        let first = folder.appending(path: "first.wav"), second = folder.appending(path: "second.wav")
        queue.enqueue(request(sentences: 30), engine: engine, to: first)
        queue.enqueue(request(sentences: 2), engine: engine, to: second)
        try await Task.sleep(for: .milliseconds(100))
        queue.remove(queue.jobs[0].id)
        try await waitUntilIdle(queue)
        XCTAssertEqual(queue.jobs[0].state, .cancelled)
        guard case .finished = queue.jobs[1].state else { return XCTFail("\(queue.jobs[1].state)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testAWaitingJobIsTakenOffTheQueue() async throws {
        let queue = ExportQueue(notifier: RecordingNotifier())
        let kept = folder.appending(path: "kept.wav"), dropped = folder.appending(path: "dropped.wav")
        queue.enqueue(request(sentences: 3), engine: engine, to: kept)
        queue.enqueue(request(sentences: 3), engine: engine, to: dropped)
        queue.remove(queue.jobs[1].id)
        XCTAssertEqual(queue.jobs.map(\.url), [kept])
        try await waitUntilIdle(queue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dropped.path))
        queue.clearDone()
        XCTAssertTrue(queue.jobs.isEmpty)
    }

    func testLongJobsAndTheirEndAreNotified() async throws {
        let notifier = RecordingNotifier()
        let queue = ExportQueue(notifier: notifier)
        queue.notifyAfter = 0
        queue.enqueue(request(sentences: 2), engine: engine, to: folder.appending(path: "one.wav"))
        queue.enqueue(request(sentences: 2), engine: engine, to: folder.appending(path: "two.wav"))
        try await waitUntilIdle(queue)
        XCTAssertEqual(notifier.posted, ["Saved one.wav", "Saved two.wav", "All audio files are saved"])
    }

    func testQuickJobsAreNotNotified() async throws {
        let notifier = RecordingNotifier()
        let queue = ExportQueue(notifier: notifier)
        queue.enqueue(request(sentences: 1), engine: engine, to: folder.appending(path: "one.wav"))
        queue.enqueue(request(sentences: 1), engine: engine, to: folder.appending(path: "two.wav"))
        try await waitUntilIdle(queue)
        XCTAssertEqual(notifier.posted, [])
    }

    func testASingleJobHasNoSecondNotification() async throws {
        let notifier = RecordingNotifier()
        let queue = ExportQueue(notifier: notifier)
        queue.notifyAfter = 0
        queue.enqueue(request(sentences: 1), engine: engine, to: folder.appending(path: "one.wav"))
        try await waitUntilIdle(queue)
        XCTAssertEqual(notifier.posted, ["Saved one.wav"])
    }
}
