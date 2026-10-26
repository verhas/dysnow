import AppKit

/// Asked before a model is downloaded: the user, not Dysnow, is to follow
/// its licence.
@MainActor
enum DownloadConsent {
    /// Whether to download `name`, whose licence is `licence`; `source` is
    /// where the licence can be read. Shown before every download.
    static func confirm(_ name: String, licence: String, source: URL?) -> Bool {
        let alert = alert(name, licence: licence, source: source)
        let answer = alert.runModal()
        if answer == .alertThirdButtonReturn, let source {
            NSWorkspace.shared.open(source)
            return false
        }
        return answer == .alertFirstButtonReturn
    }

    static func alert(_ name: String, licence: String, source: URL?) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Download \(name)?"
        alert.informativeText = """
            You are responsible for following its licence while you use it with Dysnow: for the \
            speech you make with it, and for what you do with that speech.

            Its licence, as far as Dysnow knows: \(licence)

            This is for information only: it is not authoritative and not legally binding. Dysnow \
            does not, by itself, grant you any right to the model or its voices. Check the licence at \
            its source before you use the model.
            """
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")
        if source != nil { alert.addButton(withTitle: "Read the Licence…") }
        return alert
    }

    /// For one of the models in `ModelInfo`: Kokoro, Qwen3-TTS, ZipVoice,
    /// Pocket TTS.
    static func confirm(engineID: String) -> Bool {
        let info = ModelInfo.of(engineID)
        return confirm(info?.name ?? "the model", licence: info?.licence.joined(separator: " ") ?? "Not known.",
                       source: info?.source)
    }

    static func confirm(_ model: PiperModel) -> Bool {
        let names = model.voices.map(\.name).joined(separator: ", ")
        let voices = model.voices.count == 1 ? "voice" : "voices"
        return confirm("Piper's \(model.language.name) \(voices) \(names)", licence: model.licence,
                       source: model.source)
    }
}
