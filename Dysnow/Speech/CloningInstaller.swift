import Foundation
import Observation

/// Where ZipVoice's or Pocket TTS's model is, and getting it there:
/// downloaded into `~/.dysnow/voices` or a folder the user picks, or found
/// where it already is.
@MainActor @Observable
final class CloningInstaller {
    static let zipVoice = CloningInstaller(model: .zipVoice)
    static let pocket = CloningInstaller(model: .pocket)

    static func shared(_ model: CloningModel) -> CloningInstaller {
        switch model {
        case .zipVoice: zipVoice
        case .pocket: pocket
        }
    }

    let model: CloningModel
    private(set) var state = KokoroInstaller.State.idle
    /// The model's folder, whether or not the model is in it yet.
    private(set) var directory: URL
    private(set) var isInstalled: Bool

    init(model: CloningModel) {
        self.model = model
        directory = model.directory
        isInstalled = model.holdsModel(model.directory)
    }

    var isBusy: Bool {
        switch state {
        case .downloading, .unpacking: true
        default: false
        }
    }

    var isDefaultLocation: Bool {
        directory.standardizedFileURL == model.defaultDirectory.standardizedFileURL
    }

    /// Looks again: the folder may have been filled, linked, or unmounted
    /// while the app was not looking.
    func refresh() {
        directory = model.directory
        isInstalled = model.holdsModel(directory)
    }

    /// Downloads the model into a folder of its own inside `parent`, and uses
    /// it from there; into the default place when no parent is given.
    func install(into parent: URL? = nil) async {
        guard !isBusy else { return }
        let parent = parent ?? model.defaultDirectory.deletingLastPathComponent()
        let target = parent.appending(path: model.package.folderName, directoryHint: .isDirectory)
        if model.holdsModel(target) {
            use(target)
            return
        }
        // The archive, then the file published apart from it, share the bar.
        let share = Double(model.package.megabytes) / Double(model.megabytes)
        state = .downloading(0)
        do {
            if !FileManager.default.fileExists(atPath: target.appending(path: model.files[0]).path) {
                try await ModelDownloader.install(model.package, into: parent) { [weak self] fraction in
                    Task { @MainActor in self?.progress(fraction * share) }
                } unpacking: {
                    state = .unpacking
                }
            }
            if let extra = model.extraFile {
                state = .downloading(share)
                try await ModelDownloader.install(extra, into: target) { [weak self] fraction in
                    Task { @MainActor in self?.progress(share + fraction * (1 - share)) }
                }
            }
            guard model.holdsModel(target) else {
                state = .failed("The download did not hold the model.")
                return
            }
            use(target)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func progress(_ fraction: Double) {
        if case .downloading = state { state = .downloading(fraction) }
    }

    /// Uses a model that is already there: the folder picked, or the model's
    /// own folder inside it.
    func locate(_ folder: URL) {
        let candidates = [folder, folder.appending(path: model.package.folderName, directoryHint: .isDirectory)]
        guard let found = candidates.first(where: model.holdsModel) else {
            state = .failed("\(folder.lastPathComponent) does not hold \(model.name)'s model: it needs "
                + model.files.formatted(.list(type: .and)) + ".")
            return
        }
        use(found)
    }

    /// Back to `~/.dysnow/voices`; the model may or may not be there.
    func useDefaultLocation() {
        use(model.defaultDirectory)
    }

    private func use(_ folder: URL) {
        if folder.standardizedFileURL == model.defaultDirectory.standardizedFileURL {
            UserDefaults.standard.removeObject(forKey: model.directoryKey)
        } else {
            UserDefaults.standard.set(folder.path, forKey: model.directoryKey)
        }
        CloningEngine.shared(model).unload()
        state = .idle
        refresh()
    }
}
