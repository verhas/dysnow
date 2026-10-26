import Foundation
import Observation

/// Where Piper's models are, and getting them there one by one: downloaded
/// into the voices folder -- `~/.dysnow/voices` unless the user picks
/// another -- or found where they already are.
@MainActor @Observable
final class PiperInstaller {
    static let shared = PiperInstaller()

    /// Per model, by its id; a model not in it is idle.
    private(set) var states: [String: KokoroInstaller.State] = [:]
    /// The folder the models are looked for in.
    private(set) var directory = PiperEngine.directory
    /// The ids of the models downloaded.
    private(set) var installed = PiperEngine.installedModels()
    /// A message about the folder itself: a pick that held no voices.
    private(set) var folderProblem: String?

    var isDefaultLocation: Bool {
        directory.standardizedFileURL == PiperEngine.defaultDirectory.standardizedFileURL
    }

    func state(of model: PiperModel) -> KokoroInstaller.State {
        states[model.id] ?? .idle
    }

    func isInstalled(_ model: PiperModel) -> Bool {
        installed.contains(model.id)
    }

    func isBusy(_ model: PiperModel) -> Bool {
        switch state(of: model) {
        case .downloading, .unpacking: true
        default: false
        }
    }

    /// How many of the language's models are downloaded.
    func installedCount(of language: SpeechLanguage) -> Int {
        PiperModel.all.filter { $0.language == language && installed.contains($0.id) }.count
    }

    /// Looks again: the folder may have been filled, linked, or unmounted
    /// while the app was not looking.
    func refresh() {
        directory = PiperEngine.directory
        installed = PiperEngine.installedModels(in: directory)
    }

    func isInstalled(_ voice: PiperVoice) -> Bool { isInstalled(voice.model) }
    func state(of voice: PiperVoice) -> KokoroInstaller.State { state(of: voice.model) }
    func isBusy(_ voice: PiperVoice) -> Bool { isBusy(voice.model) }

    /// Downloads the model into the voices folder; into `folder` instead when
    /// one is given, which then becomes the voices folder.
    func install(_ model: PiperModel, into folder: URL? = nil) async {
        guard !isBusy(model) else { return }
        if let folder, folder.standardizedFileURL != directory.standardizedFileURL {
            useFolder(folder)
        }
        let target = PiperEngine.folder(of: model, in: directory)
        if !PiperEngine.holds(model, in: target) {
            states[model.id] = .downloading(0)
            do {
                try await ModelDownloader.install(model.package, into: directory) { [weak self] fraction in
                    Task { @MainActor in
                        if case .downloading = self?.states[model.id] { self?.states[model.id] = .downloading(fraction) }
                    }
                } unpacking: {
                    states[model.id] = .unpacking
                }
            } catch {
                states[model.id] = .failed(error.localizedDescription)
                return
            }
            guard PiperEngine.holds(model, in: target) else {
                states[model.id] = .failed("The download did not hold the voice.")
                return
            }
        }
        states[model.id] = nil
        PiperEngine.shared.unload()
        refresh()
    }

    /// Deletes a downloaded model.
    func remove(_ model: PiperModel) {
        PiperEngine.shared.unload()
        try? FileManager.default.removeItem(at: PiperEngine.folder(of: model, in: directory))
        refresh()
    }

    /// Uses voices that are already there: the folder picked holds voice
    /// folders, or is one.
    func locate(_ folder: URL) {
        let candidates = [folder, folder.deletingLastPathComponent()]
        guard let found = candidates.first(where: { candidate in
            !PiperEngine.installedModels(in: candidate).isEmpty
        }) else {
            folderProblem = "\(folder.lastPathComponent) holds none of Piper's voices: they are folders such as "
                + (PiperModel.withID("hu_HU-anna-medium")?.package.folderName ?? "") + "."
            return
        }
        useFolder(found)
    }

    /// Back to `~/.dysnow/voices`.
    func useDefaultLocation() {
        useFolder(PiperEngine.defaultDirectory)
    }

    /// Looks for the voices in this folder from now on, and downloads them there.
    func useFolder(_ folder: URL) {
        if folder.standardizedFileURL == PiperEngine.defaultDirectory.standardizedFileURL {
            UserDefaults.standard.removeObject(forKey: PiperEngine.directoryKey)
        } else {
            UserDefaults.standard.set(folder.path, forKey: PiperEngine.directoryKey)
        }
        folderProblem = nil
        PiperEngine.shared.unload()
        refresh()
    }
}
