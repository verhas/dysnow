import SwiftUI

/// The text on the left of everything: the editor, with the voice to read it
/// in and what to do with it in the toolbar.
struct ContentView: View {
    @Bindable var model: AppModel
    private let installer = KokoroInstaller.shared
    private let piperInstaller = PiperInstaller.shared
    private let qwen3Installer = Qwen3Installer.shared
    private let xttsInstaller = XTTSInstaller.shared
    private let voiceStore = MyVoiceStore.shared

    var body: some View {
        VStack(spacing: 0) {
            if model.engine is KokoroEngine && !installer.isInstalled {
                ModelBanner(installer: installer)
                Divider()
            } else if model.engine is PiperEngine, let voice = model.voice.flatMap({ PiperVoice.withID($0.id) }),
                      !piperInstaller.isInstalled(voice) {
                PiperVoiceBanner(voice: voice, installer: piperInstaller)
                Divider()
            } else if model.engine is Qwen3Engine && !qwen3Installer.isInstalled(qwen3Installer.variant) {
                Qwen3Banner(installer: qwen3Installer)
                Divider()
            } else if model.engine is XTTSEngine && !xttsInstaller.isReady {
                XTTSBanner(installer: xttsInstaller)
                Divider()
            } else if let engine = model.engine as? CloningEngine {
                if !CloningInstaller.shared(engine.model).isInstalled {
                    CloningBanner(installer: .shared(engine.model))
                    Divider()
                } else if model.voices.isEmpty {
                    NoOwnVoiceBanner(engine: engine, gender: model.gender) { model.voiceSheet = .newVoice }
                    Divider()
                }
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
        .navigationSubtitle(model.hasUnsavedChanges && !model.text.isEmpty ? "Edited"
            : model.fileURL == nil ? "" : "Dysnow")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            installer.refresh()
            piperInstaller.refresh()
            qwen3Installer.refresh()
            CloningModel.allCases.forEach { CloningInstaller.shared($0).refresh() }
            xttsInstaller.refresh()
        }
        .sheet(item: $model.voiceSheet) { sheet in
            VoiceRecordingSheet(purpose: sheet, store: voiceStore, languageID: model.languageID,
                                engineID: model.engineID) { id in
                model.voicesChanged(selecting: id)
            }
        }
        .onChange(of: voiceStore.voices) { model.voicesChanged() }
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
        MarkupTextEditor(text: $model.text, selection: $model.selection, original: $model.original,
                         syntax: model.textFormat.syntax,
                         isEditable: model.preparing == nil, completer: model.completer)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(alignment: .topLeading) {
                if model.text.isEmpty { EditorPlaceholder() }
            }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("New Text", systemImage: "square.and.pencil", action: model.newText)
                .help("Start a new text: the editor is emptied, and what is pasted next is the new original (⌘N)")
        }
        ToolbarItem(placement: .navigation) {
            Button("Open", systemImage: "doc", action: model.openFile)
                .help("Open a text file")
        }
        ToolbarItem(placement: .navigation) {
            Button("Prepare with Apple Intelligence", systemImage: "wand.and.sparkles", action: model.prepareText)
                .disabled(model.text.isEmpty || model.preparing != nil)
                .help("Have Apple Intelligence fix typos and write out abbreviations, signs and sums as they "
                    + "are said: e.g. as \u{201C}for example\u{201D}, 2*4 as \u{201C}two times four\u{201D}")
        }
        ToolbarItemGroup(placement: .automatic) {
            Picker("Format", selection: $model.textFormat) {
                ForEach(TextFormat.allCases) { Text($0.title).tag($0) }
            }
            .help("How the text is written: what in it is markup, and how the speech tags look")
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
                if model.engineTakesOwnVoices {
                    Divider()
                    Text("Add a Voice…").tag(AppModel.addVoiceTag)
                }
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
                .help("Save the speech as a sound file (⌥⌘S)")
        }
    }

    private var isPlaying: Bool {
        if case .playing = model.activity { true } else { false }
    }

    private var isActive: Bool { model.activity != .idle }
}

/// What is shown in the editor while it is empty, in the editor's font.
private struct EditorPlaceholder: View {
    @AppStorage(EditorSettings.fontKey) private var fontFamily = ""
    @AppStorage(EditorSettings.sizeKey) private var fontSize = EditorSettings.defaultSize

    var body: some View {
        Text("Type or paste text here, open a text file with ⌘O, or drop one on the window. "
            + "⌃Space writes the tags that set how it is read.")
            .font(Font(EditorSettings.font(family: fontFamily, size: fontSize)))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 17)
            .padding(.vertical, 10)
            .allowsHitTesting(false)
    }
}

/// What is going on, at the bottom of the window, and the speed.
private struct StatusBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            if let done = model.preparing {
                ProgressView(value: done).frame(width: 120)
                Text("Apple Intelligence is going through the text…")
                Button("Stop", action: model.stopPreparing)
                    .controlSize(.small)
            } else {
                activity
            }
            Spacer()
            ExportIndicator(model: model)
            Text(counts)
            Divider().frame(height: 14)
            speed
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var activity: some View {
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
    }

    /// The speed; off, with a word why, for a model that does not follow it.
    private var speed: some View {
        let follows = model.engine.followsSpeed
        return HStack(spacing: 4) {
            Image(systemName: "tortoise")
            Slider(value: $model.speed, in: 0.5...2.0)
                .controlSize(.mini)
                .frame(width: 90)
            Image(systemName: "hare")
            Text(String(format: "%.1f×", model.speed))
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
            if !follows {
                Image(systemName: "questionmark.circle")
                    .help("\(model.engine.name) does not follow the speed setting.")
            }
        }
        .disabled(!follows)
        .help(follows ? "Speed" : "\(model.engine.name) does not follow the speed setting.")
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
