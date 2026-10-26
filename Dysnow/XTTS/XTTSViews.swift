import AppKit
import SwiftUI

/// The pickers for XTTS's Python, environment and model.
@MainActor
enum XTTSPanel {
    static func python() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose Python 3.11: a python3.11 program, such as /opt/homebrew/bin/python3.11."
        panel.prompt = "Use This Python"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func environment() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose a Python 3.11 environment with XTTS's libraries in it: the folder holding bin/python, "
            + "such as XTTS Voice Generator's xtts-env."
        panel.prompt = "Use This Environment"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func existingModel() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder of XTTS v2's model: it holds model.pth, config.json, vocab.json and "
            + "speakers_xtts.pth."
        panel.prompt = "Use This Model"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        panel.directoryURL = XTTSModel.coquiDirectory.deletingLastPathComponent()
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func downloadDestination() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder to download XTTS v2's model into (about 1.9 GB; it goes into an "
            + "\(XTTSModel.huggingFace.folderName) folder there)."
        panel.prompt = "Download Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Says what XTTS v2 still needs, in the main window, and gets it.
struct XTTSBanner: View {
    let installer: XTTSInstaller

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: installer.environmentIsReady ? "arrow.down.circle" : "wrench.and.screwdriver")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                XTTSNeeds(installer: installer)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.yellow.opacity(0.12))
        .task { if !installer.hasLooked { await installer.lookForPython() } }
    }
}

/// The first thing XTTS v2 still needs, and the buttons to get it. In the
/// Settings, which have buttons of their own, only the work going on, and
/// how to get Python when there is none.
private struct XTTSNeeds: View {
    let installer: XTTSInstaller
    var inSettings = false

    var body: some View {
        if case .working(let line, let fraction) = installer.environmentStep {
            Text("Setting up XTTS's Python libraries").bold()
            HStack {
                if let fraction {
                    ProgressView(value: fraction).frame(width: 200)
                } else {
                    ProgressView().controlSize(.small)
                }
                Button("Cancel", action: installer.cancel)
            }
            Text(line).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        } else if !installer.environmentIsReady && (!inSettings || installer.python == nil) {
            environment
        } else if !installer.modelIsInstalled && !inSettings {
            model
        }
        if case .failed(let message) = installer.environmentStep {
            Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled).lineLimit(6)
        }
    }

    @ViewBuilder private var environment: some View {
        if let python = installer.python {
            Text("XTTS v2 runs in Python, with libraries of its own").bold()
            Text("Dysnow sets them up once, in \(XTTSEnvironment.defaultEnvironment.abbreviatedPath), with Python "
                + "\(python.version) in \(python.url.deletingLastPathComponent().abbreviatedPath): about 2 GB, "
                + "downloaded by pip, which takes some minutes.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Set Up", action: installer.setUpEnvironment)
                    .keyboardShortcut(.defaultAction)
                otherMenu
            }
        } else if installer.hasLooked {
            Text("XTTS v2 needs Python 3.11, which is not on this Mac").bold()
            Text(XTTSEnvironment.installAdvice)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if !installer.otherPythons.isEmpty {
                Text("Found, but not usable: " + installer.otherPythons
                    .map { "\($0.version) (\($0.machine)) in \($0.url.deletingLastPathComponent().abbreviatedPath)" }
                    .joined(separator: ", ") + ".")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Look Again") { Task { await installer.lookForPython() } }
                    .keyboardShortcut(.defaultAction)
                Link("python.org", destination: URL(string: "https://www.python.org/downloads/macos/")!)
                otherMenu
            }
        } else {
            HStack {
                ProgressView().controlSize(.small)
                Text("Looking for Python 3.11…").foregroundStyle(.secondary)
            }
        }
    }

    private var otherMenu: some View {
        Menu("Other") {
            Button("Choose Python 3.11…") {
                guard let url = XTTSPanel.python() else { return }
                Task { await installer.choosePython(url) }
            }
            Button("Use an Existing Environment…") {
                guard let folder = XTTSPanel.environment() else { return }
                installer.useEnvironment(folder)
            }
        }
        .fixedSize()
    }

    @ViewBuilder private var model: some View {
        Text("XTTS v2's model is needed to speak").bold()
        Text("It is not in \(installer.modelDirectory.abbreviatedPath). It is downloaded once, about 1.9 GB. "
            + "Its licence allows non-commercial use only.")
            .font(.callout)
            .foregroundStyle(.secondary)
        if let problem = installer.folderProblem {
            Text(problem).font(.callout).foregroundStyle(.red)
        }
        HStack {
            InstallerState(state: installer.modelState)
            if !installer.isBusy {
                Button("Download") {
                    guard DownloadConsent.confirm(engineID: "xtts") else { return }
                    installer.installModel()
                }
                .keyboardShortcut(.defaultAction)
                Menu("Other") {
                    Button("Download to Another Folder…") {
                        guard let folder = XTTSPanel.downloadDestination(),
                              DownloadConsent.confirm(engineID: "xtts") else { return }
                        installer.installModel(into: folder)
                    }
                    Button("Use a Model Already Downloaded…") {
                        guard let folder = XTTSPanel.existingModel() else { return }
                        installer.locateModel(folder)
                    }
                }
                .fixedSize()
            } else {
                Button("Cancel", action: installer.cancel)
            }
        }
    }
}

/// XTTS v2's part of the Settings window: its Python, its environment and
/// its model.
struct XTTSSettingsSection: View {
    let installer: XTTSInstaller
    @State private var showsLog = false
    @AppStorage(XTTSEngine.endingKey) private var ending = XTTSEngine.Ending.fade

    var body: some View {
        Section {
            LabeledContent("Python") {
                HStack {
                    if let python = installer.python {
                        Text("\(python.version), \(python.url.path)")
                            .textSelection(.enabled)
                            .truncationMode(.middle)
                            .lineLimit(1)
                    } else if installer.hasLooked {
                        Label("Python 3.11 not found", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Button("Choose…") {
                        guard let url = XTTSPanel.python() else { return }
                        Task { await installer.choosePython(url) }
                    }
                    .disabled(installer.isBusy)
                }
            }
            LabeledContent("Environment") {
                HStack {
                    Text(installer.environment.abbreviatedPath)
                        .textSelection(.enabled)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .help(installer.environment.path)
                    if installer.environmentIsReady {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }
            if installer.environmentStep != .idle || installer.hasLooked && installer.python == nil {
                VStack(alignment: .leading, spacing: 4) {
                    XTTSNeeds(installer: installer, inSettings: true)
                }
            }
            HStack {
                Button(installer.environmentIsReady && installer.usesDefaultEnvironment ? "Set Up Again" : "Set Up") {
                    installer.setUpEnvironment()
                }
                .disabled(installer.python == nil || installer.isBusy)
                .help("Install XTTS's libraries into \(XTTSEnvironment.defaultEnvironment.abbreviatedPath)")
                Button("Use Existing…") {
                    guard let folder = XTTSPanel.environment() else { return }
                    installer.useEnvironment(folder)
                }
                .disabled(installer.isBusy)
                Button("Use Default") { installer.useDefaultEnvironment() }
                    .disabled(installer.usesDefaultEnvironment || installer.isBusy)
                Spacer()
                if !installer.log.isEmpty {
                    Toggle("Show pip's Output", isOn: $showsLog).toggleStyle(.button)
                }
            }
            if showsLog {
                ScrollView {
                    Text(installer.log.suffix(60).joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 140)
            }
            LabeledContent("Model") {
                HStack {
                    Text(installer.modelDirectory.abbreviatedPath)
                        .textSelection(.enabled)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .help(installer.modelDirectory.path)
                    InstallerState(state: installer.modelState)
                    if installer.modelIsInstalled {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }
            HStack {
                Button("Download (1.9 GB)") {
                    guard DownloadConsent.confirm(engineID: "xtts") else { return }
                    installer.installModel()
                }
                .disabled(installer.modelIsInstalled || installer.isBusy)
                Button("Use Existing Model…") {
                    guard let folder = XTTSPanel.existingModel() else { return }
                    installer.locateModel(folder)
                }
                .disabled(installer.isBusy)
                Button("Use Default") { installer.useDefaultModel() }
                    .disabled(installer.usesDefaultModel || installer.isBusy)
                Spacer()
            }
            if let problem = installer.folderProblem {
                Text(problem).foregroundStyle(.red)
            }
            Picker("Sentence Endings", selection: $ending) {
                ForEach(XTTSEngine.Ending.allCases) { Text($0.title).tag($0) }
            }
            Text(endingNote)
                .font(.callout)
                .foregroundStyle(.secondary)
        } header: {
            ModelSectionHeader(title: "XTTS v2", engineID: "xtts")
        } footer: {
            Text("XTTS v2 runs in Python 3.11, which Dysnow finds on the Mac but does not bring. It speaks in its "
                + "own 58 voices and in yours, from My Voices.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .task { if !installer.hasLooked { await installer.lookForPython() } }
    }

    private var endingNote: String {
        switch ending {
        case .cut:
            "XTTS stops the last sound of what it is given within 20 ms, before the pause Dysnow makes."
        case .fade:
            "The last sound, when XTTS cuts it short, is drawn out and fades over a tenth of a second."
        case .word:
            "Each piece ends with a full stop, and XTTS says its last word again after it, which Dysnow "
                + "cuts off: the end is XTTS's own. Now and then the word is heard twice, when XTTS says more "
                + "after it. Each piece takes longer to make. Not in Chinese, where it is faded out."
        }
    }
}
