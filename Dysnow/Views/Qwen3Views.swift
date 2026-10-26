import AppKit
import SwiftUI

/// The folder pickers for Qwen3-TTS's models.
@MainActor
enum Qwen3FolderPanel {
    static func downloadDestination() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder Qwen3-TTS's models are downloaded into and looked for in."
        panel.prompt = "Download Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = Qwen3Engine.defaultDirectory
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func existingModel() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose a Qwen3-TTS model's folder, such as \(Qwen3Variant.small.model.folderName), "
            + "or the folder holding it."
        panel.prompt = "Use This Model"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// A download's progress, with a button to stop it.
private struct DownloadState: View {
    let variant: Qwen3Variant
    let installer: Qwen3Installer

    var body: some View {
        InstallerState(state: installer.state(of: variant))
        if installer.isBusy(variant) {
            Button("Stop", systemImage: "xmark.circle") { installer.cancel(variant) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Stop the download; it goes on from here next time")
        }
    }
}

/// Offers to download the chosen size of Qwen3-TTS's model.
struct Qwen3Banner: View {
    let installer: Qwen3Installer

    var body: some View {
        let variant = installer.variant
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Qwen3-TTS's model is needed to speak").bold()
                Text("The \(variant.title) model is not in \(installer.directory.abbreviatedPath). It is downloaded "
                    + "once, about \(Self.size(variant)).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let problem = installer.folderProblem {
                    Text(problem).font(.callout).foregroundStyle(.red)
                }
            }
            Spacer()
            DownloadState(variant: variant, installer: installer)
            if !installer.isBusy(variant) {
                Button("Download") {
                    guard DownloadConsent.confirm(engineID: "qwen3") else { return }
                    installer.install(variant)
                }
                .keyboardShortcut(.defaultAction)
                Menu("Other") {
                    ForEach(Qwen3Variant.all.filter { $0 != variant }) { other in
                        Button("Use the \(other.title) model (\(Self.size(other)))") { installer.choose(other) }
                    }
                    Divider()
                    Button("Download to Another Folder…") {
                        guard let folder = Qwen3FolderPanel.downloadDestination() else { return }
                        guard DownloadConsent.confirm(engineID: "qwen3") else { return }
                        installer.install(variant, into: folder)
                    }
                    Button("Use a Model Already Downloaded…") {
                        guard let folder = Qwen3FolderPanel.existingModel() else { return }
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

    static func size(_ variant: Qwen3Variant) -> String {
        Measurement(value: Double(variant.model.megabytes) / 1024, unit: UnitInformationStorage.gigabytes)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(1))))
    }
}

/// Qwen3-TTS's part of the Settings window: the folder, and the model sizes.
struct Qwen3SettingsSection: View {
    let installer: Qwen3Installer

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
                Button("Use Existing Model…") {
                    guard let folder = Qwen3FolderPanel.existingModel() else { return }
                    installer.locate(folder)
                }
                Button("Change Folder…") {
                    guard let folder = Qwen3FolderPanel.downloadDestination() else { return }
                    installer.useFolder(folder)
                }
                Button("Use Default") { installer.useDefaultLocation() }
                    .disabled(installer.isDefaultLocation)
                    .help("Use \(Qwen3Engine.defaultDirectory.abbreviatedPath)")
                Spacer()
            }
            Picker("Model", selection: Binding(get: { installer.variant }, set: installer.choose)) {
                ForEach(Qwen3Variant.all) { variant in
                    Text(variant.title).tag(variant)
                }
            }
            .pickerStyle(.radioGroup)
            ForEach(Qwen3Variant.all) { variant in
                LabeledContent {
                    HStack {
                        DownloadState(variant: variant, installer: installer)
                        if installer.isInstalled(variant) {
                            Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Button("Delete", systemImage: "trash") { installer.remove(variant) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Delete this model from the disk")
                        } else if !installer.isBusy(variant) {
                            Button("Download (\(Qwen3Banner.size(variant)))") {
                                guard DownloadConsent.confirm(engineID: "qwen3") else { return }
                                installer.install(variant)
                            }
                        }
                    }
                } label: {
                    Text(variant.model.folderName)
                }
            }
            Text("Runs on the Mac's GPU. Moods in tts:mood tags are given to it as instructions.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } header: {
            ModelSectionHeader(title: "Qwen3-TTS models", engineID: "qwen3")
        }
    }
}
