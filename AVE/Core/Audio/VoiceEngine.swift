#if os(iOS)
import AVFoundation

/// Un seul `AVAudioEngine` pour le micro ET la lecture : l'annulation d'écho (voice processing)
/// a besoin de voir ce que l'on joue pour le soustraire de ce que l'on capte.
public final class VoiceEngine: @unchecked Sendable {
    let engine = AVAudioEngine()
    public let echoCancellationEnabled: Bool
    private let lock = NSLock()
    private var configObserver: NSObjectProtocol?
    public let configurationChanges: AsyncStream<Void>
    private let configContinuation: AsyncStream<Void>.Continuation

    /// À créer AVANT d'attacher le lecteur : activer le voice processing après coup change les formats.
    public init(echoCancellation: Bool = true) throws {
        echoCancellationEnabled = echoCancellation
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        configurationChanges = stream
        configContinuation = continuation
        if echoCancellation {
            try engine.inputNode.setVoiceProcessingEnabled(true)
        }
        let cont = continuation
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { _ in cont.yield() }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configContinuation.finish()
    }

    public var isRunning: Bool { engine.isRunning }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        engine.stop()
    }
}
#endif
