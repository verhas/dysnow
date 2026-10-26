import Foundation

/// What XTTS v2 runs in: Python 3.11 -- which Dysnow does not bring, it is
/// found on the Mac -- and a virtual environment of its libraries, made by
/// Dysnow in `~/.dysnow/xtts/venv`, or one the user already has.
enum XTTSEnvironment {
    static var root: URL { DysnowHome.root.appending(path: "xtts", directoryHint: .isDirectory) }
    static var defaultEnvironment: URL { root.appending(path: "venv", directoryHint: .isDirectory) }

    /// The settings keys of a Python and an environment the user picked.
    static let pythonKey = "xtts.python"
    static let environmentKey = "xtts.environment"

    /// The environment used: the one picked, or Dysnow's own.
    static var environment: URL {
        UserDefaults.standard.string(forKey: environmentKey).map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? defaultEnvironment
    }

    static func python(in environment: URL) -> URL {
        environment.appending(path: "bin/python")
    }

    /// The server and the libraries' versions, in the app.
    static var server: URL? { Bundle.main.url(forResource: "xtts_server", withExtension: "py") }
    static var requirements: URL? { Bundle.main.url(forResource: "xtts-requirements", withExtension: "txt") }

    /// Written into an environment Dysnow made once every library is in:
    /// the requirements it was made of. Another version of Dysnow with other
    /// requirements installs them again.
    static func stamp(in environment: URL) -> URL {
        environment.appending(path: "dysnow-requirements.txt")
    }

    // MARK: Python

    /// A Python found, and what it is.
    struct Python: Equatable, Sendable {
        let url: URL
        let version: String
        let machine: String

        var isUsable: Bool { version.hasPrefix("3.11.") && machine == Self.machine }

        /// What this Mac runs natively: a Python for the other kind of
        /// processor cannot load the libraries Dysnow installs.
        static let machine: String = {
            #if arch(arm64)
            "arm64"
            #else
            "x86_64"
            #endif
        }()
    }

    /// Where Python 3.11 is put by Homebrew, python.org's installer, uv,
    /// pyenv and MacPorts, the one picked first.
    static func candidates() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths = [UserDefaults.standard.string(forKey: pythonKey)].compactMap { $0 }
        paths += ["/opt/homebrew/bin/python3.11", "/opt/homebrew/opt/python@3.11/bin/python3.11",
                  "/usr/local/bin/python3.11", "/usr/local/opt/python@3.11/bin/python3.11",
                  "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11",
                  home.appending(path: ".local/bin/python3.11").path, "/opt/local/bin/python3.11"]
        let versioned: [(URL, String)] = [
            (home.appending(path: ".pyenv/versions"), "bin/python3.11"),
            (home.appending(path: ".local/share/uv/python"), "bin/python3.11"),
        ]
        for (folder, executable) in versioned {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names.sorted().reversed() where name.hasPrefix("3.11") || name.hasPrefix("cpython-3.11") {
                paths.append(folder.appending(path: name).appending(path: executable).path)
            }
        }
        var seen = Set<String>()
        return paths.filter { FileManager.default.isExecutableFile(atPath: $0) && seen.insert($0).inserted }
            .map { URL(filePath: $0) }
    }

    /// What the Python is; nil when it does not run.
    static func inspect(_ url: URL) async -> Python? {
        let script = "import platform; print(platform.python_version(), platform.machine())"
        guard let result = try? await run(url, ["-I", "-c", script]), result.status == 0 else { return nil }
        let parts = result.output.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 2 else { return nil }
        return Python(url: url, version: parts[0], machine: parts[1])
    }

    /// The first usable Python 3.11, and every other Python looked at.
    static func findPython() async -> (usable: Python?, others: [Python]) {
        var others: [Python] = []
        for candidate in candidates() {
            guard let python = await inspect(candidate) else { continue }
            if python.isUsable { return (python, others) }
            others.append(python)
        }
        return (nil, others)
    }

    // MARK: The environment

    /// Whether the environment has its libraries: made by Dysnow of the
    /// requirements of this version, or one picked by the user, which is
    /// checked when it is picked.
    static func isReady(_ environment: URL) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: python(in: environment).path) else { return false }
        if environment.standardizedFileURL != defaultEnvironment.standardizedFileURL { return true }
        guard let requirements, let wanted = try? Data(contentsOf: requirements),
              let installed = try? Data(contentsOf: stamp(in: environment)) else { return false }
        return wanted == installed
    }

    /// Makes Dysnow's environment with `python` and installs the libraries
    /// into it; `progress` is told each line pip writes, and how far it is.
    static func setUp(with python: Python, progress: @escaping @Sendable (String, Double) -> Void) async throws {
        guard let requirements else { throw SpeechError.failed("The list of XTTS's libraries is missing from Dysnow.") }
        let environment = defaultEnvironment
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if !FileManager.default.isExecutableFile(atPath: self.python(in: environment).path) {
            progress("Making the environment with Python \(python.version)…", 0)
            let made = try await run(python.url, ["-m", "venv", environment.path])
            guard made.status == 0 else { throw SpeechError.failed("The environment could not be made:\n" + made.output) }
        }
        let count = Double(((try? String(contentsOf: requirements, encoding: .utf8)) ?? "")
            .split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }.count)
        let collected = Counter()
        let installed = try await run(self.python(in: environment),
                                      ["-m", "pip", "install", "--disable-pip-version-check", "--progress-bar", "off",
                                       "-r", requirements.path]) { line in
            // Each library is collected first, then all are installed.
            if line.hasPrefix("Collecting ") || line.hasPrefix("Requirement already satisfied") {
                progress(line, min(collected.increment() / max(count, 1), 1) * 0.8)
            } else if line.hasPrefix("Installing collected packages") {
                progress("Installing the libraries…", 0.85)
            } else {
                progress(line, -1)
            }
        }
        guard installed.status == 0 else {
            throw SpeechError.failed("pip could not install XTTS's libraries:\n" + installed.output.suffix(2_000))
        }
        try? FileManager.default.removeItem(at: stamp(in: environment))
        try FileManager.default.copyItem(at: requirements, to: stamp(in: environment))
        progress("Done.", 1)
    }

    // MARK: Running

    struct Result: Sendable {
        let status: Int32
        /// What it wrote, to stdout and stderr together.
        let output: String
    }

    /// Runs a program to its end, telling `line` each line it writes.
    static func run(_ executable: URL, _ arguments: [String],
                    line: (@Sendable (String) -> Void)? = nil) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environmentVariables
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        let output = Collected()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result, Error>) in
                LineReader.read(pipe.fileHandleForReading) { text in
                    output.append(text)
                    line?(text)
                }
                process.terminationHandler = { process in
                    // What it wrote last is read before the result is given.
                    pipe.fileHandleForReading.readabilityHandler = nil
                    let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                    if !rest.isEmpty {
                        for text in String(decoding: rest, as: UTF8.self).split(separator: "\n") {
                            output.append(String(text))
                        }
                    }
                    continuation.resume(returning: Result(status: process.terminationStatus, output: output.text))
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }

    /// What Python is started with: no user site, no buffering, the user's
    /// own configuration of Python left out.
    static var environmentVariables: [String: String] {
        var variables = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("PYTHON") && $0.key != "VIRTUAL_ENV" }
        variables["PYTHONUNBUFFERED"] = "1"
        variables["PYTHONNOUSERSITE"] = "1"
        variables["TOKENIZERS_PARALLELISM"] = "false"
        // Apple's command line tools, for a library that has to be built.
        variables["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        return variables
    }

    /// How to get Python 3.11, for a Mac without it.
    static let installAdvice = """
        XTTS needs Python 3.11: its libraries do not install on 3.12 or newer. Dysnow does not bring \
        Python with it; install Python 3.11 in one of these ways, then press Look Again:

        • Homebrew: brew install python@3.11
        • uv: uv python install 3.11
        • python.org: the macOS installer of the newest Python 3.11 release
        """
}

private final class Counter: @unchecked Sendable {
    private var value = 0.0
    private let lock = NSLock()

    func increment() -> Double {
        lock.withLock {
            value += 1
            return value
        }
    }
}

private final class Collected: @unchecked Sendable {
    private var lines: [String] = []
    private let lock = NSLock()

    func append(_ line: String) {
        lock.withLock { lines.append(line) }
    }

    var text: String { lock.withLock { lines.joined(separator: "\n") } }
}
