import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client HTTPS du service de comptes. Routes PROPOSÉES (contrat §6) : aucun serveur ne les implémente encore.
public struct HTTPAccountsAPI: AccountsAPI {
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let baseURL: URL
    private let send: Send

    /// `https` uniquement (`http` toléré vers le réseau local avec `allowInsecureLocalNetwork`, développement seulement).
    public init(baseURL: URL, allowInsecureLocalNetwork: Bool = false, send: @escaping Send = HTTPAccountsAPI.liveSend) throws {
        _ = try AVEEndpoint(Self.asWebSocketScheme(baseURL), allowInsecureLocalNetwork: allowInsecureLocalNetwork)
        self.baseURL = baseURL
        self.send = send
    }

    public static let liveSend: Send = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.network }
        return (data, http)
    }

    // MARK: AccountsAPI

    public func requestOTP(phone: PhoneNumber, channel: OTPChannel) async throws -> OTPChallenge {
        let json = try await call("POST", "auth/otp/request", body: ["phone": phone.e164, "channel": channel.rawValue])
        guard let id = json["challenge_id"] as? String else { throw AuthError.unavailable }
        return OTPChallenge(id: id, retryAfterSeconds: json["retry_after_s"] as? Int)
    }

    public func verifyOTP(challengeID: String, code: String) async throws -> AuthCredentials {
        try credentials(try await call("POST", "auth/otp/verify", body: ["challenge_id": challengeID, "code": code]), .phone)
    }

    public func signInWithApple(identityToken: String, rawNonce: String, authorizationCode: String?) async throws -> AuthCredentials {
        var body: [String: Any] = ["identity_token": identityToken, "nonce": rawNonce]
        if let authorizationCode { body["authorization_code"] = authorizationCode }
        return try credentials(try await call("POST", "auth/apple", body: body), .apple)
    }

    public func guestChallenge() async throws -> Data {
        let json = try await call("POST", "auth/guest/challenge")
        guard let b64 = json["challenge"] as? String, let data = Data(base64Encoded: b64) else { throw AuthError.unavailable }
        return data
    }

    public func signInAsGuest(_ attestation: GuestAttestation, challenge: Data) async throws -> AuthCredentials {
        let body: [String: Any] = ["key_id": attestation.keyID, "attestation": attestation.attestation.base64EncodedString(),
                                   "challenge": challenge.base64EncodedString()]
        return try credentials(try await call("POST", "auth/guest", body: body), .guest)
    }

    public func accessToken(refreshToken: String) async throws -> AccessToken {
        let json = try await call("POST", "auth/token", bearer: refreshToken)
        guard let token = json["token"] as? String, let seconds = json["expires_in"] as? Double else { throw AuthError.unavailable }
        return AccessToken(token: token, expiresAt: Date().addingTimeInterval(seconds))
    }

    public func signOut(refreshToken: String) async throws {
        _ = try await call("POST", "auth/signout", bearer: refreshToken)
    }

    public func deleteAccount(refreshToken: String) async throws {
        _ = try await call("DELETE", "account", bearer: refreshToken)
    }

    public func profile(refreshToken: String) async throws -> AccountProfile {
        Self.profile(from: try await call("GET", "account/profile", bearer: refreshToken))
    }

    public func updateProfile(refreshToken: String, fullName: String?, termsVersion: String?, adultConfirmed: Bool?)
        async throws -> AccountProfile {
        var body: [String: Any] = [:]
        if let fullName { body["full_name"] = fullName }
        if let termsVersion { body["terms_version"] = termsVersion }
        if adultConfirmed == true { body["adult_confirmed"] = true }
        return Self.profile(from: try await call("PATCH", "account/profile", body: body, bearer: refreshToken))
    }

    static func profile(from json: [String: Any]) -> AccountProfile {
        AccountProfile(fullName: json["full_name"] as? String, termsVersion: json["terms_version"] as? String,
                       adultConfirmed: json["adult_confirmed"] as? Bool ?? false)
    }

    // MARK: Interne

    /// Les réponses de connexion portent `refresh_token`. Sans lui, la réponse est inutilisable.
    private func credentials(_ json: [String: Any], _ kind: AccountKind) throws -> AuthCredentials {
        guard let token = json["refresh_token"] as? String, !token.isEmpty else { throw AuthError.unavailable }
        return AuthCredentials(refreshToken: token, kind: kind)
    }

    private func call(_ method: String, _ path: String, body: [String: Any]? = nil, bearer: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await send(request)
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.network
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        switch http.statusCode {
        case 200..<300:
            return json
        case 401:
            // Sur une route à jeton long : il est révoqué. Sur une route de connexion : identifiants refusés.
            throw bearer != nil ? AuthError.signedOut : AuthError.rejected
        case 429:
            let retry = json["retry_after_s"] as? Int ?? Int(http.value(forHTTPHeaderField: "Retry-After") ?? "")
            throw AuthError.tooManyAttempts(retryAfterSeconds: retry)
        case 400..<500:
            switch json["error"] as? String {
            case "invalid_phone": throw AuthError.invalidPhone
            case "invalid_code": throw AuthError.invalidCode
            case "wrong_code": throw AuthError.wrongCode
            case "guest_unsupported": throw AuthError.guestUnsupported
            case "invalid_name": throw AuthError.invalidName
            default: throw AuthError.rejected
            }
        default:
            throw AuthError.unavailable
        }
    }

    /// `AVEEndpoint` valide `ws`/`wss` : on lui présente l'URL avec le schéma équivalent.
    private static func asWebSocketScheme(_ url: URL) -> URL {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.scheme = url.scheme?.lowercased() == "https" ? "wss" : "ws"
        return parts?.url ?? url
    }
}
