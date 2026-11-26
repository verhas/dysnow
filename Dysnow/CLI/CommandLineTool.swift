import Foundation

/// Dysnow without its window, for scripts and agents: the app's own
/// executable, started with a command.
///
///     Dysnow.app/Contents/MacOS/Dysnow speak "Hello there." -o hello.m4a
///
/// Only what is asked for goes to the standard output -- the file written,
/// or JSON with `--json`; everything else goes to the standard error, so
/// whatever the speech libraries print there cannot get mixed into it.
enum CommandLineTool {
    enum Command: Equatable {
        case help(topic: String?)
        case version
        case speak(SpeakOptions)
        case voices(language: String?, model: String?, gender: SpeechGender?, json: Bool)
        case models(json: Bool)
        case mcp
    }

    struct SpeakOptions: Equatable {
        var text: String?
        /// A text file to read; "-" for the standard input.
        var file: String?
        var output: String?
        var language: String?
        var voice: String?
        var model: String?
        var gender: SpeechGender?
        var speed: Double = 1
        /// nil: as the file's extension says, Markdown otherwise.
        var format: TextFormat?
        var play = false
        var json = false
        var quiet = false
    }

    struct UsageError: Error, Equatable {
        let message: String
    }

    /// The words the executable is started with that make it the command
    /// line tool; anything else starts the app.
    static let commands: Set<String> = ["speak", "say", "voices", "models", "mcp", "help", "--help", "-h",
                                        "--version", "version"]

    /// The command asked for; nil when the app is to start.
    static func command(in arguments: [String]) -> String? {
        arguments.first.flatMap { commands.contains($0) ? $0 : nil }
    }

    // MARK: Parsing

    static func parse(_ arguments: [String]) throws(UsageError) -> Command {
        guard let first = arguments.first else { return .help(topic: nil) }
        var rest = Array(arguments.dropFirst())
        switch first {
        case "help", "--help", "-h":
            return .help(topic: rest.first)
        case "version", "--version":
            return .version
        case "mcp":
            if let extra = rest.first { throw UsageError(message: "mcp takes no arguments, not \(extra).") }
            return .mcp
        case "models":
            var json = false
            while let argument = rest.first {
                rest.removeFirst()
                switch argument {
                case "--json": json = true
                case "-h", "--help": return .help(topic: "models")
                default: throw UsageError(message: "models does not take \(argument).")
                }
            }
            return .models(json: json)
        case "voices":
            var language: String?, model: String?, gender: SpeechGender?, json = false
            while let argument = rest.first {
                rest.removeFirst()
                switch argument {
                case "-l", "--language": language = try value(of: argument, from: &rest)
                case "-m", "--model": model = try value(of: argument, from: &rest)
                case "-g", "--gender": gender = try self.gender(try value(of: argument, from: &rest))
                case "--json": json = true
                case "-h", "--help": return .help(topic: "voices")
                default: throw UsageError(message: "voices does not take \(argument).")
                }
            }
            return .voices(language: language, model: model, gender: gender, json: json)
        case "speak", "say":
            var options = SpeakOptions()
            var words: [String] = []
            while let argument = rest.first {
                rest.removeFirst()
                switch argument {
                case "-t", "--text": options.text = try value(of: argument, from: &rest)
                case "-f", "--file", "-i", "--input": options.file = try value(of: argument, from: &rest)
                case "-o", "--output": options.output = try value(of: argument, from: &rest)
                case "-l", "--language": options.language = try value(of: argument, from: &rest)
                case "-v", "--voice", "--speaker": options.voice = try value(of: argument, from: &rest)
                case "-m", "--model": options.model = try value(of: argument, from: &rest)
                case "-g", "--gender": options.gender = try gender(try value(of: argument, from: &rest))
                case "-s", "--speed":
                    let text = try value(of: argument, from: &rest)
                    guard let speed = Double(text), speed >= 0.25, speed <= 4 else {
                        throw UsageError(message: "The speed is a number from 0.25 to 4, not \(text).")
                    }
                    options.speed = speed
                case "--markdown": options.format = .markdown
                case "--plain": options.format = .plain
                case "-p", "--play": options.play = true
                case "--json": options.json = true
                case "-q", "--quiet": options.quiet = true
                case "-h", "--help": return .help(topic: "speak")
                case "--":
                    words += rest
                    rest = []
                case "-":
                    options.file = "-"
                default:
                    if argument.hasPrefix("-"), argument.count > 1 {
                        throw UsageError(message: "speak does not take \(argument).")
                    }
                    words.append(argument)
                }
            }
            if !words.isEmpty {
                guard options.text == nil else {
                    throw UsageError(message: "The text is given twice: with --text and as \(words[0]).")
                }
                options.text = words.joined(separator: " ")
            }
            if options.text != nil, options.file != nil {
                throw UsageError(message: "Give the text, or a file to read it from, not both.")
            }
            if options.output == nil, !options.play {
                throw UsageError(message: "Say where to save the speech, with --output, or --play it.")
            }
            return .speak(options)
        default:
            throw UsageError(message: "There is no command \(first).")
        }
    }

    private static func value(of option: String, from rest: inout [String]) throws(UsageError) -> String {
        guard let value = rest.first else { throw UsageError(message: "\(option) needs a value.") }
        rest.removeFirst()
        return value
    }

    private static func gender(_ text: String) throws(UsageError) -> SpeechGender {
        guard let gender = SpeechGender(rawValue: text.lowercased()) else {
            throw UsageError(message: "The gender is female, male or neutral, not \(text).")
        }
        return gender
    }

    // MARK: Running

    /// Runs the command; returns the exit status.
    @MainActor
    static func run(_ arguments: [String], output: StandardOutput) async -> Int32 {
        let command: Command
        do {
            command = try parse(arguments)
        } catch {
            StandardOutput.error("dysnow: \(error.message)\nSee `dysnow help`.")
            return 2
        }
        do {
            switch command {
            case .help(let topic):
                output.write(help(topic))
            case .version:
                output.write("Dysnow \(version)")
            case .models(let json):
                if json {
                    output.write(JSONValue.array(SpeechService.models).encoded(pretty: true))
                } else {
                    for engine in SpeechService.engines {
                        let state = engine.isAvailable ? "installed" : "not installed"
                        output.write("\(engine.name) (\(engine.id)): \(state); \(engine.languages.count) languages")
                    }
                }
            case .voices(let language, let model, let gender, let json):
                let voices = try SpeechService.voices(language: language, model: model, gender: gender)
                if json {
                    output.write(JSONValue.array(voices.map(\.json)).encoded(pretty: true))
                } else if voices.isEmpty {
                    StandardOutput.error("No downloaded voice fits; `dysnow models` shows what is installed.")
                } else {
                    for entry in voices {
                        output.write([entry.model.name, entry.language.id, entry.voice.name, entry.voice.id,
                                      entry.voice.gender.rawValue].joined(separator: "\t"))
                    }
                }
            case .speak(let options):
                try await speak(options, output: output)
            case .mcp:
                await MCPServer(output: output).run()
            }
            await SpeechService.shutDown()
            return 0
        } catch {
            await SpeechService.shutDown()
            StandardOutput.error("dysnow: \(error.localizedDescription)")
            return 1
        }
    }

    @MainActor
    private static func speak(_ options: SpeakOptions, output: StandardOutput) async throws {
        let text: String
        var format = options.format
        if let given = options.text {
            text = given
        } else if let file = options.file, file != "-" {
            let url = URL(filePath: file, relativeTo: .currentDirectory()).absoluteURL
            text = try readText(url)
            format = format ?? TextFormat(fileExtension: url.pathExtension)
        } else if options.file == "-" || isatty(STDIN_FILENO) == 0 {
            text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        } else {
            throw SpeechError.failed("There is no text: give it as words, with --file, or on the standard input.")
        }
        var job = SpeechService.Job(text: text, format: format ?? .markdown,
                                    choice: .init(language: options.language, voice: options.voice,
                                                  model: options.model, gender: options.gender),
                                    speed: options.speed)
        job.output = options.output.map { URL(filePath: $0, relativeTo: .currentDirectory()).absoluteURL }
        let say = { (line: String) in if !options.quiet { StandardOutput.error(line) } }

        let player = options.play ? AudioPlayer() : nil
        var started = false
        let result = try await SpeechService.speak(job, note: say) { _, piece in
            guard let player else { return }
            if !started {
                try player.start(sampleRate: piece.sampleRate)
                started = true
            }
            player.enqueue(piece.samples)
        }
        await player?.drain()
        if options.json {
            output.write(result.json.encoded())
        } else {
            result.warnings.forEach(say)
            say("\(ExportQueue.format(result.duration)) of speech, read by \(result.voice.name) "
                + "(\(result.model), \(result.language.name))")
            if let url = result.output { output.write(url.path) }
        }
    }

    /// Plain text in whatever encoding it is in; rich text and Word
    /// documents as the text in them.
    static func readText(_ url: URL) throws -> String {
        if ["docx", "doc", "rtf", "rtfd", "html", "htm", "odt"].contains(url.pathExtension.lowercased()) {
            return try NSAttributedString(url: url, options: [:], documentAttributes: nil).string
        }
        var encoding = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &encoding) { return text }
        return try String(contentsOf: url, encoding: .isoLatin1)
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    // MARK: Help

    static func help(_ topic: String?) -> String {
        switch topic {
        case "speak", "say": speakHelp
        case "voices": voicesHelp
        case "models": modelsHelp
        case "mcp": mcpHelp
        default: generalHelp
        }
    }

    static let generalHelp = """
        Dysnow reads text aloud, on this Mac, with the models downloaded in the app.

        Usage: dysnow <command> [options]

        Commands:
          speak     make the speech of a text and save it, or play it
          voices    list the voices that can speak now
          models    list the speech models and whether they are installed
          mcp       serve the Model Context Protocol on the standard input and output
          help      show this, or `dysnow help <command>`
          version   show Dysnow's version

        Models are downloaded in the app's Settings. What is not asked for -- the
        language, the model, the speaker -- is as chosen in the app last.
        Started without a command, Dysnow opens its window.
        """

    static let speakHelp = """
        Usage: dysnow speak [options] [text...]

        The text is the words given, or --text, or --file, or the standard input.
        It is read as Markdown, speech tags and all (see MARKUP.md), unless --plain
        or a .txt file says otherwise.

        Options:
          -o, --output FILE     the sound file to write: .m4a, .mp3, .wav, .aiff or .flac
          -p, --play            play the speech as it is made (with or without --output)
          -t, --text TEXT       the text to read
          -f, --file FILE       read the text from a file (.md, .txt, .docx, .rtf...); - is stdin
          -l, --language LANG   by id or name: en-us, de, "British English", Hungarian
          -v, --voice NAME      a speaker's name or id: Heart, af_heart
          -m, --model NAME      kokoro, piper, qwen3, xtts... (the start of the name will do)
          -g, --gender G        female, male or neutral
          -s, --speed X         0.25 to 4; 1 is the voice's own pace (default)
              --plain           the text is plain text, tags in [brackets]
              --markdown        the text is Markdown (default)
              --json            print the result as one line of JSON
          -q, --quiet           say nothing on the standard error but errors

        Prints the path of the file written. Exits with 1 when the speech could not
        be made, 2 when the command is wrong.

        Examples:
          dysnow speak "Good morning." -o morning.m4a
          dysnow speak -f chapter.md -l en-gb -v Fable -o chapter.mp3
          echo "Szia!" | dysnow speak -l hu -o szia.wav --json
        """

    static let voicesHelp = """
        Usage: dysnow voices [-l LANGUAGE] [-m MODEL] [-g GENDER] [--json]

        Lists the voices that can speak now: model, language, name, id and gender,
        separated by tabs, or as JSON.
        """

    static let modelsHelp = """
        Usage: dysnow models [--json]

        Lists the speech models, whether each is installed, and its languages.
        """

    static let mcpHelp = """
        Usage: dysnow mcp

        Serves the Model Context Protocol on the standard input and output, for an
        agent to make speech with. Its tools are speak, list_voices and list_models.
        For Claude Code:

          claude mcp add dysnow -- /Applications/Dysnow.app/Contents/MacOS/Dysnow mcp
        """
}

/// Where the command line's results go: the standard output as it was at
/// the start. The process's own standard output is pointed at the standard
/// error, so that nothing else -- a library's messages -- lands in it.
final class StandardOutput: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()

    /// Takes the standard output over; once, before anything is printed.
    static func takeOver() -> StandardOutput {
        let saved = dup(STDOUT_FILENO)
        dup2(STDERR_FILENO, STDOUT_FILENO)
        return StandardOutput(handle: FileHandle(fileDescriptor: saved, closeOnDealloc: true))
    }

    init(handle: FileHandle) {
        self.handle = handle
    }

    /// Writes a line.
    func write(_ line: String) {
        lock.withLock { try? handle.write(contentsOf: Data((line + "\n").utf8)) }
    }

    static func error(_ line: String) {
        try? FileHandle.standardError.write(contentsOf: Data((line + "\n").utf8))
    }
}
