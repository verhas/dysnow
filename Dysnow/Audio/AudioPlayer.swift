import AVFoundation

/// Plays speech as it is made: each piece is queued behind the one before,
/// so playback runs on without a gap while the next is still being made.
@MainActor
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    /// Queued pieces not yet played.
    private var pending = 0
    /// Bumped by `stop`, so the completions of what it threw away are ignored.
    private var generation = 0
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init() {
        engine.attach(node)
    }

    /// Ready to play mono samples at this rate, with nothing queued.
    func start(sampleRate: Int) throws {
        stop()
        guard let wanted = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1) else {
            throw SpeechError.failed("Audio at \(sampleRate) Hz cannot be played.")
        }
        if format != wanted {
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: engine.mainMixerNode, format: wanted)
            format = wanted
        }
        if !engine.isRunning { try engine.start() }
        node.play()
    }

    func enqueue(_ samples: [Float]) {
        guard let format, !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        pending += 1
        let generation = generation
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.played(generation) }
        }
    }

    /// Returns once everything queued has been played, or playback stopped.
    func drain() async {
        guard pending > 0 else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }

    func pause() {
        node.pause()
    }

    func resume() {
        node.play()
    }

    func stop() {
        generation += 1
        node.stop()
        pending = 0
        resumeWaiters()
    }

    private func played(_ generation: Int) {
        guard generation == self.generation else { return }
        pending -= 1
        if pending == 0 { resumeWaiters() }
    }

    private func resumeWaiters() {
        let waiters = drainWaiters
        drainWaiters = []
        waiters.forEach { $0.resume() }
    }
}
