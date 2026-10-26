import Foundation

/// `xtts_server.py`, running in the XTTS environment's Python: started when
/// first needed and kept running, the model loaded in it once. Requests go
/// to its stdin and answers come from its stdout, a line of JSON each; see
/// the script for what they are.
actor XTTSServer {
    struct Request: Encodable, Sendable {
        var id = 0
        let command: String
        var model: String?
        var text: String?
        var language: String?
        var speaker: String?
        var reference: [String]?
        var speed: Double?
        var ending: String?
        var output: String?
    }

    struct Answer: Decodable, Sendable {
        let id: Int?
        let event: String?
        let ok: Bool?
        let error: String?
        // check
        let python: String?
        let torch: String?
        let tts: String?
        // load
        let speakers: [String]?
        let languages: [String]?
        // speak
        let output: String?
    }

    private var process: Process?
    private var input: FileHandle?
    private var environment: URL?
    private var loadedModel: URL?
    /// The model being loaded: those asking for it meanwhile wait for it,
    /// rather than load it again.
    private var loading: (folder: URL, environment: URL, task: Task<Answer, Error>)?
    private var nextID = 1
    private var waiting: [Int: CheckedContinuation<Answer, Error>] = [:]
    /// The last lines it wrote to stderr: what went wrong, when something did.
    private var log: [String] = []

    /// The answer to a request; started, in `environment`, when it is not
    /// running.
    func send(_ request: Request, in environment: URL) async throws -> Answer {
        if process?.isRunning != true || self.environment != environment { try start(in: environment) }
        var request = request
        request.id = nextID
        nextID += 1
        var line = try JSONEncoder().encode(request)
        line.append(UInt8(ascii: "\n"))
        let answer = try await withCheckedThrowingContinuation { continuation in
            waiting[request.id] = continuation
            do {
                try input?.write(contentsOf: line)
            } catch {
                waiting[request.id] = nil
                continuation.resume(throwing: error)
            }
        }
        guard answer.ok == true else {
            throw SpeechError.failed("XTTS: " + (answer.error ?? "it failed."))
        }
        return answer
    }

    /// Loads the model in `folder`, unless it is the one loaded, or being
    /// loaded.
    func load(_ folder: URL, in environment: URL) async throws -> Answer? {
        if isLoaded(folder, in: environment) { return nil }
        if let loading, loading.folder == folder, loading.environment == environment {
            return try await loading.task.value
        }
        let task = Task { try await send(Request(command: "load", model: folder.path), in: environment) }
        loading = (folder, environment, task)
        defer { if loading?.task == task { loading = nil } }
        let answer = try await task.value
        loadedModel = folder
        return answer
    }

    func isLoaded(_ folder: URL, in environment: URL) -> Bool {
        loadedModel == folder && process?.isRunning == true && self.environment == environment
    }

    func stop() {
        loading = nil
        end()
    }

    /// Lets the process go. A load under way is left alone: it is the one
    /// starting the process.
    private func end() {
        if let input, process?.isRunning == true {
            try? input.write(contentsOf: Data("{\"id\": 0, \"command\": \"quit\"}\n".utf8))
        }
        let running = process
        process = nil
        input = nil
        loadedModel = nil
        // It is given a moment to quit, then made to.
        Task.detached {
            try? await Task.sleep(for: .seconds(2))
            if running?.isRunning == true { running?.terminate() }
        }
    }

    /// What it last wrote to stderr.
    var recentLog: String { log.suffix(20).joined(separator: "\n") }

    private func start(in environment: URL) throws {
        end()
        guard let script = XTTSEnvironment.server else {
            throw SpeechError.failed("The XTTS server is missing from Dysnow.")
        }
        let process = Process()
        process.executableURL = XTTSEnvironment.python(in: environment)
        process.arguments = ["-I", script.path]
        process.environment = XTTSEnvironment.environmentVariables
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { [weak self] _ in
            Task { await self?.ended() }
        }
        try process.run()
        self.process = process
        self.input = input.fileHandleForWriting
        self.environment = environment
        log = []
        // Read as they come; Foundation's async bytes read every file on one
        // queue, where the quiet stderr would hold the answers back.
        LineReader.read(output.fileHandleForReading) { [weak self] line in
            guard let answer = try? JSONDecoder().decode(Answer.self, from: Data(line.utf8)) else { return }
            Task { await self?.received(answer) }
        }
        LineReader.read(errors.fileHandleForReading) { [weak self] line in
            Task { await self?.logged(line) }
        }
    }

    private func received(_ answer: Answer) {
        guard let id = answer.id, let continuation = waiting.removeValue(forKey: id) else { return }
        continuation.resume(returning: answer)
    }

    private func logged(_ line: String) {
        log.append(line)
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    /// It stopped: what was asked of it fails, with what it said last.
    private func ended() {
        guard process?.isRunning != true else { return }
        let failed = waiting
        waiting = [:]
        loadedModel = nil
        let reason = log.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "no reason given"
        for continuation in failed.values {
            continuation.resume(throwing: SpeechError.failed("XTTS stopped: \(reason)"))
        }
    }
}

/// Hands on what a pipe gets a line at a time, as it gets it, on a thread of
/// the file handle's own.
enum LineReader {
    static func read(_ handle: FileHandle, line: @escaping @Sendable (String) -> Void) {
        let buffer = LineBuffer()
        handle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                // The end: what is left is the last line.
                handle.readabilityHandler = nil
                buffer.rest().map(line)
                return
            }
            buffer.append(data).forEach(line)
        }
    }
}

private final class LineBuffer: @unchecked Sendable {
    private var pending = Data()
    private let lock = NSLock()

    /// The lines completed by `data`.
    func append(_ data: Data) -> [String] {
        lock.withLock {
            pending.append(data)
            var lines: [String] = []
            while let end = pending.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(String(decoding: pending[pending.startIndex..<end], as: UTF8.self))
                pending = Data(pending[pending.index(after: end)...])
            }
            return lines
        }
    }

    func rest() -> String? {
        lock.withLock {
            defer { pending = Data() }
            return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
        }
    }
}
