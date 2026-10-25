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
            + (PiperVoice.all.first?.package.folderName ?? "") + ", or one of them."
        panel.prompt = "Use These Voices"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Offers to download the chosen Piper voice, which is downloaded on its own.
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
                    + "about \(voice.package.megabytes) MB.")
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
                Button("Download") { Task { await installer.install(voice) } }
                    .keyboardShortcut(.defaultAction)
                Menu("Other") {
                    Button("Download to Another Folder…") {
                        guard let folder = PiperFolderPanel.downloadDestination() else { return }
                        Task { await installer.install(voice, into: folder) }
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

/// Piper's part of the Settings window: the voices folder, and each voice.
struct PiperSettingsSection: View {
    let installer: PiperInstaller

    var body: some View {
        Section("Piper voices") {
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
            ForEach(PiperVoice.all, id: \.id) { voice in
                VoiceRow(voice: voice, installer: installer)
            }
        }
    }
}

private struct VoiceRow: View {
    let voice: PiperVoice
    let installer: PiperInstaller

    var body: some View {
        LabeledContent {
            HStack {
                InstallerState(state: installer.state(of: voice))
                if installer.isInstalled(voice) {
                    Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Show in Finder", systemImage: "magnifyingglass") {
                        NSWorkspace.shared.activateFileViewerSelecting([PiperEngine.folder(of: voice)])
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    Button("Delete", systemImage: "trash") { installer.remove(voice) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Delete \(voice.name)'s voice from the disk")
                } else if !installer.isBusy(voice) {
                    Button("Download (\(voice.package.megabytes) MB)") { Task { await installer.install(voice) } }
                }
            }
        } label: {
            Text("\(voice.name)")
            Text("\(voice.language.name), \(voice.gender.title.lowercased())")
        }
    }
}
