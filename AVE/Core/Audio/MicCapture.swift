#if os(iOS)
import AVECore
import AVFoundation

/// Capture micro via le tap de l'`AVAudioEngine`.
///
/// Le callback du tap ne fait que COPIER les échantillons et les poser dans un flux : pas de
/// conversion, pas de verrou, pas de log. Rééchantillonnage (AVAudioConverter), découpage en
/// trames de 20 ms et calcul de niveau se font dans une tâche séparée.
public final class MicCapture: MicSource, @unchecked Sendable {
    private struct RawChunk: Sendable {
        let samples: [Float]
        let sampleRate: Double
    }

    public let frames: AsyncStream<MicFrame>
    private let framesOut: AsyncStream<MicFrame>.Continuation
    private let voice: VoiceEngine
    private let lock = NSLock()
    private var consumer: Task<Void, Never>?
    private var isRunning = false

    public init(engine: VoiceEngine) {
        self.voice = engine
        let (stream, continuation) = AsyncStream<MicFrame>.makeStream(bufferingPolicy: .bufferingNewest(250))
        self.frames = stream
        self.framesOut = continuation
    }

    /// Le moteur doit être démarré par l'appelant (`VoiceEngine.start()`).
    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return }
        isRunning = true

        let (rawStream, rawOut) = AsyncStream<RawChunk>.makeStream(bufferingPolicy: .unbounded)
        let input = voice.engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            // Rien d'autre que la copie du premier canal.
            let n = Int(buffer.frameLength)
            let samples: [Float]
            if let ch = buffer.floatChannelData {
                samples = Array(UnsafeBufferPointer(start: ch[0], count: n))
            } else if let ch = buffer.int16ChannelData {
                samples = UnsafeBufferPointer(start: ch[0], count: n).map { Float($0) / 32768 }
            } else {
                return
            }
            rawOut.yield(RawChunk(samples: samples, sampleRate: buffer.format.sampleRate))
        }

        let out = framesOut
        consumer = Task.detached(priority: .userInitiated) {
            var converter = MicConverter()
            var framer = PCMFramer()
            for await chunk in rawStream {
                let pcm = converter.convert(chunk.samples, sampleRate: chunk.sampleRate)
                for samples in framer.append(pcm) {
                    out.yield(MicFrame(pcm: PCM16.data(from: samples), rms: AudioLevel.rms(samples)))
                }
            }
        }
        // Termine la tâche quand le tap est retiré.
        terminate = { rawOut.finish() }
    }

    private var terminate: (@Sendable () -> Void)?

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }
        isRunning = false
        voice.engine.inputNode.removeTap(onBus: 0)
        terminate?()
        terminate = nil
        consumer = nil
    }
}

/// Float32 (fréquence du micro) → Int16 16 kHz mono avec `AVAudioConverter`. Le convertisseur est
/// conservé entre les appels (état du rééchantillonneur) et recréé si la fréquence change
/// (changement de route, Bluetooth).
private struct MicConverter {
    private var converter: AVAudioConverter?
    private var sourceRate: Double = 0
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(AVEAudio.sampleRate),
                                       channels: 1, interleaved: true)

    mutating func convert(_ samples: [Float], sampleRate: Double) -> [Int16] {
        guard let target, !samples.isEmpty,
              let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: 1, interleaved: false) else { return [] }
        if converter == nil || sourceRate != sampleRate {
            converter = AVAudioConverter(from: source, to: target)
            sourceRate = sampleRate
        }
        guard let converter,
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = input.floatChannelData else { return [] }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel[0].update(from: $0.baseAddress ?? channel[0], count: samples.count) }

        let capacity = AVAudioFrameCount(Double(samples.count) * target.sampleRate / sampleRate) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
        var error: NSError?
        let feed = OneShotInput(input)
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard let buffer = feed.take() else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, let data = output.int16ChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}

/// Tampon d'entrée livré une seule fois au convertisseur. Le bloc d'entrée d'`AVAudioConverter` peut être déclaré
/// `@Sendable` par le SDK : il ne peut alors ni modifier une variable capturée ni capturer un `AVAudioPCMBuffer`.
/// `convert` l'appelle de façon SYNCHRONE, dans la tâche qui convertit : aucun accès concurrent réel, d'où le
/// `@unchecked Sendable`.
private final class OneShotInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
#endif
