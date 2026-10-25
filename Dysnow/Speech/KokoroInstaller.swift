import Foundation
import Observation

/// Where Kokoro's model is, and getting it there: downloaded into a folder
/// the user picks -- `~/.dysnow/voices` unless they pick another -- checked
/// to be the release it should be, and unpacked; or found where it already is.
@MainActor @Observable
final class KokoroInstaller {
    static let shared = KokoroInstaller()

    enum State: Equatable {
        case idle
        /// From 0 to 1.
        case downloading(Double)
        case unpacking
        case failed(String)
    }

    private(set) var state = State.idle
    /// The model's folder, whether or not the model is in it yet.
    private(set) var directory = KokoroEngine.directory
    private(set) var isInstalled = KokoroEngine.isInstalled

    var isBusy: Bool {
        switch state {
        case .downloading, .unpacking: true
        default: false
        }
    }

    var isDefaultLocation: Bool {
        directory.standardizedFileURL == KokoroEngine.defaultDirectory.standardizedFileURL
    }

    /// Looks again: the folder may have been filled, linked, or unmounted
    /// while the app was not looking.
    func refresh() {
        directory = KokoroEngine.directory
        isInstalled = KokoroEngine.isInstalled
    }

    /// Downloads the model into a folder of its own inside `parent`, and uses
    /// it from there; into the default place when no parent is given.
    func install(into parent: URL? = nil) async {
        guard !isBusy else { return }
        let parent = parent ?? KokoroEngine.defaultDirectory.deletingLastPathComponent()
        let target = parent.appending(path: KokoroEngine.modelName, directoryHint: .isDirectory)
        if KokoroEngine.holdsModel(target) {
            use(target)
            return
        }
        state = .downloading(0)
        do {
            try await ModelDownloader.install(KokoroEngine.package, into: parent) { [weak self] fraction in
                Task { @MainActor in
                    if case .downloading = self?.state { self?.state = .downloading(fraction) }
                }
            } unpacking: {
                state = .unpacking
            }
            guard KokoroEngine.holdsModel(target) else {
                state = .failed("The download did not hold the model.")
                return
            }
            use(target)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Uses a model that is already there: the folder picked, or the model's
    /// own folder inside it.
    func locate(_ folder: URL) {
        let candidates = [folder, folder.appending(path: KokoroEngine.modelName, directoryHint: .isDirectory)]
        guard let found = candidates.first(where: KokoroEngine.holdsModel) else {
            state = .failed("\(folder.lastPathComponent) does not hold Kokoro's model: it needs model.onnx, "
                + "voices.bin, tokens.txt and espeak-ng-data.")
            return
        }
        use(found)
    }

    /// Back to `~/.dysnow/voices`; the model may or may not be there.
    func useDefaultLocation() {
        use(KokoroEngine.defaultDirectory)
    }

    private func use(_ folder: URL) {
        if folder.standardizedFileURL == KokoroEngine.defaultDirectory.standardizedFileURL {
            UserDefaults.standard.removeObject(forKey: KokoroEngine.directoryKey)
        } else {
            UserDefaults.standard.set(folder.path, forKey: KokoroEngine.directoryKey)
        }
        KokoroEngine.shared.unload()
        state = .idle
        refresh()
    }
}
