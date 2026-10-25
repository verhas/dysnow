import CryptoKit
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
            let archive = try await download()
            defer { try? FileManager.default.removeItem(at: archive) }
            state = .unpacking
            try await Task.detached { try KokoroInstaller.verifyAndUnpack(archive, into: parent) }.value
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

    private func download() async throws -> URL {
        let delegate = DownloadDelegate { [weak self] fraction in
            Task { @MainActor in
                if case .downloading = self?.state { self?.state = .downloading(fraction) }
            }
        }
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            session.downloadTask(with: KokoroEngine.modelURL).resume()
        }
    }

    /// Off the main thread: the archive is hundreds of megabytes.
    nonisolated private static func verifyAndUnpack(_ archive: URL, into parent: URL) throws {
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == KokoroEngine.modelSHA256 else { throw InstallError.checksum }

        // The archive holds a single folder, named after the model.
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.arguments = ["xjf", archive.path, "-C", parent.path]
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else { throw InstallError.unpack }
    }

    enum InstallError: LocalizedError {
        case checksum, unpack

        var errorDescription: String? {
            switch self {
            case .checksum: "The download is not the expected model: it may have been damaged on the way."
            case .unpack: "The model could not be unpacked."
            }
        }
    }
}

/// Reports a download's progress, and hands over the file before URLSession
/// deletes it.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    var continuation: CheckedContinuation<URL, Error>?

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite
            : Int64(KokoroEngine.downloadMegabytes) << 20
        progress(min(Double(totalBytesWritten) / Double(expected), 1))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let kept = FileManager.default.temporaryDirectory.appending(path: "dysnow-kokoro-\(UUID().uuidString).tar.bz2")
        do {
            if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                throw URLError(.badServerResponse)
            }
            try FileManager.default.moveItem(at: location, to: kept)
            continuation?.resume(returning: kept)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
