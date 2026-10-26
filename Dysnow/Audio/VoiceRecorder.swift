import AVFoundation
import Observation

/// Records from the microphone, for a voice of the user's own.
@MainActor @Observable
final class VoiceRecorder {
    private(set) var isRecording = false
    /// How loud it is now, from 0 to 1, for a meter.
    private(set) var level: Float = 0
    private(set) var duration: TimeInterval = 0

    private let engine = AVAudioEngine()
    private let collector = Collector()
    private var meter: Task<Void, Never>?

    /// Asks for the microphone the first time.
    func start() async throws {
        guard !isRecording else { return }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw SpeechError.failed("Dysnow may not use the microphone. It can be allowed in System Settings, "
                + "Privacy & Security, Microphone.")
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechError.failed("There is no microphone to record with.")
        }
        collector.reset(sampleRate: format.sampleRate)
        let collector = collector
        // Called on the audio thread, not the main one.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, _ in
            collector.append(buffer)
        }
        try engine.start()
        isRecording = true
        duration = 0
        meter = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self else { return }
                let (level, duration) = collector.progress
                self.level = level
                self.duration = duration
            }
        }
    }

    /// The recording, as voices keep it: mono at 24 kHz, the silence at the
    /// ends cut off.
    func stop() throws -> SynthesizedAudio {
        meter?.cancel()
        meter = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        level = 0
        let recorded = collector.audio
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(recorded.sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(recorded.samples.count)),
              let channel = buffer.floatChannelData?[0], !recorded.samples.isEmpty else {
            throw SpeechError.failed("Nothing was recorded.")
        }
        buffer.frameLength = AVAudioFrameCount(recorded.samples.count)
        recorded.samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: recorded.samples.count) }
        return AudioImporter.trimmed(try AudioImporter.convert(buffer))
    }

    /// Gathers what the microphone hears, on the audio thread.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: [Float] = []
        private var sampleRate = 48_000.0
        private var lastLevel: Float = 0

        func reset(sampleRate: Double) {
            lock.withLock {
                samples = []
                self.sampleRate = sampleRate
                lastLevel = 0
            }
        }

        /// The channels mixed into one.
        func append(_ buffer: AVAudioPCMBuffer) {
            guard let channels = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength), channelCount = Int(buffer.format.channelCount)
            var mixed = [Float](repeating: 0, count: count)
            for channel in 0..<channelCount {
                for index in 0..<count { mixed[index] += channels[channel][index] / Float(channelCount) }
            }
            let peak = mixed.lazy.map(abs).max() ?? 0
            lock.withLock {
                samples += mixed
                lastLevel = peak
            }
        }

        var progress: (level: Float, duration: TimeInterval) {
            lock.withLock { (min(lastLevel * 2, 1), Double(samples.count) / sampleRate) }
        }

        var audio: SynthesizedAudio {
            lock.withLock { SynthesizedAudio(samples: samples, sampleRate: Int(sampleRate)) }
        }
    }
}
