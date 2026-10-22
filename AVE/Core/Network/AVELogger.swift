import Foundation
#if canImport(os)
import os
#endif

/// Journal minimal. RÈGLE : ne jamais passer de jeton, de texte utilisateur (transcription,
/// réponse) ni d'URL complète. Uniquement des constantes, des codes et des compteurs.
public struct AVELogger: Sendable {
    public enum Level: Sendable { case debug, info, error }

    private let sink: @Sendable (Level, String) -> Void

    public init(_ sink: @escaping @Sendable (Level, String) -> Void) {
        self.sink = sink
    }

    public func debug(_ message: String) { sink(.debug, message) }
    public func info(_ message: String) { sink(.info, message) }
    public func error(_ message: String) { sink(.error, message) }

    public static let silent = AVELogger { _, _ in }

    #if canImport(os)
    public static let system: AVELogger = {
        let logger = Logger(subsystem: "fr.ave.app", category: "network")
        return AVELogger { level, message in
            switch level {
            case .debug: logger.debug("\(message, privacy: .public)")
            case .info: logger.info("\(message, privacy: .public)")
            case .error: logger.error("\(message, privacy: .public)")
            }
        }
    }()
    #endif
}
