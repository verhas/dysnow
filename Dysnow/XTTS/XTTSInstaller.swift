import Foundation
import Observation

/// Getting XTTS v2 ready, a step at a time: Python 3.11 found, the
/// environment of its libraries made, the model downloaded.
@MainActor @Observable
final class XTTSInstaller {
    static let shared = XTTSInstaller()

    enum Step: Equatable {
        case idle
        case working(String, Double?)
        case failed(String)
    }

    /// The Python 3.11 found; nil before looking, or when there is none.
    private(set) var python: XTTSEnvironment.Python?
    /// The other Pythons found, which are not 3.11.
    private(set) var otherPythons: [XTTSEnvironment.Python] = []
    private(set) var hasLooked = false
    private(set) var environment = XTTSEnvironment.environment
    private(set) var environmentIsReady = XTTSEnvironment.isReady(XTTSEnvironment.environment)
    private(set) var environmentStep = Step.idle
    /// The last lines pip wrote, while it works.
    private(set) var log: [String] = []
    private(set) var modelDirectory = XTTSModel.directory
    private(set) var modelIsInstalled = XTTSModel.isInstalled
    private(set) var modelState = KokoroInstaller.State.idle
    private(set) var folderProblem: String?
    private var work: Task<Void, Never>?

    var isReady: Bool { environmentIsReady && modelIsInstalled }
    var isBusy: Bool { work != nil }
    var usesDefaultEnvironment: Bool {
        environment.standardizedFileURL == XTTSEnvironment.defaultEnvironment.standardizedFileURL
    }
    var usesDefaultModel: Bool { UserDefaults.standard.string(forKey: XTTSModel.directoryKey) == nil }

    func refresh() {
        environment = XTTSEnvironment.environment
        environmentIsReady = XTTSEnvironment.isReady(environment)
        modelDirectory = XTTSModel.directory
        modelIsInstalled = XTTSModel.isInstalled
    }

    /// Looks for Python 3.11 where it is usually installed.
    func lookForPython() async {
        let found = await XTTSEnvironment.findPython()
        python = found.usable
        otherPythons = found.others
        hasLooked = true
    }

    /// Uses the Python the user picked, if it is 3.11.
    func choosePython(_ url: URL) async {
        guard let picked = await XTTSEnvironment.inspect(url) else {
            environmentStep = .failed("\(url.lastPathComponent) does not run as Python.")
            return
        }
        guard picked.isUsable else {
            environmentStep = .failed("That is Python \(picked.version) for \(picked.machine): XTTS needs 3.11 for "
                + XTTSEnvironment.Python.machine + ".")
            return
        }
        UserDefaults.standard.set(url.path, forKey: XTTSEnvironment.pythonKey)
        environmentStep = .idle
        await lookForPython()
    }

    /// Makes Dysnow's environment and installs the libraries into it: about
    /// a gigabyte, downloaded by pip.
    func setUpEnvironment() {
        guard work == nil, let python else { return }
        useDefaultEnvironment()
        environmentStep = .working("Starting…", 0)
        log = []
        work = Task {
            do {
                try await XTTSEnvironment.setUp(with: python) { line, fraction in
                    Task { @MainActor in self.progress(line, fraction) }
                }
                environmentStep = .working("Checking the libraries…", nil)
                _ = try await XTTSEngine.shared.check(XTTSEnvironment.defaultEnvironment)
                environmentStep = .idle
            } catch is CancellationError {
                environmentStep = .idle
            } catch {
                environmentStep = .failed(error.localizedDescription)
            }
            work = nil
            refresh()
            if isReady { Task.detached(priority: .utility) { await XTTSEngine.shared.prepare() } }
        }
    }

    private func progress(_ line: String, _ fraction: Double) {
        log.append(line)
        if log.count > 200 { log.removeFirst(log.count - 200) }
        if fraction >= 0, case .working = environmentStep {
            environmentStep = .working(line, fraction)
        }
    }

    func cancel() {
        work?.cancel()
    }

    /// Uses an environment the user already has, as the one XTTS Voice
    /// Generator was set up with, once its libraries load.
    func useEnvironment(_ folder: URL) {
        guard work == nil else { return }
        guard FileManager.default.isExecutableFile(atPath: XTTSEnvironment.python(in: folder).path) else {
            environmentStep = .failed("\(folder.lastPathComponent) is not a Python environment: it has no bin/python.")
            return
        }
        environmentStep = .working("Checking \(folder.lastPathComponent)…", nil)
        work = Task {
            do {
                let answer = try await XTTSEngine.shared.check(folder)
                guard answer.python?.hasPrefix("3.11.") == true else {
                    throw SpeechError.failed("Its Python is \(answer.python ?? "unknown"): XTTS needs 3.11.")
                }
                UserDefaults.standard.set(folder.path, forKey: XTTSEnvironment.environmentKey)
                await XTTSEngine.shared.unload()
                environmentStep = .idle
            } catch {
                await XTTSEngine.shared.unload()
                environmentStep = .failed("\(folder.lastPathComponent) cannot run XTTS: \(error.localizedDescription)")
            }
            work = nil
            refresh()
        }
    }

    func useDefaultEnvironment() {
        UserDefaults.standard.removeObject(forKey: XTTSEnvironment.environmentKey)
        Task { await XTTSEngine.shared.unload() }
        refresh()
    }

    /// Deletes Dysnow's environment: about two gigabytes back.
    func removeEnvironment() {
        Task { await XTTSEngine.shared.unload() }
        try? FileManager.default.removeItem(at: XTTSEnvironment.defaultEnvironment)
        refresh()
    }

    // MARK: The model

    /// Downloads the model into Dysnow's folder, or into `parent`.
    func installModel(into parent: URL? = nil) {
        guard work == nil else { return }
        let parent = parent ?? XTTSModel.defaultDirectory.deletingLastPathComponent()
        modelState = .downloading(0)
        work = Task {
            do {
                try await HuggingFaceDownloader.install(XTTSModel.huggingFace, into: parent) { fraction in
                    Task { @MainActor in
                        if case .downloading = self.modelState { self.modelState = .downloading(fraction) }
                    }
                }
                useModel(parent.appending(path: XTTSModel.huggingFace.folderName, directoryHint: .isDirectory))
                modelState = .idle
                if environmentIsReady { Task.detached(priority: .utility) { await XTTSEngine.shared.prepare() } }
            } catch is CancellationError {
                modelState = .idle
            } catch let error as URLError where error.code == .cancelled {
                modelState = .idle
            } catch {
                modelState = .failed(error.localizedDescription)
            }
            work = nil
            refresh()
        }
    }

    /// Uses a model already downloaded: by Coqui TTS, or into another folder.
    func locateModel(_ folder: URL) {
        let candidates = [folder, folder.appending(path: XTTSModel.huggingFace.folderName),
                          folder.appending(path: "tts_models--multilingual--multi-dataset--xtts_v2")]
        guard let found = candidates.first(where: XTTSModel.holds) else {
            folderProblem = "\(folder.lastPathComponent) holds no XTTS v2 model: config.json, model.pth, vocab.json "
                + "and speakers_xtts.pth."
            return
        }
        useModel(found)
    }

    func useDefaultModel() {
        UserDefaults.standard.removeObject(forKey: XTTSModel.directoryKey)
        folderProblem = nil
        Task { await XTTSEngine.shared.unload() }
        refresh()
    }

    private func useModel(_ folder: URL) {
        if folder.standardizedFileURL == XTTSModel.defaultDirectory.standardizedFileURL {
            UserDefaults.standard.removeObject(forKey: XTTSModel.directoryKey)
        } else {
            UserDefaults.standard.set(folder.path, forKey: XTTSModel.directoryKey)
        }
        folderProblem = nil
        Task { await XTTSEngine.shared.unload() }
        refresh()
    }
}
