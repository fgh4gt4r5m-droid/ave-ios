/// Fournit le jeton d'accès au moment de chaque (re)connexion.
///
/// L'app n'embarque JAMAIS de clé B2B. Selon le mode de distribution :
/// - app grand public AVE : jeton de session lu du Keychain (`TokenStore`) ;
/// - app hôte (WoYo, TaGa…) : l'hôte appelle son propre backend, qui détient la clé B2B et obtient un
///   jeton court auprès d'AVE (`POST /v1/token`, voir contrat E8) ;
/// - dev : `nil` (serveur de dev sans authentification).
/// Renvoie `nil` si aucun jeton n'est requis ; lève si le jeton est requis mais introuvable.
public typealias AVETokenProvider = @Sendable () async throws -> String?
