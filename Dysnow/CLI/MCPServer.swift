import Foundation

/// The Model Context Protocol, served on the standard input and output: a
/// JSON-RPC message a line each way. An agent makes speech with its tools:
/// `speak`, `list_voices` and `list_models`. Requests are answered one at a
/// time, in the order they come.
@MainActor
final class MCPServer {
    /// The protocol versions it speaks, newest first.
    static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    private let output: StandardOutput
    /// The version agreed on with the client.
    private(set) var protocolVersion = MCPServer.protocolVersions[0]

    init(output: StandardOutput) {
        self.output = output
    }

    /// Answers requests until the standard input ends.
    func run() async {
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                if let answer = await handle(line) { output.write(answer) }
            }
        } catch {
            StandardOutput.error("dysnow mcp: \(error.localizedDescription)")
        }
    }

    /// The answer to a line, as a line; nil for a notification.
    func handle(_ line: String) async -> String? {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else {
            return Self.error(id: .null, code: -32700, message: "Parse error").encoded()
        }
        return await respond(to: message)?.encoded()
    }

    func respond(to message: JSONValue) async -> JSONValue? {
        guard case .object = message, let method = message["method"]?.string else {
            // A response to a request of ours -- there are none -- or junk.
            if message["id"] != nil, message["result"] == nil, message["error"] == nil {
                return Self.error(id: message["id"] ?? .null, code: -32600, message: "Invalid Request")
            }
            return nil
        }
        guard let id = message["id"] else { return nil }  // A notification: nothing to say.
        let params = message["params"] ?? [:]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"]?.string ?? ""
            protocolVersion = Self.protocolVersions.contains(asked) ? asked : Self.protocolVersions[0]
            return Self.result(id: id, [
                "protocolVersion": .string(protocolVersion),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "dysnow", "title": "Dysnow", "version": .string(CommandLineTool.version)],
                "instructions": .string(Self.instructions),
            ])
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": .array(Self.tools)])
        case "tools/call":
            guard let name = params["name"]?.string else {
                return Self.error(id: id, code: -32602, message: "tools/call needs the tool's name")
            }
            let arguments = params["arguments"] ?? [:]
            do {
                return Self.result(id: id, try await call(name, arguments))
            } catch let error as UnknownTool {
                return Self.error(id: id, code: -32602, message: "Unknown tool: \(error.name)")
            } catch {
                return Self.result(id: id, [
                    "content": [["type": "text", "text": .string(error.localizedDescription)]],
                    "isError": true,
                ])
            }
        default:
            return Self.error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private struct UnknownTool: Error {
        let name: String
    }

    // MARK: Tools

    private func call(_ name: String, _ arguments: JSONValue) async throws -> [String: JSONValue] {
        switch name {
        case "speak": return try await speak(arguments)
        case "list_voices":
            let voices = try SpeechService.voices(language: arguments["language"]?.string,
                                                  model: arguments["model"]?.string,
                                                  gender: try gender(arguments["gender"]))
            let list = JSONValue.array(voices.map(\.json))
            let summary = voices.isEmpty ? "No downloaded voice fits; list_models shows what is installed."
                : list.encoded()
            return ["content": [["type": "text", "text": .string(summary)]],
                    "structuredContent": ["voices": list]]
        case "list_models":
            let list = JSONValue.array(SpeechService.models)
            return ["content": [["type": "text", "text": .string(list.encoded())]],
                    "structuredContent": ["models": list]]
        default:
            throw UnknownTool(name: name)
        }
    }

    private func speak(_ arguments: JSONValue) async throws -> [String: JSONValue] {
        let text: String
        var format = try textFormat(arguments["text_format"])
        if let given = arguments["text"]?.string, !given.isEmpty {
            text = given
        } else if let path = arguments["input_path"]?.string, !path.isEmpty {
            let url = Self.url(path)
            text = try CommandLineTool.readText(url)
            format = format ?? TextFormat(fileExtension: url.pathExtension)
        } else {
            throw SpeechError.failed("Give the text to read, as text or input_path.")
        }
        let output: URL
        if let path = arguments["output_path"]?.string, !path.isEmpty {
            output = Self.url(path)
        } else {
            let kind = arguments["audio_format"]?.string?.lowercased() ?? "m4a"
            guard let format = ExportFormat(fileExtension: kind) else {
                throw SpeechError.failed("audio_format is m4a, mp3, wav, aiff or flac, not \(kind).")
            }
            let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
                .timeSeparator(.omitted).dateSeparator(.omitted).dateTimeSeparator(.standard))
            output = FileManager.default.temporaryDirectory.appending(path: "dysnow", directoryHint: .isDirectory)
                .appending(path: "speech-\(stamp)-\(UUID().uuidString.prefix(8)).\(format.fileExtension)")
        }
        var speed = 1.0
        if let value = arguments["speed"] {
            guard let number = value.number, number >= 0.25, number <= 4 else {
                throw SpeechError.failed("speed is a number from 0.25 to 4.")
            }
            speed = number
        }
        let job = SpeechService.Job(
            text: text, format: format ?? .markdown,
            choice: .init(language: arguments["language"]?.string, voice: arguments["voice"]?.string,
                          model: arguments["model"]?.string, gender: try gender(arguments["gender"])),
            speed: speed, output: output)
        let result = try await SpeechService.speak(job, note: { StandardOutput.error("dysnow mcp: \($0)") })

        var summary = "Saved \(String(format: "%.1f", result.duration)) seconds of speech to \(output.path), "
            + "read by \(result.voice.name) (\(result.model), \(result.language.name))."
        if !result.warnings.isEmpty { summary += "\n" + result.warnings.joined(separator: "\n") }
        var content: [JSONValue] = [["type": "text", "text": .string(summary)]]
        if arguments["return_audio"]?.bool == true, protocolVersion != "2024-11-05" {
            let data = try Data(contentsOf: output)
            content.append(["type": "audio", "data": .string(data.base64EncodedString()),
                            "mimeType": .string(Self.mimeType(of: output))])
        }
        return ["content": .array(content), "structuredContent": result.json]
    }

    private func gender(_ value: JSONValue?) throws -> SpeechGender? {
        guard let text = value?.string, !text.isEmpty else { return nil }
        guard let gender = SpeechGender(rawValue: text.lowercased()) else {
            throw SpeechError.failed("gender is female, male or neutral, not \(text).")
        }
        return gender
    }

    private func textFormat(_ value: JSONValue?) throws -> TextFormat? {
        guard let text = value?.string, !text.isEmpty else { return nil }
        guard let format = TextFormat(rawValue: text.lowercased()) else {
            throw SpeechError.failed("text_format is markdown or plain, not \(text).")
        }
        return format
    }

    /// A path as given; relative to the server's working directory, `~` for
    /// home.
    private static func url(_ path: String) -> URL {
        URL(filePath: (path as NSString).expandingTildeInPath, relativeTo: .currentDirectory()).absoluteURL
    }

    private static func mimeType(of url: URL) -> String {
        switch ExportFormat(fileExtension: url.pathExtension) {
        case .m4a: "audio/mp4"
        case .mp3: "audio/mpeg"
        case .wav: "audio/wav"
        case .aiff: "audio/aiff"
        case .flac: "audio/flac"
        case nil: "application/octet-stream"
        }
    }

    // MARK: Messages

    private static func result(id: JSONValue, _ result: [String: JSONValue]) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": .object(result)]
    }

    private static func error(id: JSONValue, code: Int, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]]
    }

    static let instructions = """
        Dysnow makes speech of text on this Mac, with downloaded speech models. \
        Call speak with the text and an absolute output_path ending in .m4a, .mp3, .wav, .aiff or .flac; \
        it returns when the file is written. The text is Markdown by default, and may carry Dysnow's speech \
        tags (<!-- tts:mood value="excited" --> ... <!-- /tts:mood -->, tts:speed, tts:speaker, \
        tts:language, tts:set). Use list_voices to find the voices for a language.
        """

    static let tools: [JSONValue] = [
        [
            "name": "speak",
            "title": "Make speech",
            "description": """
                Reads a text aloud into a sound file, with a voice of a model installed in Dysnow. \
                Unset choices are as the Dysnow app has them. Returns the file's path, the speech's \
                length in seconds, and the voice used.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "The text to read (Markdown unless text_format is plain)."],
                    "input_path": ["type": "string",
                                   "description": "A file to read the text from instead: .md, .txt, .docx, .rtf."],
                    "output_path": ["type": "string", "description": """
                        Absolute path of the sound file to write; its extension (.m4a, .mp3, .wav, .aiff, \
                        .flac) picks the kind. Default: a new file in the temporary directory.
                        """],
                    "audio_format": ["type": "string", "enum": ["m4a", "mp3", "wav", "aiff", "flac"],
                                     "description": "The kind of file when output_path is not given. Default m4a."],
                    "text_format": ["type": "string", "enum": ["markdown", "plain"],
                                    "description": "How the text is written. Default markdown."],
                    "language": ["type": "string",
                                 "description": "Language id or name: en-us, en-gb, de, Hungarian, ..."],
                    "voice": ["type": "string", "description": "A speaker's name or id, from list_voices."],
                    "model": ["type": "string", "description": "kokoro, piper, qwen3, xtts, zipvoice, pocket ..."],
                    "gender": ["type": "string", "enum": ["female", "male", "neutral"]],
                    "speed": ["type": "number", "minimum": 0.25, "maximum": 4,
                              "description": "1 is the voice's own pace. Default 1."],
                    "return_audio": ["type": "boolean",
                                     "description": "Also return the sound itself, base64, in the result. Default false."],
                ],
                "anyOf": [["required": ["text"]], ["required": ["input_path"]]],
            ],
        ],
        [
            "name": "list_voices",
            "title": "List voices",
            "description": "Lists the voices that can speak now, of the installed models.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "language": ["type": "string", "description": "Only those of this language, by id or name."],
                    "model": ["type": "string", "description": "Only those of this model."],
                    "gender": ["type": "string", "enum": ["female", "male", "neutral"]],
                ],
            ],
            "annotations": ["readOnlyHint": true],
        ],
        [
            "name": "list_models",
            "title": "List models",
            "description": "Lists Dysnow's speech models, whether each is installed, and the languages it speaks.",
            "inputSchema": ["type": "object", "properties": [:]],
            "annotations": ["readOnlyHint": true],
        ],
    ]
}
