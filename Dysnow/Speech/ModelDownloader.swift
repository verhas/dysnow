import CryptoKit
import Foundation

/// A model as it is published: a .tar.bz2 archive holding one folder.
struct ModelPackage: Hashable, Sendable {
    let url: URL
    let sha256: String
    /// About the size of the download, for telling the user, and for the
    /// progress when the server does not say.
    let megabytes: Int
    /// The folder the archive unpacks to.
    var folderName: String {
        url.deletingPathExtension().deletingPathExtension().lastPathComponent
    }
}

/// Downloads a model archive, checks it is the release it should be, and
/// unpacks it.
enum ModelDownloader {
    /// Unpacks the package into `parent`, where it makes a folder of its own.
    /// `progress` is told how much is downloaded, from 0 to 1, on any thread;
    /// `unpacking` when the download is done and the rest begins.
    static func install(_ package: ModelPackage, into parent: URL,
                        progress: @escaping @Sendable (Double) -> Void,
                        unpacking: @MainActor () -> Void) async throws {
        let archive = try await download(package, progress: progress)
        defer { try? FileManager.default.removeItem(at: archive) }
        await unpacking()
        try await Task.detached { try verifyAndUnpack(archive, sha256: package.sha256, into: parent) }.value
    }

    private static func download(_ package: ModelPackage,
                                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = DownloadDelegate(expectedBytes: Int64(package.megabytes) << 20, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.continuation = continuation
                session.downloadTask(with: package.url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    /// Off the main thread: an archive is tens or hundreds of megabytes.
    private static func verifyAndUnpack(_ archive: URL, sha256: String, into parent: URL) throws {
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else { throw InstallError.checksum }

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
    let expectedBytes: Int64
    let progress: @Sendable (Double) -> Void
    var continuation: CheckedContinuation<URL, Error>?

    init(expectedBytes: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.expectedBytes = expectedBytes
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
        progress(min(Double(totalBytesWritten) / Double(expected), 1))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let kept = FileManager.default.temporaryDirectory.appending(path: "dysnow-model-\(UUID().uuidString).tar.bz2")
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
