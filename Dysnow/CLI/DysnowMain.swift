import Foundation

/// Where Dysnow starts: the app, or, given a command, the command line tool.
///
///     Dysnow.app/Contents/MacOS/Dysnow speak "Hello." -o hello.m4a
///     Dysnow.app/Contents/MacOS/Dysnow mcp
@main
enum DysnowMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard CommandLineTool.command(in: arguments) != nil else {
            DysnowApp.main()
            return
        }
        reexecuteIfLinked()
        // Before anything can print: only results go to the standard output.
        let output = StandardOutput.takeOver()
        Task { @MainActor in
            exit(await CommandLineTool.run(arguments, output: output))
        }
        dispatchMain()
    }

    /// Started through a link -- `/usr/local/bin/dysnow` -- the executable
    /// is not seen to be in the app: its settings, its resources, its
    /// version would not be found. It starts itself again from where it is.
    private static func reexecuteIfLinked() {
        var size = UInt32(PATH_MAX)
        var path = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&path, &size) == 0, let real = realpath(path, nil) else { return }
        defer { free(real) }
        guard strcmp(real, path) != 0 else { return }
        var arguments: [UnsafeMutablePointer<CChar>?] = CommandLine.arguments.map { strdup($0) }
        arguments.append(nil)
        execv(real, arguments)
        // Not reached unless it failed: then it goes on as it is.
    }
}
