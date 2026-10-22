import Foundation

/// Erreurs définitives : aucune reconnexion automatique.
public enum AVEFatalError: String, Sendable, Equatable {
    case unauthorized
    case tooManySessions = "too_many_sessions"
    case badVersion = "bad_version"
    case unsupportedCodec = "unsupported_codec"
    // Ajouts par rapport à la liste de la demande : erreurs de configuration client qui ne se
    // corrigent pas en réessayant (le serveur ferme en 1008 après chacune).
    case badLang = "bad_lang"
    case badSampleRate = "bad_sample_rate"

    public init?(code: String) { self.init(rawValue: code) }
}

public enum ConnectionState: Sendable, Equatable {
    case idle
    case connecting
    case reconnecting(attempt: Int)
    /// `ready` reçu. `resumed == false` : session neuve (l'historique serveur est perdu).
    case open(resumed: Bool)
    case failed(AVEFatalError)
    case closed
}

/// Flux typé vers l'UI, dans l'ordre de réception.
public enum ClientEvent: Sendable, Equatable {
    case state(ConnectionState)
    /// Chunk PCM16 mono du TTS (déjà dédoublonné), sans l'en-tête binaire.
    case audio(Data)
    case server(ServerEvent)
    /// Après reprise : `gap == true` signifie que le serveur a oublié des trames (réponse tronquée).
    case replayGap(count: Int, gap: Bool)
}
