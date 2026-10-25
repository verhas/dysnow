import Foundation
import Observation

/// Where Piper's voices are, and getting them there one by one: downloaded
/// into the voices folder -- `~/.dysnow/voices` unless the user picks
/// another -- or found where they already are.
@MainActor @Observable
final class PiperInstaller {
    static let shared = PiperInstaller()

    /// Per voice, by its id; a voice not in it is idle.
    private(set) var states: [String: KokoroInstaller.State] = [:]
    /// The folder the voices are looked for in.
    private(set) var directory = PiperEngine.directory
    private(set) var installed = Set(PiperVoice.all.filter(PiperEngine.isInstalled).map(\.id))
    /// A message about the folder itself: a pick that held no voices.
    private(set) var folderProblem: String?

    var isDefaultLocation: Bool {
        directory.standardizedFileURL == PiperEngine.defaultDirectory.standardizedFileURL
    }

    func state(of voice: PiperVoice) -> KokoroInstaller.State {
        states[voice.id] ?? .idle
    }

    func isInstalled(_ voice: PiperVoice) -> Bool {
        installed.contains(voice.id)
    }

    func isBusy(_ voice: PiperVoice) -> Bool {
        switch state(of: voice) {
        case .downloading, .unpacking: true
        default: false
        }
    }

    /// Looks again: the folder may have been filled, linked, or unmounted
    /// while the app was not looking.
    func refresh() {
        directory = PiperEngine.directory
        installed = Set(PiperVoice.all.filter(PiperEngine.isInstalled).map(\.id))
    }

    /// Downloads the voice into the voices folder; into `folder` instead when
    /// one is given, which then becomes the voices folder.
    func install(_ voice: PiperVoice, into folder: URL? = nil) async {
        guard !isBusy(voice) else { return }
        if let folder, folder.standardizedFileURL != directory.standardizedFileURL {
            useFolder(folder)
        }
        let target = PiperEngine.folder(of: voice, in: directory)
        if !PiperEngine.holds(voice, in: target) {
            states[voice.id] = .downloading(0)
            do {
                try await ModelDownloader.install(voice.package, into: directory) { [weak self] fraction in
                    Task { @MainActor in
                        if case .downloading = self?.states[voice.id] { self?.states[voice.id] = .downloading(fraction) }
                    }
                } unpacking: {
                    states[voice.id] = .unpacking
                }
            } catch {
                states[voice.id] = .failed(error.localizedDescription)
                return
            }
            guard PiperEngine.holds(voice, in: target) else {
                states[voice.id] = .failed("The download did not hold the voice.")
                return
            }
        }
        states[voice.id] = nil
        PiperEngine.shared.unload()
        refresh()
    }

    /// Deletes a downloaded voice.
    func remove(_ voice: PiperVoice) {
        PiperEngine.shared.unload()
        try? FileManager.default.removeItem(at: PiperEngine.folder(of: voice, in: directory))
        refresh()
    }

    /// Uses voices that are already there: the folder picked holds voice
    /// folders, or is one.
    func locate(_ folder: URL) {
        let candidates = [folder, folder.deletingLastPathComponent()]
        guard let found = candidates.first(where: { candidate in
            PiperVoice.all.contains { PiperEngine.holds($0, in: PiperEngine.folder(of: $0, in: candidate)) }
        }) else {
            folderProblem = "\(folder.lastPathComponent) holds none of Piper's voices: they are folders such as "
                + (PiperVoice.all.first?.package.folderName ?? "") + "."
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
