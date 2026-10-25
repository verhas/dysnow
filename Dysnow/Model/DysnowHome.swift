import Foundation

/// Where Dysnow keeps its files: the downloaded voice models.
enum DysnowHome {
    /// `~/.dysnow`, unless DYSNOW_HOME names another directory -- for a trial
    /// run that leaves the real one alone.
    static let root: URL = {
        if let path = ProcessInfo.processInfo.environment["DYSNOW_HOME"], !path.isEmpty {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".dysnow")
    }()
}
