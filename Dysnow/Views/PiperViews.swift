import AppKit
import SwiftUI

/// The folder pickers for Piper's voices.
@MainActor
enum PiperFolderPanel {
    /// The folder voices are to be downloaded into, and looked for in.
    static func downloadDestination() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder Piper's voices are downloaded into and looked for in."
        panel.prompt = "Download Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = PiperEngine.defaultDirectory
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// A folder holding voices already downloaded, or one voice's own folder.
    static func existingVoices() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder holding Piper's voices, such as "
            + (PiperModel.withID("hu_HU-anna-medium")?.package.folderName ?? "") + ", or one of them."
        panel.prompt = "Use These Voices"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Offers to download the chosen Piper voice's model.
struct PiperVoiceBanner: View {
    let voice: PiperVoice
    let installer: PiperInstaller

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(voice.name)'s voice is needed to speak").bold()
                Text("It is not in \(installer.directory.abbreviatedPath). It is downloaded once, "
                    + "about \(voice.package.megabytes) MB. Its licence: \(voice.model.licence).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let problem = installer.folderProblem {
                    Text(problem).font(.callout).foregroundStyle(.red)
                }
            }
            Spacer()
            InstallerState(state: installer.state(of: voice))
            if !installer.isBusy(voice) {
                Button("Download") {
                    guard DownloadConsent.confirm(voice.model) else { return }
                    Task { await installer.install(voice.model) }
                }
                .keyboardShortcut(.defaultAction)
                Menu("Other") {
                    Button("Download to Another Folder…") {
                        guard let folder = PiperFolderPanel.downloadDestination(),
                              DownloadConsent.confirm(voice.model) else { return }
                        Task { await installer.install(voice.model, into: folder) }
                    }
                    Button("Use Voices Already Downloaded…") {
                        guard let folder = PiperFolderPanel.existingVoices() else { return }
                        installer.locate(folder)
                    }
                    if !installer.isDefaultLocation {
                        Divider()
                        Button("Use the Default Location") { installer.useDefaultLocation() }
                    }
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.yellow.opacity(0.12))
    }
}

/// Piper's part of the Settings window: the voices folder, and the models
/// of a language, to download.
struct PiperSettingsSection: View {
    let installer: PiperInstaller
    @AppStorage("piper.settingsLanguage") private var languageID = PiperModel.hungarian.id

    private var language: SpeechLanguage {
        PiperModel.languages.first { $0.id == languageID } ?? PiperModel.hungarian
    }

    var body: some View {
        Section {
            LabeledContent("Location") {
                Text(installer.directory.abbreviatedPath)
                    .textSelection(.enabled)
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .help(installer.directory.path)
            }
            if let problem = installer.folderProblem {
                Text(problem).foregroundStyle(.red)
            }
            HStack {
                Button("Use Existing Voices…") {
                    guard let folder = PiperFolderPanel.existingVoices() else { return }
                    installer.locate(folder)
                }
                Button("Change Folder…") {
                    guard let folder = PiperFolderPanel.downloadDestination() else { return }
                    installer.useFolder(folder)
                }
                Button("Use Default") { installer.useDefaultLocation() }
                    .disabled(installer.isDefaultLocation)
                    .help("Use \(PiperEngine.defaultDirectory.abbreviatedPath)")
                Spacer()
            }
            Picker("Language", selection: $languageID) {
                ForEach(PiperModel.languages) { language in
                    let count = installer.installedCount(of: language)
                    Text(count == 0 ? language.name : "\(language.name) (\(count) downloaded)").tag(language.id)
                }
            }
            ForEach(PiperModel.all.filter { $0.language == language }) { model in
                PiperModelRow(model: model, installer: installer)
            }
        } header: {
            ModelSectionHeader(title: "Piper voices", engineID: "piper")
        } footer: {
            Text("Each voice is a download of its own, with a licence of its own, as its model card says. "
                + "A language is offered in the main window once one of its voices is downloaded.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// One of Piper's models: its voices, its licence, and getting it.
private struct PiperModelRow: View {
    let model: PiperModel
    let installer: PiperInstaller

    var body: some View {
        LabeledContent {
            HStack {
                InstallerState(state: installer.state(of: model))
                if installer.isInstalled(model) {
                    Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Show in Finder", systemImage: "magnifyingglass") {
                        NSWorkspace.shared.activateFileViewerSelecting([PiperEngine.folder(of: model)])
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    Button("Delete", systemImage: "trash") { installer.remove(model) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Delete this voice from the disk")
                } else if !installer.isBusy(model) {
                    Button("Download (\(model.package.megabytes) MB)") {
                        guard DownloadConsent.confirm(model) else { return }
                        Task { await installer.install(model) }
                    }
                }
            }
        } label: {
            Text(model.voices.map { "\($0.name) (\($0.gender.title.lowercased()))" }.joined(separator: ", "))
            HStack(spacing: 4) {
                if !model.qualityTitle.isEmpty { Text(model.qualityTitle + " ·") }
                Text(model.licence)
                    .foregroundStyle(model.isNonCommercial ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                Link(model.source.lastPathComponent == "MODEL_CARD" ? "Model card" : "Source", destination: model.source)
            }
            .help(model.id)
        }
    }
}
