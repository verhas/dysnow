import AVFoundation
import Lame
import UniformTypeIdentifiers

/// The kinds of sound file speech can be saved as.
enum ExportFormat: String, CaseIterable, Sendable {
    case m4a, mp3, wav, aiff, flac

    var title: String {
        switch self {
        case .m4a: "M4A (AAC, compressed)"
        case .mp3: "MP3 (compressed)"
        case .wav: "WAV (uncompressed)"
        case .aiff: "AIFF (uncompressed)"
        case .flac: "FLAC (lossless)"
        }
    }

    var fileExtension: String { rawValue }

    var contentType: UTType {
        switch self {
        case .m4a: .mpeg4Audio
        case .mp3: .mp3
        case .wav: .wav
        case .aiff: .aiff
        case .flac: UTType(filenameExtension: "flac") ?? .audio
        }
    }

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "m4a", "mp4", "aac": self = .m4a
        case "mp3": self = .mp3
        case "wav", "wave": self = .wav
        case "aif", "aiff": self = .aiff
        case "flac": self = .flac
        default: return nil
        }
    }

    /// Mono, at the speech's own sample rate. Not for MP3, which Core Audio
    /// does not write: LAME does.
    func settings(sampleRate: Int) -> [String: Any] {
        let common: [String: Any] = [AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1]
        let own: [String: Any] = switch self {
        case .m4a, .mp3:
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
        if format == .mp3 {
            return try MP3Encoder.write(audio, to: url)
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

/// Writes MP3 files with LAME: mono, 64 kbit/s, which is plenty for speech.
private enum MP3Encoder {
    static func write(_ audio: SynthesizedAudio, to url: URL) throws {
        guard let lame = lame_init() else { throw SpeechError.failed("The MP3 encoder could not be started.") }
        defer { lame_close(lame) }
        lame_set_in_samplerate(lame, Int32(audio.sampleRate))
        lame_set_num_channels(lame, 1)
        lame_set_mode(lame, MONO)
        lame_set_brate(lame, 64)
        lame_set_quality(lame, 2)
        guard lame_init_params(lame) >= 0 else {
            throw SpeechError.failed("MP3 cannot be made at \(audio.sampleRate) Hz.")
        }
        var mp3 = Data()
        let chunk = 8192
        // As LAME's documentation asks: 1.25 times the samples, and 7200.
        var buffer = [UInt8](repeating: 0, count: chunk * 5 / 4 + 7200)
        var start = 0
        repeat {
            let count = min(chunk, audio.samples.count - start)
            let written = audio.samples[start..<(start + count)].withUnsafeBufferPointer { samples in
                lame_encode_buffer_ieee_float(lame, samples.baseAddress, nil, Int32(count), &buffer, Int32(buffer.count))
            }
            guard written >= 0 else { throw SpeechError.failed("The speech could not be made into MP3.") }
            mp3.append(buffer, count: Int(written))
            start += count
        } while start < audio.samples.count
        let rest = lame_encode_flush(lame, &buffer, Int32(buffer.count))
        if rest > 0 { mp3.append(buffer, count: Int(rest)) }
        try mp3.write(to: url, options: .atomic)
    }
}
