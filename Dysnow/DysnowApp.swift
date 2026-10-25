import SwiftUI

@main
struct DysnowApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // One window: closing it quits the app.
        Window("Dysnow", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 420)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…", action: model.openFile)
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Audio…", action: model.saveAudio)
                    .keyboardShortcut("s")
                    .disabled(!model.canSpeak)
            }
            CommandMenu("Speech") {
                Button(isPlaying ? "Pause" : "Play", action: model.togglePlay)
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Play from Cursor", action: model.playFromCursor)
                    .keyboardShortcut(.return, modifiers: [.command, .option])
                Button("Stop", action: model.stop)
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(model.activity == .idle)
                Divider()
                Button(model.showsExports ? "Hide Saving Queue" : "Show Saving Queue") {
                    model.showsExports.toggle()
                }
                .keyboardShortcut("j")
            }
        }

        Settings {
            SettingsView()
        }
    }

    private var isPlaying: Bool {
        if case .playing = model.activity { true } else { false }
    }
}
