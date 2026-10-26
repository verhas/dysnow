import SwiftUI

@main
struct DysnowApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        Task { @MainActor in EditorSettings.applyTheme() }
    }

    var body: some Scene {
        // One window: closing it quits the app.
        Window("Dysnow", id: "main") {
            ContentView(model: model)
                .onAppear { delegate.model = model }
                .frame(minWidth: 900, minHeight: 420)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Text", action: model.newText)
                    .keyboardShortcut("n")
                Button("Open…", action: model.openFile)
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Text", action: model.saveText)
                    .keyboardShortcut("s")
                Button("Save Text As…", action: model.saveTextAs)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Save Audio…", action: model.saveAudio)
                    .keyboardShortcut("s", modifiers: [.command, .option])
                    .disabled(!model.canSpeak)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Restore All Changes") {
                    NSApp.sendAction(#selector(MarkupTextView.restoreAllChanges(_:)), to: nil, from: nil)
                }
                .disabled(model.original.isEmpty || model.original == model.text)
                Button("Keep All Changes") { model.original = model.text }
                    .disabled(model.original == model.text)
                    .help("Changes are shown against the text as it is now")
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
                Button("Prepare with Apple Intelligence", action: model.prepareText)
                    .keyboardShortcut("p", modifiers: [.command, .option])
                    .disabled(model.text.isEmpty || model.preparing != nil)
                Button("Complete Markup") {
                    NSApp.sendAction(#selector(MarkupTextView.completeMarkup(_:)), to: nil, from: nil)
                }
                .keyboardShortcut(.space, modifiers: .control)
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

        WindowGroup("About the Model", id: ModelInfo.windowID, for: String.self) { $engineID in
            ModelInfoView(engineID: engineID ?? "")
        }
        .windowResizability(.contentSize)
    }

    private var isPlaying: Bool {
        if case .playing = model.activity { true } else { false }
    }
}

/// Opens the files sent to the app: Open With in the Finder, a file dropped
/// on the Dock icon, `open -a Dysnow file.md`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var model: AppModel? {
        didSet {
            pending.forEach { model?.open($0) }
            pending = []
        }
    }
    @MainActor private var pending: [URL] = []

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let model { model.open(url) } else { pending = [url] }
    }
}
