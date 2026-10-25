import AppKit
import SwiftUI

/// The folder pickers for the model: where to download it, or where it is.
@MainActor
enum ModelFolderPanel {
    /// The folder the model is to be downloaded into: it gets a folder of its
    /// own inside.
    static func downloadDestination() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder to download Kokoro's voice model into "
            + "(about \(KokoroEngine.downloadMegabytes) MB; it goes into a \(KokoroEngine.modelName) folder there)."
        panel.prompt = "Download Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = KokoroEngine.defaultDirectory.deletingLastPathComponent()
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// The folder a model already is in: its own, or the one holding it.
    static func existingModel() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose the \(KokoroEngine.modelName) folder, or the folder that holds it."
        panel.prompt = "Use This Model"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = true
        // Hidden folders such as ~/.dysnow are where models are usually kept.
        panel.showsHiddenFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private extension URL {
    /// "~/.dysnow/voices/…", for showing.
    var abbreviatedPath: String { (path as NSString).abbreviatingWithTildeInPath }
}

/// Download progress, a failure, or nothing.
private struct InstallerState: View {
    let installer: KokoroInstaller

    var body: some View {
        switch installer.state {
        case .idle:
            EmptyView()
        case .downloading(let fraction):
            ProgressView(value: fraction).frame(width: 140)
            Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .unpacking:
            ProgressView().controlSize(.small)
            Text("Unpacking…").foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(.red).lineLimit(3)
        }
    }
}

/// Offers to get Kokoro's model, which the app needs before it can speak:
/// downloaded to the suggested place or another, or found where it already is.
struct ModelBanner: View {
    let installer: KokoroInstaller

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kokoro's voice model is needed to speak").bold()
                Text("It is not in \(installer.directory.abbreviatedPath). It is downloaded once, "
                    + "about \(KokoroEngine.downloadMegabytes) MB.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            InstallerState(installer: installer)
            if !installer.isBusy {
                Button(installer.isDefaultLocation ? "Download" : "Download There") {
                    let parent = installer.directory.deletingLastPathComponent()
                    Task { await installer.install(into: parent) }
                }
                .keyboardShortcut(.defaultAction)
                Menu("Other") {
                    Button("Download to Another Folder…") {
                        guard let folder = ModelFolderPanel.downloadDestination() else { return }
                        Task { await installer.install(into: folder) }
                    }
                    Button("Use a Model Already Downloaded…") {
                        guard let folder = ModelFolderPanel.existingModel() else { return }
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

/// The Settings window: for now, where Kokoro's model is.
struct SettingsView: View {
    private let installer = KokoroInstaller.shared

    var body: some View {
        Form {
            Section("Kokoro voice model") {
                LabeledContent("Location") {
                    Text(installer.directory.abbreviatedPath)
                        .textSelection(.enabled)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .help(installer.directory.path)
                }
                LabeledContent("Status") {
                    if installer.isInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Not found", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                if installer.state != .idle {
                    HStack {
                        InstallerState(installer: installer)
                    }
                }
                HStack {
                    Button("Use Existing Model…") {
                        guard let folder = ModelFolderPanel.existingModel() else { return }
                        installer.locate(folder)
                    }
                    Button("Download To…") {
                        guard let folder = ModelFolderPanel.downloadDestination() else { return }
                        Task { await installer.install(into: folder) }
                    }
                    Button("Use Default") { installer.useDefaultLocation() }
                        .disabled(installer.isDefaultLocation)
                        .help("Use \(KokoroEngine.defaultDirectory.abbreviatedPath)")
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([installer.directory])
                    }
                    .disabled(!installer.isInstalled)
                }
                .disabled(installer.isBusy)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: installer.refresh)
    }
}
