import Foundation
import Speech

/// Writes down what is said in a recording, on the Mac itself: the words a
/// voice's recording holds, which ZipVoice needs.
@MainActor
enum Transcriber {
    static func transcribe(_ audio: SynthesizedAudio, languageID: String) async throws -> String {
        guard await authorized() else {
            throw SpeechError.failed("Dysnow may not use speech recognition. It can be allowed in System Settings, "
                + "Privacy & Security, Speech Recognition.")
        }
        let locale = Locale(identifier: languageID == "zh" ? "zh-CN" : languageID)
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            throw SpeechError.failed("Speech recognition is not available for this language.")
        }
        let file = FileManager.default.temporaryDirectory.appending(path: "dysnow-transcribe-\(UUID().uuidString).wav")
        try AudioExporter.write(audio, to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let request = SFSpeechURLRecognitionRequest(url: file)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            // Called on a queue of its own, not the main one.
            recognizer.recognitionTask(with: request) { @Sendable result, error in
                if let error {
                    once.run { continuation.resume(throwing: error) }
                } else if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    once.run { continuation.resume(returning: text) }
                }
            }
        }
    }

    private static func authorized() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { @Sendable status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default: return false
        }
    }

    /// Resumes a continuation only once, whatever the recogniser reports.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func run(_ body: () -> Void) {
            let first = lock.withLock {
                defer { done = true }
                return !done
            }
            if first { body() }
        }
    }
}
