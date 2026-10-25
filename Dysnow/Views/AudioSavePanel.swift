import AppKit

/// The save dialog for speech, with the file format to choose below it.
@MainActor
enum AudioSavePanel {
    /// The file to save to and its format; nil when cancelled.
    static func run(name: String, format: ExportFormat) -> (URL, ExportFormat)? {
        let panel = NSSavePanel()
        let chooser = FormatChooser(panel: panel, format: format)
        panel.accessoryView = chooser.view
        panel.allowedContentTypes = [format.contentType]
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = name + "." + format.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return (url, chooser.format)
    }
}

/// A "Format:" pop-up: choosing one sets the file name's extension to match.
@MainActor
private final class FormatChooser: NSObject {
    private weak var panel: NSSavePanel?
    private(set) var format: ExportFormat
    let view: NSView

    init(panel: NSSavePanel, format: ExportFormat) {
        self.panel = panel
        self.format = format
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.addItems(withTitles: ExportFormat.allCases.map(\.title))
        popUp.selectItem(at: ExportFormat.allCases.firstIndex(of: format) ?? 0)
        let stack = NSStackView(views: [NSTextField(labelWithString: "Format:"), popUp])
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        view = stack
        super.init()
        popUp.target = self
        popUp.action = #selector(choose(_:))
    }

    @objc private func choose(_ popUp: NSPopUpButton) {
        format = ExportFormat.allCases[popUp.indexOfSelectedItem]
        guard let panel else { return }
        let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = base + "." + format.fileExtension
    }
}
