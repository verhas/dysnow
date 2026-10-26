import AppKit
import SwiftUI

/// The folder pickers for ZipVoice's and Pocket TTS's models.
@MainActor
enum CloningFolderPanel {
    static func downloadDestination(_ model: CloningModel) -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder to download \(model.name)'s model into (about \(model.megabytes) MB; "
            + "it goes into a \(model.package.folderName) folder there)."
        panel.prompt = "Download Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = model.defaultDirectory.deletingLastPathComponent()
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func existingModel(_ model: CloningModel) -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose the \(model.package.folderName) folder, or the folder that holds it."
        panel.prompt = "Use This Model"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Offers to get ZipVoice's or Pocket TTS's model.
struct CloningBanner: View {
    let installer: CloningInstaller

    var body: some View {
        let model = installer.model
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.name)'s model is needed to speak").bold()
                Text("It is not in \(installer.directory.abbreviatedPath). It is downloaded once, "
                    + "about \(model.megabytes) MB. " + (model.note ?? ""))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            InstallerState(state: installer.state)
            if !installer.isBusy {
                Button(installer.isDefaultLocation ? "Download" : "Download There") {
                    let parent = installer.directory.deletingLastPathComponent()
                    guard DownloadConsent.confirm(engineID: installer.model.rawValue) else { return }
                    Task { await installer.install(into: parent) }
                }
                .keyboardShortcut(.defaultAction)
                Menu("Other") {
                    Button("Download to Another Folder…") {
                        guard let folder = CloningFolderPanel.downloadDestination(model) else { return }
                        guard DownloadConsent.confirm(engineID: installer.model.rawValue) else { return }
                        Task { await installer.install(into: folder) }
                    }
                    Button("Use a Model Already Downloaded…") {
                        guard let folder = CloningFolderPanel.existingModel(model) else { return }
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

/// Says that a model speaking in the user's voices has none of them yet.
struct NoOwnVoiceBanner: View {
    let engine: CloningEngine
    let gender: SpeechGender
    let addVoice: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.badge.plus")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(engine.name) speaks in your own voices").bold()
                Text("There is no \(gender.title.lowercased()) one yet. A voice is made of a recording "
                    + "of ten seconds or so: of you, or of someone who lets you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Add a Voice…", action: addVoice)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.blue.opacity(0.08))
    }
}

/// ZipVoice's or Pocket TTS's part of the Settings window.
struct CloningSettingsSection: View {
    let installer: CloningInstaller

    var body: some View {
        let model = installer.model
        Section {
            LabeledContent("Location") {
                Text(installer.directory.abbreviatedPath)
                    .textSelection(.enabled)
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .help(installer.directory.path)
            }
            LabeledContent("Status") {
                HStack {
                    InstallerState(state: installer.state)
                    if installer.isInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if !installer.isBusy {
                        Button("Download (\(model.megabytes) MB)") {
                            let parent = installer.directory.deletingLastPathComponent()
                            guard DownloadConsent.confirm(engineID: installer.model.rawValue) else { return }
                            Task { await installer.install(into: parent) }
                        }
                    }
                }
            }
            if let note = model.note {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Use Existing Model…") {
                    guard let folder = CloningFolderPanel.existingModel(model) else { return }
                    installer.locate(folder)
                }
                Button("Download To…") {
                    guard let folder = CloningFolderPanel.downloadDestination(model) else { return }
                    guard DownloadConsent.confirm(engineID: installer.model.rawValue) else { return }
                    Task { await installer.install(into: folder) }
                }
                Button("Use Default") { installer.useDefaultLocation() }
                    .disabled(installer.isDefaultLocation)
                    .help("Use \(model.defaultDirectory.abbreviatedPath)")
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([installer.directory])
                }
                .disabled(!installer.isInstalled)
            }
            .disabled(installer.isBusy)
        } header: {
            ModelSectionHeader(title: "\(model.name) model", engineID: model.rawValue)
        }
    }
}
