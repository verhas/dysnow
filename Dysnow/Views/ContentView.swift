import SwiftUI

/// The text on the left of everything: the editor, with the voice to read it
/// in and what to do with it in the toolbar.
struct ContentView: View {
    @Bindable var model: AppModel
    private let installer = KokoroInstaller.shared
    private let piperInstaller = PiperInstaller.shared

    var body: some View {
        VStack(spacing: 0) {
            if model.engine is KokoroEngine && !installer.isInstalled {
                ModelBanner(installer: installer)
                Divider()
            } else if model.engine is PiperEngine, let voice = model.voice.flatMap({ PiperVoice.withID($0.id) }),
                      !piperInstaller.isInstalled(voice) {
                PiperVoiceBanner(voice: voice, installer: piperInstaller)
                Divider()
            }
            editor
            if model.showsExports {
                Divider()
                ExportQueueView(queue: model.exports) { model.showsExports = false }
            }
            Divider()
            StatusBar(model: model)
        }
        .toolbar { toolbar }
        .navigationTitle(model.fileURL?.lastPathComponent ?? "Dysnow")
        .navigationSubtitle(model.fileURL == nil ? "" : "Dysnow")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            installer.refresh()
            piperInstaller.refresh()
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url)
            return true
        }
        .alert("Dysnow", isPresented: Binding(get: { model.errorMessage != nil },
                                              set: { if !$0 { model.errorMessage = nil } })) {
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var editor: some View {
        TextEditor(text: $model.text, selection: $model.selection)
            .font(.system(size: 15))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(alignment: .topLeading) {
                if model.text.isEmpty {
                    Text("Type or paste text here, open a text file with ⌘O, or drop one on the window.")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("Open", systemImage: "doc", action: model.openFile)
                .help("Open a text file")
        }
        ToolbarItemGroup(placement: .automatic) {
            Picker("Language", selection: $model.languageID) {
                ForEach(model.languages) { Text($0.name).tag($0.id) }
            }
            .help("The language of the text")
            Picker("Gender", selection: $model.gender) {
                ForEach(model.genders) { Text($0.title).tag($0) }
            }
            .help("A woman's or a man's voice")
            Picker("Model", selection: $model.engineID) {
                ForEach(model.availableEngines, id: \.id) { Text($0.name).tag($0.id) }
            }
            .help("The speech model the voice is of")
            Picker("Speaker", selection: Binding(get: { model.voiceID }, set: model.chooseVoice)) {
                ForEach(model.voices) { Text($0.name).tag($0.id) }
            }
            .help("The voice it is read in: picking one lets it say hello")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill",
                   action: model.togglePlay)
                .disabled(!model.canSpeak && !isActive)
                .help(model.selectionIsEmpty ? "Read the text aloud (⌘↩)" : "Read the selection aloud (⌘↩)")
            Button("Play from Cursor", systemImage: "text.line.first.and.arrowtriangle.forward",
                   action: model.playFromCursor)
                .disabled(!model.canSpeak && !isActive)
                .help("Read from the sentence the cursor is in (⌥⌘↩)")
            Button("Stop", systemImage: "stop.fill", action: model.stop)
                .disabled(!isActive)
                .help("Stop (⌘.)")
            Button("Save Audio", systemImage: "square.and.arrow.down", action: model.saveAudio)
                .disabled(!model.canSpeak)
                .help("Save the speech as a sound file (⌘S)")
        }
    }

    private var isPlaying: Bool {
        if case .playing = model.activity { true } else { false }
    }

    private var isActive: Bool { model.activity != .idle }
}

/// What is going on, at the bottom of the window, and the speed.
private struct StatusBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            switch model.activity {
            case .idle:
                Text(model.status.isEmpty ? "Ready" : model.status)
            case .playing(let made), .paused(let made):
                Text(model.activity == .paused(made: made) ? "Paused" : model.status)
                if made < 1 {
                    ProgressView(value: made).frame(width: 120)
                    Text("making speech…")
                }
            }
            Spacer()
            ExportIndicator(model: model)
            Text(counts)
            Divider().frame(height: 14)
            HStack(spacing: 4) {
                Image(systemName: "tortoise")
                Slider(value: $model.speed, in: 0.5...2.0)
                    .controlSize(.mini)
                    .frame(width: 90)
                Image(systemName: "hare")
                Text(String(format: "%.1f×", model.speed))
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
            }
            .help("Speed")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var counts: String {
        let text = model.textToSpeak
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let scope = model.selectionIsEmpty ? "" : "Selection: "
        return "\(scope)\(words) words, \(text.count) characters"
    }
}

/// How the saving is going, in the status bar; clicking it shows or hides
/// the list of files being saved.
private struct ExportIndicator: View {
    let model: AppModel

    var body: some View {
        let queue = model.exports
        if !queue.jobs.isEmpty {
            Button {
                model.showsExports.toggle()
            } label: {
                HStack(spacing: 6) {
                    if let running = queue.running, case .running(let done) = running.state {
                        ProgressView().controlSize(.mini)
                        Text("Saving \(running.url.lastPathComponent), "
                            + done.formatted(.percent.precision(.fractionLength(0))))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if queue.waitingCount > 0 {
                            Text("+\(queue.waitingCount) waiting")
                        }
                    } else {
                        Image(systemName: "tray.full")
                        Text(summary(queue))
                    }
                    Image(systemName: model.showsExports ? "chevron.down" : "chevron.up")
                }
            }
            .buttonStyle(.borderless)
            .help(model.showsExports ? "Hide the files being saved" : "Show the files being saved")
            Divider().frame(height: 14)
        }
    }

    private func summary(_ queue: ExportQueue) -> String {
        let saved = queue.jobs.count { if case .finished = $0.state { true } else { false } }
        let failed = queue.jobs.count { if case .failed = $0.state { true } else { false } }
        var parts = ["\(saved) saved"]
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: ", ")
    }
}
