#if os(iOS)
import AVFoundation

/// Session audio + moteur : `activate()` configure la session puis démarre le moteur ; un changement
/// de configuration du moteur (route, Bluetooth) le redémarre.
public final class SystemAudioLifecycle: AudioLifecycle, @unchecked Sendable {
    private let session: AudioSessionManager
    private let voice: VoiceEngine
    private let lock = NSLock()
    private var watcher: Task<Void, Never>?

    public var events: AsyncStream<AudioSessionEvent> { session.events }

    public init(session: AudioSessionManager, engine: VoiceEngine) {
        self.session = session
        self.voice = engine
    }

    public func requestMicrophonePermission() async -> Bool {
        await session.requestMicrophonePermission()
    }

    public func activate() throws {
        try session.activate()
        try voice.start()
        lock.lock()
        defer { lock.unlock() }
        guard watcher == nil else { return }
        let voice = self.voice
        watcher = Task.detached {
            for await _ in voice.configurationChanges { try? voice.start() }
        }
    }

    public func deactivate() {
        lock.lock()
        watcher?.cancel()
        watcher = nil
        lock.unlock()
        voice.stop()
        session.deactivate()
    }
}

extension AudioDevices {
    /// Matériel réel : un seul moteur pour micro et lecture (annulation d'écho).
    public static func system(echoCancellation: Bool = true) throws -> AudioDevices {
        let engine = try VoiceEngine(echoCancellation: echoCancellation)
        return AudioDevices(
            mic: MicCapture(engine: engine),
            player: TTSPlayer(engine: engine),
            lifecycle: SystemAudioLifecycle(session: AudioSessionManager(), engine: engine))
    }
}
#endif
