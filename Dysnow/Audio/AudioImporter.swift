import AVFoundation

/// Reads sound files into speech samples: a recording a voice is made from.
enum AudioImporter {
    /// The rate the voice samples are kept at: what ZipVoice and Pocket TTS
    /// make speech at.
    static let sampleRate = 24_000

    /// Any file Core Audio reads -- WAV, AIFF, M4A, MP3, FLAC -- as mono at
    /// `sampleRate`.
    static func read(_ url: URL) throws -> SynthesizedAudio {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw SpeechError.failed("\(url.lastPathComponent) could not be read.")
        }
        try file.read(into: input)
        return try convert(input)
    }

    /// Speech at another rate: Piper's 22 050 Hz joined to Kokoro's 24 000.
    static func resampled(_ audio: SynthesizedAudio, to rate: Int) throws -> SynthesizedAudio {
        guard audio.sampleRate != rate, !audio.samples.isEmpty else {
            return SynthesizedAudio(samples: audio.samples, sampleRate: rate)
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(audio.sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            throw SpeechError.failed("The sound could not be converted.")
        }
        buffer.frameLength = AVAudioFrameCount(audio.samples.count)
        audio.samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: audio.samples.count) }
        return try convert(buffer, to: rate)
    }

    /// Recorded or read samples, in any format, as mono at `rate`.
    static func convert(_ input: AVAudioPCMBuffer, to rate: Int = sampleRate) throws -> SynthesizedAudio {
        let sampleRate = rate
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate),
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input.format, to: target) else {
            throw SpeechError.failed("The sound could not be converted.")
        }
        // Several channels are mixed down, not just the first taken.
        if input.format.channelCount > 1 {
            converter.downmix = true
        }
        let ratio = Double(sampleRate) / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw SpeechError.failed("The sound could not be converted.")
        }
        var given = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if given {
                inputStatus.pointee = .endOfStream
                return nil
            }
            given = true
            inputStatus.pointee = .haveData
            return input
        }
        if status == .error { throw error ?? SpeechError.failed("The sound could not be converted.") }
        guard let channel = output.floatChannelData?[0] else { return SynthesizedAudio(samples: [], sampleRate: sampleRate) }
        return SynthesizedAudio(samples: Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength))),
                                sampleRate: sampleRate)
    }

    /// Without the silence at the start and the end, and no longer than
    /// `maximum` seconds: a long sample only slows the cloning down.
    static func trimmed(_ audio: SynthesizedAudio, maximum: TimeInterval = 15) -> SynthesizedAudio {
        let peak = audio.samples.lazy.map(abs).max() ?? 0
        guard peak > 0 else { return audio }
        let threshold = peak * 0.02
        let margin = audio.sampleRate / 10
        guard let first = audio.samples.firstIndex(where: { abs($0) > threshold }),
              let last = audio.samples.lastIndex(where: { abs($0) > threshold }) else { return audio }
        let start = max(first - margin, 0)
        let end = min(last + margin + 1, audio.samples.count, start + Int(maximum * Double(audio.sampleRate)))
        return SynthesizedAudio(samples: Array(audio.samples[start..<end]), sampleRate: audio.sampleRate)
    }
}
