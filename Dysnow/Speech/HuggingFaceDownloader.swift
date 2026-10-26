import CryptoKit
import Foundation

/// A model published on Hugging Face, at a fixed revision: the files of
/// that commit, never whatever is newest.
struct HuggingFaceModel: Hashable, Sendable {
    /// "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"
    let repo: String
    /// The commit.
    let revision: String
    /// About the size of the download, for telling the user.
    let megabytes: Int
    /// The files wanted, when not all of them are: XTTS v2's repository
    /// also has what only training needs.
    var files: Set<String>? = nil

    /// The folder it is downloaded to: the repository's own name.
    var folderName: String { repo.split(separator: "/").last.map(String.init) ?? repo }
}

/// Downloads every file of a Hugging Face model, each checked against the
/// hash Hugging Face gives for it, into a folder that is only given its
/// name once all of them are there: a download cut short is never taken
/// for the model.
enum HuggingFaceDownloader {
    private struct Entry: Decodable {
        struct LFS: Decodable {
            let oid: String
        }

        let type: String
        let path: String
        let size: Int64
        /// The Git object id: SHA-1 of the file as Git stores it.
        let oid: String
        /// For large files: their SHA-256.
        let lfs: LFS?
    }

    /// Downloads the model into a folder of its own in `parent`.
    static func install(_ model: HuggingFaceModel, into parent: URL,
                        progress: @escaping @Sendable (Double) -> Void) async throws {
        let listURL = URL(string: "https://huggingface.co/api/models/\(model.repo)/tree/\(model.revision)?recursive=true")!
        let (data, response) = try await URLSession.shared.data(from: listURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let files = try JSONDecoder().decode([Entry].self, from: data).filter { entry in
            entry.type == "file" && model.files.map { $0.contains(entry.path) } ?? true
        }
        let total = max(files.reduce(0) { $0 + $1.size }, 1)

        let target = parent.appending(path: model.folderName, directoryHint: .isDirectory)
        let partial = parent.appending(path: model.folderName + ".partial", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)

        var done: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            let destination = partial.appending(path: file.path)
            // Kept from a download cut short, and still good.
            if (try? verify(destination, against: file)) == true {
                done += file.size
                progress(Double(done) / Double(total))
                continue
            }
            let before = done
            let url = URL(string: "https://huggingface.co/\(model.repo)/resolve/\(model.revision)/\(file.path)")!
            let downloaded = try await ModelDownloader.downloadFile(url, expectedBytes: file.size) { fraction in
                progress((Double(before) + fraction * Double(file.size)) / Double(total))
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: downloaded, to: destination)
            guard try await Task.detached(operation: { try verify(destination, against: file) }).value else {
                try? FileManager.default.removeItem(at: destination)
                throw ModelDownloader.InstallError.checksum
            }
            done += file.size
            progress(Double(done) / Double(total))
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: partial, to: target)
    }

    /// The file is the one listed: its size, and its SHA-256 for a large
    /// file, its Git object id for a small one.
    private static func verify(_ url: URL, against file: Entry) throws -> Bool {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
        guard Int64(size) == file.size else { return false }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if let lfs = file.lfs {
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
                hash.update(data: chunk)
            }
            return hex(hash.finalize()) == lfs.oid
        }
        var hash = Insecure.SHA1()
        hash.update(data: Data("blob \(file.size)\0".utf8))
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hex(hash.finalize()) == file.oid
    }

    private static func hex<D: Digest>(_ digest: D) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
