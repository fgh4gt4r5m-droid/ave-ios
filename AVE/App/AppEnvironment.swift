import AVECore
import Foundation

/// Lit l'adresse du serveur dans l'Info.plist (alimentée par les .xcconfig, voir `Config/`).
/// Aucune clé ni jeton ici.
struct AppEnvironment {
    let endpoint: AVEEndpoint

    static func load(bundle: Bundle = .main) throws -> AppEnvironment {
        guard let raw = bundle.object(forInfoDictionaryKey: "AVEEndpoint") as? String,
              let url = URL(string: raw) else { throw AVEEndpointError.invalidURL }
        let allowLocal = (bundle.object(forInfoDictionaryKey: "AVEAllowInsecureLocal") as? String) == "YES"
        return AppEnvironment(endpoint: try AVEEndpoint(url, allowInsecureLocalNetwork: allowLocal))
    }
}
