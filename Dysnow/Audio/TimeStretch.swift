import AVFoundation

/// Makes speech faster or slower without changing its pitch, for engines
/// that cannot be asked for another speed.
enum TimeStretch {
    /// `rate` 2 is twice as fast: half as long.
    static func apply(_ audio: SynthesizedAudio, rate: Float) throws -> SynthesizedAudio {
        guard abs(rate - 1) > 0.01, !audio.samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: Double(audio.sampleRate), channels: 1),
              let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.samples.count)),
              let channel = input.floatChannelData?[0] else { return audio }
        input.frameLength = AVAudioFrameCount(audio.samples.count)
        audio.samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: audio.samples.count) }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let stretch = AVAudioUnitTimePitch()
        stretch.rate = min(max(rate, 1 / 32), 32)
        engine.attach(player)
        engine.attach(stretch)
        engine.connect(player, to: stretch, format: format)
        engine.connect(stretch, to: engine.mainMixerNode, format: format)
        let chunk: AVAudioFrameCount = 4096
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunk)
        try engine.start()
        defer { engine.stop() }
        player.scheduleBuffer(input)
        player.play()

        // The effect starts late by its latency: that much is rendered and
        // dropped first.
        let skip = Int(stretch.latency * Double(audio.sampleRate))
        let wanted = Int(Double(audio.samples.count) / Double(stretch.rate))
        guard let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: chunk) else {
            return audio
        }
        var samples: [Float] = []
        samples.reserveCapacity(skip + wanted)
        while samples.count < skip + wanted {
            let frames = AVAudioFrameCount(min(Int(chunk), skip + wanted - samples.count))
            guard try engine.renderOffline(frames, to: output) == .success,
                  let rendered = output.floatChannelData?[0] else { break }
            samples += UnsafeBufferPointer(start: rendered, count: Int(output.frameLength))
        }
        return SynthesizedAudio(samples: Array(samples.dropFirst(skip)), sampleRate: audio.sampleRate)
    }
}
