import Foundation
import Observation

/// Speech being saved to files, one file at a time, in the order asked for.
/// Saving runs beside playback, so the text can be listened to meanwhile.
/// A file that took longer than `notifyAfter` to make is announced with a
/// notification when done, and so is the end of a run of several files.
@MainActor @Observable
final class ExportQueue {
    struct Job: Identifiable, Equatable {
        enum State: Equatable {
            case waiting
            /// From 0 to 1.
            case running(Double)
            /// With how long the speech is.
            case finished(TimeInterval)
            case failed(String)
            case cancelled
        }

        let id = UUID()
        let url: URL
        let voiceName: String
        let languageName: String
        /// The start of the text, to tell the jobs apart.
        let preview: String
        var state = State.waiting

        var isDone: Bool {
            switch state {
            case .waiting, .running: false
            case .finished, .failed, .cancelled: true
            }
        }
    }

    private(set) var jobs: [Job] = []
    var notifyAfter: TimeInterval = 5

    private let notifier: Notifier
    /// What each job not yet done is to make, kept apart from the jobs shown.
    private var work: [UUID: (request: SpeechRequest, engine: any SpeechEngine, audio: SynthesizedAudio?)] = [:]
    private var runningID: UUID?
    private var runningTask: Task<Void, Never>?
    /// The run of jobs since the queue was last empty.
    private var batch: (start: Date, finished: Int, failed: Int)?

    init(notifier: Notifier) {
        self.notifier = notifier
    }

    var running: Job? { jobs.first { $0.id == runningID } }
    var waitingCount: Int { jobs.count { $0.state == .waiting } }
    var isBusy: Bool { runningID != nil }
    var hasDoneJobs: Bool { jobs.contains(where: \.isDone) }

    /// Queues a file to be made; `audio` is the speech when it is made already.
    func enqueue(_ request: SpeechRequest, engine: any SpeechEngine, to url: URL, audio: SynthesizedAudio? = nil) {
        let text = request.blocks.map(\.text).joined(separator: " ")
        let job = Job(url: url, voiceName: request.voice.name, languageName: request.language.name,
                      preview: text.count > 80 ? text.prefix(80) + "…" : text)
        jobs.append(job)
        work[job.id] = (request, engine, audio)
        notifier.prepare()
        startNext()
    }

    /// Stops the job if it is being made, or takes it off the queue if it is
    /// waiting; a job done is taken off the list.
    func remove(_ id: UUID) {
        if id == runningID {
            runningTask?.cancel()
            return
        }
        jobs.removeAll { $0.id == id }
        work[id] = nil
    }

    func clearDone() {
        jobs.removeAll(where: \.isDone)
    }

    private func startNext() {
        guard runningID == nil else { return }
        guard let next = jobs.first(where: { $0.state == .waiting }) else {
            finishBatch()
            return
        }
        if batch == nil { batch = (Date.now, 0, 0) }
        runningID = next.id
        update(next.id) { $0.state = .running(0) }
        runningTask = Task { await run(next) }
    }

    private func run(_ job: Job) async {
        let started = Date.now
        guard let (request, engine, made) = work[job.id] else { return }
        do {
            let audio: SynthesizedAudio
            if let made {
                audio = made
            } else {
                // The last bit is the writing.
                audio = try await Synthesizer.synthesize(request, with: engine, engines: SpeechEngines.all) {
                    [weak self] done, _ in
                    self?.update(job.id) { $0.state = .running(done * 0.97) }
                }
            }
            try Task.checkCancellation()
            try await Task.detached(priority: .userInitiated) {
                try AudioExporter.write(audio, to: job.url)
            }.value
            update(job.id) { $0.state = .finished(audio.duration) }
            batch?.finished += 1
            if Date.now.timeIntervalSince(started) > notifyAfter {
                notifier.post(title: "Saved \(job.url.lastPathComponent)",
                              body: "\(Self.format(audio.duration)) of speech, read by \(job.voiceName).",
                              fileURL: job.url)
            }
        } catch is CancellationError {
            update(job.id) { $0.state = .cancelled }
        } catch {
            update(job.id) { $0.state = .failed(error.localizedDescription) }
            batch?.failed += 1
            if Date.now.timeIntervalSince(started) > notifyAfter {
                notifier.post(title: "\(job.url.lastPathComponent) could not be saved",
                              body: error.localizedDescription, fileURL: nil)
            }
        }
        work[job.id] = nil
        runningID = nil
        runningTask = nil
        startNext()
    }

    /// The queue has run empty: after several files, and long enough to have
    /// looked away, that is announced too.
    private func finishBatch() {
        guard let batch else { return }
        self.batch = nil
        let total = batch.finished + batch.failed
        guard total > 1, Date.now.timeIntervalSince(batch.start) > notifyAfter else { return }
        let failures = batch.failed == 0 ? "" : " \(batch.failed) of them could not be saved."
        notifier.post(title: "All audio files are saved",
                      body: "\(total) files made in \(Self.format(Date.now.timeIntervalSince(batch.start))).\(failures)",
                      fileURL: nil)
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    static func format(_ duration: TimeInterval) -> String {
        Duration.seconds(duration).formatted(.time(pattern: duration >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}
