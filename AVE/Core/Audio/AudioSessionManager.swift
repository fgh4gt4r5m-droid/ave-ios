#if os(iOS)
import AVFoundation

/// Configure `AVAudioSession` pour la conversation vocale et traduit les notifications système
/// en un flux d'événements simples pour le coordinateur de session.
public final class AudioSessionManager: AudioLifecycle, @unchecked Sendable {
    public let events: AsyncStream<AudioSessionEvent>
    private let continuation: AsyncStream<AudioSessionEvent>.Continuation
    private let lock = NSLock()
    private var observers: [NSObjectProtocol] = []

    public init() {
        let (stream, continuation) = AsyncStream<AudioSessionEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.continuation = continuation
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        continuation.finish()
    }

    public func requestMicrophonePermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// `.playAndRecord` + `.voiceChat` : annulation d'écho, gain automatique, routage voix.
    public func activate() throws {
        let session = AVAudioSession.sharedInstance()
        // `.allowBluetooth` (profil mains libres) est renommé `.allowBluetoothHFP` dans le SDK iOS 26 ;
        // l'ancien nom reste valide en iOS 17.
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setPreferredSampleRate(Double(AVEAudio.sampleRate))
        try session.setPreferredIOBufferDuration(Double(AVEAudio.frameMilliseconds) / 1000)
        try session.setActive(true)
        startObserving()
    }

    public func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    public var currentRoute: AudioRoute {
        Self.route(from: AVAudioSession.sharedInstance().currentRoute)
    }

    private func startObserving() {
        lock.lock()
        defer { lock.unlock() }
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let continuation = self.continuation

        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                continuation.yield(.interruptionBegan)
            case .ended:
                let opts = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let resume = AVAudioSession.InterruptionOptions(rawValue: opts).contains(.shouldResume)
                continuation.yield(.interruptionEnded(shouldResume: resume))
            @unknown default:
                break
            }
        })

        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let reason: AudioRouteChangeReason
            switch AVAudioSession.RouteChangeReason(rawValue: raw) {
            case .newDeviceAvailable: reason = .newDeviceAvailable
            case .oldDeviceUnavailable: reason = .oldDeviceUnavailable
            case .categoryChange: reason = .categoryChange
            case .override: reason = .override
            default: reason = .other
            }
            continuation.yield(.routeChanged(Self.route(from: AVAudioSession.sharedInstance().currentRoute), reason: reason))
        })

        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { _ in
            continuation.yield(.mediaServicesReset)
        })
    }

    private static func route(from route: AVAudioSessionRouteDescription) -> AudioRoute {
        switch route.outputs.first?.portType {
        case .builtInSpeaker: return .builtInSpeaker
        case .builtInReceiver: return .receiver
        case .headphones, .usbAudio: return .headphones
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE: return .bluetooth
        default: return .other
        }
    }
}
#endif
