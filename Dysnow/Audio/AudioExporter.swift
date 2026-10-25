import AVFoundation
import UniformTypeIdentifiers

/// The kinds of sound file speech can be saved as.
enum ExportFormat: String, CaseIterable, Sendable {
    case m4a, wav, aiff, flac

    var title: String {
        switch self {
        case .m4a: "M4A (AAC, compressed)"
        case .wav: "WAV (uncompressed)"
        case .aiff: "AIFF (uncompressed)"
        case .flac: "FLAC (lossless)"
        }
    }

    var fileExtension: String { rawValue }

    var contentType: UTType {
        switch self {
        case .m4a: .mpeg4Audio
        case .wav: .wav
        case .aiff: .aiff
        case .flac: UTType(filenameExtension: "flac") ?? .audio
        }
    }

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "m4a", "mp4", "aac": self = .m4a
        case "wav", "wave": self = .wav
        case "aif", "aiff": self = .aiff
        case "flac": self = .flac
        default: return nil
        }
    }

    /// Mono, at the speech's own sample rate.
    func settings(sampleRate: Int) -> [String: Any] {
        let common: [String: Any] = [AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1]
        let own: [String: Any] = switch self {
        case .m4a:
            [AVFormatIDKey: kAudioFormatMPEG4AAC, AVEncoderBitRateKey: 64_000]
        case .wav:
            [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
             AVLinearPCMIsBigEndianKey: false]
        case .aiff:
            [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
             AVLinearPCMIsBigEndianKey: true]
        case .flac:
            [AVFormatIDKey: kAudioFormatFLAC, AVEncoderBitDepthHintKey: 16]
        }
        return common.merging(own) { $1 }
    }
}

/// Writes speech to a sound file; the file's extension picks the format.
enum AudioExporter {
    static func write(_ audio: SynthesizedAudio, to url: URL) throws {
        guard let format = ExportFormat(fileExtension: url.pathExtension) else {
            throw SpeechError.failed("Speech can be saved as "
                + ExportFormat.allCases.map { "." + $0.fileExtension }.formatted(.list(type: .or))
                + ", not .\(url.pathExtension).")
        }
        guard let pcm = AVAudioFormat(standardFormatWithSampleRate: Double(audio.sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: AVAudioFrameCount(audio.samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            throw SpeechError.failed("The speech could not be prepared for saving.")
        }
        buffer.frameLength = AVAudioFrameCount(audio.samples.count)
        audio.samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: audio.samples.count) }

        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: format.settings(sampleRate: audio.sampleRate),
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
        file.close()
    }
}
