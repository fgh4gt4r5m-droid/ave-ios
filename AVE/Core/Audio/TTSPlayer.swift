#if os(iOS)
import AVECore
import AVFoundation

/// Lecture du TTS : `AVAudioPlayerNode` sur le moteur partagé, file d'amorçage (~100 ms) et purge instantanée.
public final class TTSPlayer: SpeechPlayer, @unchecked Sendable {
    /// Niveau de lecture 0…1 par chunk programmé (approximation : devance la lecture réelle d'environ la durée d'amorçage).
    public let levels: AsyncStream<Float>
    private let levelsOut: AsyncStream<Float>.Continuation

    private let voice: VoiceEngine
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat?
    private let lock = NSLock()
    private var primer: PlaybackPrimer
    private var generation = 0
    private var pending = 0

    public init(engine: VoiceEngine, sampleRate: Int = AVEAudio.sampleRate) {
        self.voice = engine
        self.primer = PlaybackPrimer(sampleRate: sampleRate)
        self.format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate),
                                    channels: 1, interleaved: false)
        let (stream, continuation) = AsyncStream<Float>.makeStream(bufferingPolicy: .bufferingNewest(8))
        self.levels = stream
        self.levelsOut = continuation
        engine.engine.attach(node)
        engine.engine.connect(node, to: engine.engine.mainMixerNode, format: format)
    }

    /// Plus rien à jouer ni en attente (utile pour l'état « parole » de l'orbe, qui dure plus longtemps que `tts_end`).
    public var isDrained: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pending == 0
    }

    public func enqueue(_ pcm: Data) {
        lock.lock()
        let ready = primer.push(pcm)
        lock.unlock()
        schedule(ready)
    }

    /// Fin d'énoncé (`tts_end` naturel) : libère ce qui attendait encore l'amorçage.
    public func endOfUtterance() {
        lock.lock()
        let rest = primer.finish()
        lock.unlock()
        schedule(rest)
    }

    /// Barge-in : coupe la lecture immédiatement et jette tout ce qui était programmé.
    public func purge() {
        lock.lock()
        primer.purge()
        generation += 1
        pending = 0
        lock.unlock()
        node.stop()  // supprime les buffers programmés
    }

    private func schedule(_ chunks: [Data]) {
        guard let format, !chunks.isEmpty else { return }
        for chunk in chunks {
            let samples = PCM16.samples(from: chunk)
            guard !samples.isEmpty,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData else { continue }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            for (i, s) in samples.enumerated() { channel[0][i] = Float(s) / 32768 }

            lock.lock()
            let gen = generation
            pending += 1
            lock.unlock()

            node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                if self.generation == gen, self.pending > 0 { self.pending -= 1 }
                self.lock.unlock()
            }
            levelsOut.yield(AudioLevel.normalized(rms: AudioLevel.rms(samples)))
        }
        if voice.isRunning, !node.isPlaying { node.play() }
    }
}
#endif
