import XCTest
@testable import Dysnow

final class CommandLineTests: XCTestCase {
    private func parse(_ arguments: String...) throws -> CommandLineTool.Command {
        try CommandLineTool.parse(arguments)
    }

    func testOnlyCommandsStartTheTool() {
        XCTAssertEqual(CommandLineTool.command(in: ["speak", "hi"]), "speak")
        XCTAssertEqual(CommandLineTool.command(in: ["mcp"]), "mcp")
        XCTAssertNil(CommandLineTool.command(in: []))
        // What Xcode passes the app when it runs it.
        XCTAssertNil(CommandLineTool.command(in: ["-NSDocumentRevisionsDebugMode", "YES"]))
    }

    func testSpeakTakesItsOptions() throws {
        let command = try parse("speak", "-o", "out.mp3", "-l", "de", "-v", "Thorsten", "-m", "piper",
                                "-g", "Male", "-s", "1.5", "--plain", "--json", "Guten", "Tag.")
        var expected = CommandLineTool.SpeakOptions()
        expected.text = "Guten Tag."
        expected.output = "out.mp3"
        expected.language = "de"
        expected.voice = "Thorsten"
        expected.model = "piper"
        expected.gender = .male
        expected.speed = 1.5
        expected.format = .plain
        expected.json = true
        XCTAssertEqual(command, .speak(expected))
    }

    func testSpeakNeedsSomewhereToGo() {
        XCTAssertThrowsError(try parse("speak", "hi"))
        XCTAssertNoThrow(try parse("speak", "--play", "hi"))
    }

    func testSpeakRefusesWhatItCannotDo() {
        XCTAssertThrowsError(try parse("speak", "-o", "a.wav", "-s", "9", "hi"))
        XCTAssertThrowsError(try parse("speak", "-o", "a.wav", "-g", "robot", "hi"))
        XCTAssertThrowsError(try parse("speak", "-o", "a.wav", "--loud", "hi"))
        XCTAssertThrowsError(try parse("speak", "-o", "a.wav", "-t", "hi", "there"))
        XCTAssertThrowsError(try parse("speak", "-o", "a.wav", "-f", "a.md", "-t", "hi"))
        XCTAssertThrowsError(try parse("speak", "-o"))
    }

    func testDashesEndTheOptions() throws {
        guard case .speak(let options) = try parse("speak", "-o", "a.wav", "--", "-5", "degrees") else {
            return XCTFail("not speak")
        }
        XCTAssertEqual(options.text, "-5 degrees")
    }

    func testListings() throws {
        XCTAssertEqual(try parse("voices", "-l", "hu", "--json"),
                       .voices(language: "hu", model: nil, gender: nil, json: true))
        XCTAssertEqual(try parse("models"), .models(json: false))
        XCTAssertEqual(try parse("help", "speak"), .help(topic: "speak"))
        XCTAssertThrowsError(try parse("mcp", "extra"))
    }
}

@MainActor
final class MCPServerTests: XCTestCase {
    private let server = MCPServer(output: StandardOutput(handle: .nullDevice))

    private func answer(_ line: String) async throws -> JSONValue? {
        try await server.handle(line).map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
    }

    func testInitializeAgreesOnAVersion() async throws {
        let known = try await answer(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)
        XCTAssertEqual(known?["id"], 1)
        XCTAssertEqual(known?["result"]?["protocolVersion"], "2025-03-26")
        XCTAssertEqual(known?["result"]?["serverInfo"]?["name"], "dysnow")
        let unknown = try await answer(#"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
        XCTAssertEqual(unknown?["result"]?["protocolVersion"], .string(MCPServer.protocolVersions[0]))
    }

    func testNotificationsAreNotAnswered() async throws {
        let none = try await answer(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(none)
    }

    func testListsItsTools() async throws {
        let list = try await answer(#"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#)
        guard case .array(let tools)? = list?["result"]?["tools"] else { return XCTFail("no tools") }
        XCTAssertEqual(tools.compactMap { $0["name"]?.string }, ["speak", "list_voices", "list_models"])
    }

    func testErrors() async throws {
        let parse = try await answer("not json")
        XCTAssertEqual(parse?["error"]?["code"], -32700)
        let method = try await answer(#"{"jsonrpc":"2.0","id":3,"method":"resources/list"}"#)
        XCTAssertEqual(method?["error"]?["code"], -32601)
        let tool = try await answer(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"sing"}}"#)
        XCTAssertEqual(tool?["error"]?["code"], -32602)
    }

    func testToolFailuresAreResults() async throws {
        let missing = try await answer(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"speak","arguments":{}}}"#)
        XCTAssertEqual(missing?["result"]?["isError"], true)
        let speed = try await answer(
            #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"speak","arguments":{"text":"x","speed":10}}}"#)
        XCTAssertEqual(speed?["result"]?["isError"], true)
    }
}
