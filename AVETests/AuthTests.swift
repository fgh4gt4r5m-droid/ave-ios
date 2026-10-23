import Foundation
import Testing
@testable import AVECore
@testable import AVEKit

/// Faux service de comptes configurable.
final class StubAccounts: AccountsAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _tokenCalls = 0
    private var _calls: [String] = []
    var tokenResult: Result<AccessToken, AuthError> = .success(AccessToken(token: "t1", expiresAt: .distantFuture))
    var tokenDelay: Duration = .zero
    var verifyResult: Result<AuthCredentials, AuthError> = .success(AuthCredentials(refreshToken: "rt", kind: .phone))
    var otpResult: Result<OTPChallenge, AuthError> = .success(OTPChallenge(id: "c1", retryAfterSeconds: 30))
    var appleResult: Result<AuthCredentials, AuthError> = .success(AuthCredentials(refreshToken: "rt-apple", kind: .apple))
    var guestResult: Result<AuthCredentials, AuthError> = .success(AuthCredentials(refreshToken: "rt-guest", kind: .guest))
    var signOutFails = false
    var deleteFails = false

    var tokenCalls: Int { lock.withLock { _tokenCalls } }
    var calls: [String] { lock.withLock { _calls } }
    private func record(_ s: String) { lock.withLock { _calls.append(s) } }

    func requestOTP(phone: PhoneNumber, channel: OTPChannel) async throws -> OTPChallenge {
        record("otp:\(phone.e164):\(channel.rawValue)")
        return try otpResult.get()
    }
    func verifyOTP(challengeID: String, code: String) async throws -> AuthCredentials {
        record("verify:\(challengeID):\(code)")
        return try verifyResult.get()
    }
    func signInWithApple(identityToken: String, rawNonce: String, authorizationCode: String?) async throws -> AuthCredentials {
        record(authorizationCode.map { "apple:\($0)" } ?? "apple")
        return try appleResult.get()
    }
    func guestChallenge() async throws -> Data { record("guestChallenge"); return Data([9]) }
    func signInAsGuest(_ attestation: GuestAttestation, challenge: Data) async throws -> AuthCredentials {
        record("guest")
        return try guestResult.get()
    }
    func accessToken(refreshToken: String) async throws -> AccessToken {
        lock.withLock { _tokenCalls += 1 }
        if tokenDelay > .zero { try await Task.sleep(for: tokenDelay) }
        return try tokenResult.get()
    }
    func signOut(refreshToken: String) async throws {
        record("signOut")
        if signOutFails { throw AuthError.network }
    }
    func deleteAccount(refreshToken: String) async throws {
        record("delete")
        if deleteFails { throw AuthError.unavailable }
    }
}

final class ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { t } }
    func advance(_ s: TimeInterval) { lock.withLock { t = t.addingTimeInterval(s) } }
}

struct StubGuestAttester: GuestAttesting {
    var fail: AuthError?
    func attest(challenge: Data) async throws -> GuestAttestation {
        if let fail { throw fail }
        return GuestAttestation(keyID: "k", attestation: Data([1, 2]))
    }
}

@Suite("PhoneNumber")
struct PhoneNumberTests {
    @Test("formats acceptés")
    func accepted() {
        #expect(PhoneNumber("+224 621 23 45 67")?.e164 == "+224621234567")
        #expect(PhoneNumber("00224621234567")?.e164 == "+224621234567")
        #expect(PhoneNumber("621 23 45 67", defaultCountryCode: "224")?.e164 == "+224621234567")
        #expect(PhoneNumber("0621234567", defaultCountryCode: "33")?.e164 == "+33621234567")  // « 0 » local retiré
        #expect(PhoneNumber("(+33) 6.21.23.45.67")?.e164 == "+33621234567")
    }

    @Test("formats refusés")
    func rejected() {
        #expect(PhoneNumber("621234567") == nil)                    // pas d'indicatif et aucun défaut
        #expect(PhoneNumber("+22") == nil)                          // trop court
        #expect(PhoneNumber("+224 abc 123 456") == nil)
        #expect(PhoneNumber("+1234567890123456") == nil)            // plus de 15 chiffres
        #expect(PhoneNumber("+0224621234567") == nil)               // l'indicatif ne commence pas par 0
        #expect(PhoneNumber("621234567", defaultCountryCode: "2x4") == nil)
    }

    @Test("affichage masqué")
    func masked() {
        let masked = PhoneNumber("+224621234567")?.masked
        #expect(masked == "+224 •••• •• 67")
        #expect(masked?.contains("1234") == false)
    }
}

@Suite("AuthSession")
struct AuthSessionTests {
    private func make(_ api: StubAccounts, stored: String? = nil, clock: ClockBox = ClockBox()) -> (AuthSession, InMemoryTokenStore, ClockBox) {
        let store = InMemoryTokenStore(token: stored)
        return (AuthSession(api: api, store: store, now: { clock.now }), store, clock)
    }

    @Test("adopt : jeton long gardé dans le magasin, état connecté")
    func adopt() async throws {
        let (session, store, _) = make(StubAccounts())
        #expect(await session.state == .signedOut)
        try await session.adopt(AuthCredentials(refreshToken: "abc", kind: .apple))
        #expect(await session.state == .signedIn(.apple))
        #expect(store.readToken() == "apple:abc")
    }

    @Test("reprise au démarrage depuis le magasin ; contenu illisible = déconnecté")
    func restore() async {
        let (s1, _, _) = make(StubAccounts(), stored: "guest:xyz")
        #expect(await s1.state == .signedIn(.guest))
        for bad in ["n'importe quoi", "inconnu:abc", "phone:"] {
            let (s, _, _) = make(StubAccounts(), stored: bad)
            #expect(await s.state == .signedOut)
        }
    }

    @Test("jeton court mis en cache jusqu'à la marge d'expiration, puis renouvelé")
    func caching() async throws {
        let api = StubAccounts()
        let clock = ClockBox()
        api.tokenResult = .success(AccessToken(token: "court", expiresAt: clock.now.addingTimeInterval(600)))
        let (session, _, _) = make(api, stored: "phone:rt", clock: clock)
        #expect(try await session.accessToken() == "court")
        #expect(try await session.accessToken() == "court")
        #expect(api.tokenCalls == 1)
        clock.advance(571)  // il reste 29 s, sous la marge de 30 s
        _ = try await session.accessToken()
        #expect(api.tokenCalls == 2)
    }

    @Test("demandes simultanées regroupées en une seule requête")
    func coalescing() async throws {
        let api = StubAccounts()
        api.tokenDelay = .milliseconds(60)
        let (session, _, _) = make(api, stored: "phone:rt")
        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 { group.addTask { try await session.accessToken() } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(tokens == Array(repeating: "t1", count: 5))
        #expect(api.tokenCalls == 1)
    }

    @Test("jeton long révoqué (401) : déconnexion locale complète")
    func revoked() async throws {
        let api = StubAccounts()
        api.tokenResult = .failure(.signedOut)
        let (session, store, _) = make(api, stored: "phone:rt")
        await #expect(throws: AuthError.signedOut) { try await session.accessToken() }
        #expect(await session.state == .signedOut)
        #expect(store.readToken() == nil)
    }

    @Test("panne réseau : l'erreur remonte, la connexion est conservée")
    func networkKeepsSession() async throws {
        let api = StubAccounts()
        api.tokenResult = .failure(.network)
        let (session, store, _) = make(api, stored: "phone:rt")
        await #expect(throws: AuthError.network) { try await session.accessToken() }
        #expect(await session.state == .signedIn(.phone) && store.readToken() == "phone:rt")
        api.tokenResult = .success(AccessToken(token: "ok", expiresAt: .distantFuture))
        #expect(try await session.accessToken() == "ok")  // la panne n'est pas mise en cache
    }

    @Test("déconnecté : aucun jeton")
    func signedOutNoToken() async {
        let (session, _, _) = make(StubAccounts())
        await #expect(throws: AuthError.signedOut) { try await session.accessToken() }
    }

    @Test("signOut : l'appareil est déconnecté même si le serveur est injoignable")
    func signOutAlways() async {
        let api = StubAccounts()
        api.signOutFails = true
        let (session, store, _) = make(api, stored: "phone:rt")
        await session.signOut()
        #expect(await session.state == .signedOut && store.readToken() == nil)
        #expect(api.calls == ["signOut"])
    }

    @Test("suppression du compte : réussie = déconnecté ; échec = reste connecté, erreur visible")
    func deleteAccount() async throws {
        let api = StubAccounts()
        api.deleteFails = true
        let (session, store, _) = make(api, stored: "phone:rt")
        await #expect(throws: AuthError.unavailable) { try await session.deleteAccount() }
        #expect(await session.state == .signedIn(.phone) && store.readToken() == "phone:rt")
        api.deleteFails = false
        try await session.deleteAccount()
        #expect(await session.state == .signedOut && store.readToken() == nil)
    }

    @Test("le fournisseur de jeton d'AVE passe par la session")
    func tokenProviderBridge() async throws {
        let api = StubAccounts()
        let (session, _, _) = make(api, stored: "phone:rt")
        let provider = session.tokenProvider()
        #expect(try await provider() == "t1")
    }

    @Test("le flux d'états annonce l'état initial puis les changements")
    func statesStream() async throws {
        let (session, _, _) = make(StubAccounts())
        var iterator = session.states.makeAsyncIterator()
        #expect(await iterator.next() == .signedOut)
        try await session.adopt(AuthCredentials(refreshToken: "a", kind: .phone))
        #expect(await iterator.next() == .signedIn(.phone))
    }
}

@Suite("HTTPAccountsAPI")
struct HTTPAccountsAPITests {
    final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [URLRequest] = []
        var requests: [URLRequest] { lock.withLock { _requests } }
        func add(_ r: URLRequest) { lock.withLock { _requests.append(r) } }
    }

    private func api(status: Int = 200, body: String = "{}", headers: [String: String] = [:], capture: Capture = Capture(),
                     fail: Error? = nil) throws -> HTTPAccountsAPI {
        guard let base = URL(string: "https://accounts.test") else { throw AuthError.unavailable }
        return try HTTPAccountsAPI(baseURL: base) { request in
            capture.add(request)
            if let fail { throw fail }
            guard let url = request.url, let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers) else {
                throw AuthError.network
            }
            return (Data(body.utf8), http)
        }
    }

    @Test("https obligatoire ; http toléré seulement en local avec l'indicateur de développement")
    func scheme() throws {
        let send: HTTPAccountsAPI.Send = { _ in throw AuthError.network }
        #expect(throws: (any Error).self) { try HTTPAccountsAPI(baseURL: URL(string: "http://accounts.test") ?? URL(fileURLWithPath: "/"), send: send) }
        #expect(throws: (any Error).self) { try HTTPAccountsAPI(baseURL: URL(string: "http://accounts.test") ?? URL(fileURLWithPath: "/"), allowInsecureLocalNetwork: true, send: send) }
        _ = try HTTPAccountsAPI(baseURL: URL(string: "http://192.168.1.5:9000") ?? URL(fileURLWithPath: "/"), allowInsecureLocalNetwork: true, send: send)
        _ = try HTTPAccountsAPI(baseURL: URL(string: "https://accounts.test") ?? URL(fileURLWithPath: "/"), send: send)
    }

    @Test("demande de code : route, méthode et corps")
    func otpRequest() async throws {
        let cap = Capture()
        let a = try api(body: #"{"challenge_id":"c9","retry_after_s":30}"#, capture: cap)
        let phone = try #require(PhoneNumber("+224621234567"))
        let challenge = try await a.requestOTP(phone: phone, channel: .whatsapp)
        #expect(challenge == OTPChallenge(id: "c9", retryAfterSeconds: 30))
        let req = try #require(cap.requests.first)
        #expect(req.url?.absoluteString == "https://accounts.test/auth/otp/request" && req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try #require(try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any])
        #expect(body["phone"] as? String == "+224621234567" && body["channel"] as? String == "whatsapp")
    }

    @Test("connexions : le type de compte vient de la route, le jeton long de la réponse")
    func credentials() async throws {
        let a = try api(body: #"{"refresh_token":"rt-1"}"#)
        #expect(try await a.verifyOTP(challengeID: "c", code: "123456") == AuthCredentials(refreshToken: "rt-1", kind: .phone))
        #expect(try await a.signInWithApple(identityToken: "i", rawNonce: "n", authorizationCode: nil).kind == .apple)
        #expect(try await a.signInAsGuest(GuestAttestation(keyID: "k", attestation: Data([1])), challenge: Data([2])).kind == .guest)
        let empty = try api(body: "{}")
        await #expect(throws: AuthError.unavailable) { try await empty.verifyOTP(challengeID: "c", code: "1") }
    }

    @Test("Apple : le code d'autorisation part s'il existe (révocation à la suppression), absent sinon")
    func appleAuthorizationCode() async throws {
        let cap = Capture()
        let a = try api(body: #"{"refresh_token":"rt-1"}"#, capture: cap)
        _ = try await a.signInWithApple(identityToken: "i", rawNonce: "n", authorizationCode: "c0de")
        _ = try await a.signInWithApple(identityToken: "i", rawNonce: "n", authorizationCode: nil)
        let bodies = try cap.requests.map {
            try #require(try JSONSerialization.jsonObject(with: $0.httpBody ?? Data()) as? [String: Any])
        }
        #expect(bodies.count == 2 && cap.requests.allSatisfy { $0.url?.path == "/auth/apple" })
        #expect(bodies[0]["authorization_code"] as? String == "c0de" && bodies[0]["identity_token"] as? String == "i")
        #expect(bodies[1]["authorization_code"] == nil && bodies[1]["nonce"] as? String == "n")
    }

    @Test("jeton court : en-tête Bearer avec le jeton long")
    func accessTokenBearer() async throws {
        let cap = Capture()
        let a = try api(body: #"{"token":"t1.abc","expires_in":600}"#, capture: cap)
        let token = try await a.accessToken(refreshToken: "rt-1")
        #expect(token.token == "t1.abc" && token.expiresAt.timeIntervalSinceNow > 590)
        #expect(cap.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer rt-1")
        #expect(cap.requests.first?.url?.path == "/auth/token")
    }

    @Test("suppression : DELETE /account avec Bearer")
    func deleteRoute() async throws {
        let cap = Capture()
        try await api(capture: cap).deleteAccount(refreshToken: "rt")
        #expect(cap.requests.first?.httpMethod == "DELETE" && cap.requests.first?.url?.path == "/account")
    }

    @Test("correspondance des erreurs HTTP")
    func errors() async throws {
        let phone = try #require(PhoneNumber("+224621234567"))
        await #expect(throws: AuthError.signedOut) { try await api(status: 401).accessToken(refreshToken: "x") }
        await #expect(throws: AuthError.rejected) { try await api(status: 401).signInWithApple(identityToken: "i", rawNonce: "n", authorizationCode: nil) }
        await #expect(throws: AuthError.wrongCode) { try await api(status: 400, body: #"{"error":"wrong_code"}"#).verifyOTP(challengeID: "c", code: "1") }
        await #expect(throws: AuthError.invalidPhone) { try await api(status: 400, body: #"{"error":"invalid_phone"}"#).requestOTP(phone: phone, channel: .sms) }
        await #expect(throws: AuthError.guestUnsupported) { try await api(status: 403, body: #"{"error":"guest_unsupported"}"#).guestChallenge() }
        await #expect(throws: AuthError.tooManyAttempts(retryAfterSeconds: 42)) { try await api(status: 429, body: #"{"retry_after_s":42}"#).requestOTP(phone: phone, channel: .sms) }
        await #expect(throws: AuthError.tooManyAttempts(retryAfterSeconds: 7)) { try await api(status: 429, headers: ["Retry-After": "7"]).requestOTP(phone: phone, channel: .sms) }
        await #expect(throws: AuthError.unavailable) { try await api(status: 503).requestOTP(phone: phone, channel: .sms) }
        struct Boom: Error {}
        await #expect(throws: AuthError.network) { try await api(fail: Boom()).requestOTP(phone: phone, channel: .sms) }
    }
}

@MainActor
@Suite("SignInViewModel")
struct SignInViewModelTests {
    private func make(_ api: StubAccounts = StubAccounts(), attester: (any GuestAttesting)? = StubGuestAttester(),
                      country: String? = "224") -> (SignInViewModel, AuthSession, StubAccounts) {
        let session = AuthSession(api: api, store: InMemoryTokenStore())
        return (SignInViewModel(api: api, session: session, attester: attester, defaultCountryCode: country), session, api)
    }

    @Test("numéro invalide : message, aucun appel au service")
    func invalidPhone() async {
        let (vm, _, api) = make()
        vm.phoneInput = "abc"
        await vm.sendCode()
        #expect(vm.errorMessage == AuthMessages.message(for: .invalidPhone) && api.calls.isEmpty && vm.step == .welcome)
    }

    @Test("parcours téléphone : code demandé, puis validé, session ouverte")
    func phoneFlow() async {
        let (vm, session, api) = make()
        vm.choosePhone()
        vm.phoneInput = "621 23 45 67"
        vm.channel = .whatsapp
        await vm.sendCode()
        #expect(api.calls == ["otp:+224621234567:whatsapp"])
        #expect(vm.step == .code(phoneMasked: "+224 •••• •• 67") && vm.resendAfterSeconds == 30)
        vm.codeInput = "123456"
        await vm.verifyCode()
        #expect(api.calls.last == "verify:c1:123456")
        #expect(await session.state == .signedIn(.phone))
    }

    @Test("code erroné : message clair, pas de session")
    func wrongCode() async {
        let api = StubAccounts()
        api.verifyResult = .failure(.wrongCode)
        let (vm, session, _) = make(api)
        vm.phoneInput = "621234567"
        await vm.sendCode()
        vm.codeInput = "000000"
        await vm.verifyCode()
        #expect(vm.errorMessage == AuthMessages.message(for: .wrongCode))
        #expect(await session.state == .signedOut)
    }

    @Test("code non numérique : refusé avant tout appel")
    func nonNumericCode() async {
        let (vm, _, api) = make()
        vm.phoneInput = "621234567"
        await vm.sendCode()
        vm.codeInput = "12a456"
        await vm.verifyCode()
        #expect(vm.errorMessage == AuthMessages.message(for: .invalidCode))
        #expect(!api.calls.contains { $0.hasPrefix("verify") })
    }

    @Test("trop d'essais : délai conservé pour l'affichage")
    func rateLimited() async {
        let api = StubAccounts()
        api.otpResult = .failure(.tooManyAttempts(retryAfterSeconds: 45))
        let (vm, _, _) = make(api)
        vm.phoneInput = "621234567"
        await vm.sendCode()
        #expect(vm.resendAfterSeconds == 45 && vm.errorMessage?.contains("45") == true && vm.step == .welcome)
    }

    @Test("invité : attestation puis session ; sans attestation possible, message honnête")
    func guest() async {
        let (vm, session, _) = make()
        await vm.continueAsGuest()
        #expect(await session.state == .signedIn(.guest))
        let (none, _, _) = make(attester: nil)
        #expect(!none.canUseGuest)
        await none.continueAsGuest()
        #expect(none.errorMessage == AuthMessages.message(for: .guestUnsupported))
        let (failing, s3, api3) = make(attester: StubGuestAttester(fail: .guestUnsupported))
        await failing.continueAsGuest()
        #expect(failing.errorMessage == AuthMessages.message(for: .guestUnsupported))
        #expect(await s3.state == .signedOut && !api3.calls.contains("guest"))
    }

    @Test("Apple : session ouverte ; annulation silencieuse, échec signalé")
    func apple() async {
        let (vm, session, api) = make()
        await vm.signInWithApple(identityToken: "jeton", rawNonce: "n")
        // Deux vérifications : `await` est interdit à droite de `&&` (l'opérande droite est une autoclosure synchrone).
        #expect(api.calls == ["apple"])
        #expect(await session.state == .signedIn(.apple))
        let (v2, _, _) = make()
        v2.appleCancelled()
        #expect(v2.errorMessage == nil)
        v2.appleFailed()
        #expect(v2.errorMessage != nil)
    }

    @Test("indicatif choisi : le numéro national suffit ; un numéro avec « + » garde le sien")
    func chosenCountryCode() async {
        let (vm, _, api) = make()
        #expect(vm.countryCode == "224")  // proposé d'avance
        vm.countryCode = "221"
        vm.phoneInput = "77 123 45 67"
        await vm.sendCode()
        #expect(api.calls == ["otp:+221771234567:sms"])
        let (other, _, api2) = make()
        other.phoneInput = "+33 6 12 34 56 78"
        await other.sendCode()
        #expect(api2.calls == ["otp:+33612345678:sms"])
    }

    @Test("code : seuls les chiffres, 6 au plus ; complet = validé une seule fois, un nouveau code repart")
    func codeAutoSubmit() async {
        let (vm, _, _) = make()
        vm.phoneInput = "621234567"
        await vm.sendCode()
        vm.codeInput = "12 3a4"
        #expect(!vm.codeDidChange())
        #expect(vm.codeInput == "1234")
        vm.codeInput = "1234567"
        #expect(vm.codeDidChange())
        #expect(vm.codeInput == "123456")
        #expect(!vm.codeDidChange())  // même code : pas renvoyé en boucle
        vm.codeInput = "123450"
        #expect(vm.codeDidChange())  // nouveau code : il part
    }

    @Test("renvoi : décompte depuis l'envoi, puis plus de décompte")
    func resendCountdown() async {
        let (vm, _, _) = make()
        #expect(vm.resendCountdown() == nil)  // aucun code envoyé
        vm.phoneInput = "621234567"
        await vm.sendCode()
        let sent = Date()
        #expect((vm.resendCountdown(at: sent) ?? 0) > 25)  // le service a demandé 30 s
        #expect(vm.resendCountdown(at: sent.addingTimeInterval(31)) == nil)
    }

    @Test("retour : code → téléphone → accueil, erreur effacée")
    func back() async {
        let (vm, _, _) = make()
        vm.phoneInput = "621234567"
        await vm.sendCode()
        vm.back()
        #expect(vm.step == .phone && vm.codeInput.isEmpty)
        vm.back()
        #expect(vm.step == .welcome)
    }
}
