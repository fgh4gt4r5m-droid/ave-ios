import AVECore
import Foundation

/// Lit la configuration dans l'Info.plist (alimentée par les .xcconfig, voir `Config/`). Aucune clé ni jeton ici.
struct AppEnvironment {
    let endpoint: AVEEndpoint
    /// Identification envoyée dans `hello.client` (usage par application dans la console).
    let clientInfo: ClientInfo
    /// Service de comptes (https). `nil` seulement en développement : l'app utilise alors le faux service DEBUG.
    let accountsURL: URL?
    let allowInsecureLocal: Bool
    /// Indicatif sans « + » proposé pour les numéros saisis sans indicatif (ex. « 224 »). Optionnel.
    let defaultCountryCode: String?
    /// Vrai tant que le moteur ne fait qu'un écho avec une voix de test : l'app l'annonce (honnêteté), voir `AVE_DEMO_ENGINE`.
    let demoEngine: Bool
    /// Build TestFlight « démo interface » : faux service de comptes (`AVE_DEMO_ACCOUNTS`), annoncé à l'écran.
    let demoAccounts: Bool

    static func load(bundle: Bundle = .main) throws -> AppEnvironment {
        guard let raw = bundle.object(forInfoDictionaryKey: "AVEEndpoint") as? String,
              let url = URL(string: raw) else { throw AVEEndpointError.invalidURL }
        let allowLocal = (bundle.object(forInfoDictionaryKey: "AVEAllowInsecureLocal") as? String) == "YES"
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let accounts = (bundle.object(forInfoDictionaryKey: "AVEAccountsURL") as? String).flatMap(URL.init(string:))
        let country = (bundle.object(forInfoDictionaryKey: "AVEDefaultCountryCode") as? String).flatMap { $0.isEmpty ? nil : $0 }
        // Absent = vrai : mieux vaut un avertissement de trop qu'une app qui laisse croire à un vrai dialogue.
        let demo = (bundle.object(forInfoDictionaryKey: "AVEDemoEngine") as? String) != "NO"
        // Absent = faux : le faux service de comptes n'est jamais choisi par défaut.
        let demoAccounts = (bundle.object(forInfoDictionaryKey: "AVEDemoAccounts") as? String) == "YES"
        return AppEnvironment(
            endpoint: try AVEEndpoint(url, allowInsecureLocalNetwork: allowLocal),
            clientInfo: ClientInfo(app: "ave-ios", version: version, sdk: "avekit"),
            accountsURL: accounts, allowInsecureLocal: allowLocal, defaultCountryCode: country, demoEngine: demo,
            demoAccounts: demoAccounts)
    }
}
