import Foundation
import Observation

/// Where Qwen3-TTS's models are, which size is used, and getting them
/// there: downloaded from Hugging Face into the models folder --
/// `~/.dysnow/voices` unless the user picks another -- or found where they
/// already are. They are gigabytes, so a download can be stopped; started
/// again, it goes on from the files already there.
@MainActor @Observable
final class Qwen3Installer {
    static let shared = Qwen3Installer()

    /// Per variant, by its id; a variant not in it is idle.
    private(set) var states: [String: KokoroInstaller.State] = [:]
    private(set) var directory = Qwen3Engine.directory
    private(set) var variant = Qwen3Engine.variant
    private(set) var installed = Set(Qwen3Variant.all.filter(Qwen3Engine.isInstalled).map(\.id))
    /// A message about a folder picked that held no model.
    private(set) var folderProblem: String?
    private var downloads: [String: Task<Void, Never>] = [:]

    var isDefaultLocation: Bool {
        directory.standardizedFileURL == Qwen3Engine.defaultDirectory.standardizedFileURL
    }

    func state(of variant: Qwen3Variant) -> KokoroInstaller.State {
        states[variant.id] ?? .idle
    }

    func isInstalled(_ variant: Qwen3Variant) -> Bool {
        installed.contains(variant.id)
    }

    func isBusy(_ variant: Qwen3Variant) -> Bool {
        downloads[variant.id] != nil
    }

    /// Looks again: the folder may have been filled, linked, or unmounted
    /// while the app was not looking.
    func refresh() {
        directory = Qwen3Engine.directory
        variant = Qwen3Engine.variant
        installed = Set(Qwen3Variant.all.filter(Qwen3Engine.isInstalled).map(\.id))
    }

    /// Speaks with this size from now on, once it is downloaded.
    func choose(_ variant: Qwen3Variant) {
        UserDefaults.standard.set(variant.id, forKey: Qwen3Engine.variantKey)
        Task { await Qwen3Engine.shared.unload() }
        refresh()
    }

    /// Downloads the variant into the models folder, and uses it; into
    /// `folder` instead when one is given, which becomes the models folder.
    func install(_ variant: Qwen3Variant, into folder: URL? = nil) {
        guard downloads[variant.id] == nil else { return }
        if let folder { useFolder(folder) }
        let directory = directory
        states[variant.id] = .downloading(0)
        downloads[variant.id] = Task {
            do {
                try await HuggingFaceDownloader.install(variant.model, into: directory) { fraction in
                    Task { @MainActor in
                        if case .downloading = self.states[variant.id] {
                            self.states[variant.id] = .downloading(fraction)
                        }
                    }
                }
                states[variant.id] = nil
                choose(variant)
            } catch is CancellationError {
                states[variant.id] = nil
            } catch let error as URLError where error.code == .cancelled {
                states[variant.id] = nil
            } catch {
                states[variant.id] = .failed(error.localizedDescription)
            }
            downloads[variant.id] = nil
            refresh()
        }
    }

    /// Stops a download; what is downloaded is kept for the next try.
    func cancel(_ variant: Qwen3Variant) {
        downloads[variant.id]?.cancel()
    }

    /// Deletes a downloaded variant: gigabytes back.
    func remove(_ variant: Qwen3Variant) {
        Task { await Qwen3Engine.shared.unload() }
        try? FileManager.default.removeItem(at: Qwen3Engine.folder(of: variant, in: directory))
        refresh()
    }

    /// Uses a model already there: the folder picked is a model's own, or
    /// holds them.
    func locate(_ folder: URL) {
        for candidate in [folder, folder.deletingLastPathComponent()] {
            if let found = Qwen3Variant.all.first(where: {
                Qwen3Engine.holdsModel(Qwen3Engine.folder(of: $0, in: candidate))
            }) {
                useFolder(candidate)
                choose(found)
                return
            }
        }
        folderProblem = "\(folder.lastPathComponent) holds no Qwen3-TTS model: it is a folder such as "
            + Qwen3Variant.small.model.folderName + "."
    }

    func useDefaultLocation() {
        useFolder(Qwen3Engine.defaultDirectory)
    }

    /// Looks for the models in this folder from now on, and downloads them there.
    func useFolder(_ folder: URL) {
        if folder.standardizedFileURL == Qwen3Engine.defaultDirectory.standardizedFileURL {
            UserDefaults.standard.removeObject(forKey: Qwen3Engine.directoryKey)
        } else {
            UserDefaults.standard.set(folder.path, forKey: Qwen3Engine.directoryKey)
        }
        folderProblem = nil
        Task { await Qwen3Engine.shared.unload() }
        refresh()
    }
}
