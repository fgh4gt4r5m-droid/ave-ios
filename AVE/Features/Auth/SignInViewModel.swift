import AVECore
import Foundation
import Observation

public enum SignInStep: Sendable, Equatable {
    case welcome
    case phone
    case code(phoneMasked: String)
}

/// Parcours de connexion : téléphone + code, Apple, invité. Aucune méthode n'est obligatoire.
@MainActor
@Observable
public final class SignInViewModel {
    public private(set) var step: SignInStep = .welcome
    public private(set) var isWorking = false
    public private(set) var errorMessage: String?
    /// Secondes avant de pouvoir redemander un code (donné par le service).
    public private(set) var resendAfterSeconds: Int?
    public var phoneInput = ""
    public var codeInput = ""
    public var channel: OTPChannel = .sms

    @ObservationIgnored private let api: any AccountsAPI
    @ObservationIgnored private let session: AuthSession
    @ObservationIgnored private let attester: (any GuestAttesting)?
    @ObservationIgnored private let defaultCountryCode: String?
    @ObservationIgnored private var challengeID: String?

    public init(api: any AccountsAPI, session: AuthSession, attester: (any GuestAttesting)? = nil,
                defaultCountryCode: String? = nil) {
        self.api = api
        self.session = session
        self.attester = attester
        self.defaultCountryCode = defaultCountryCode
    }

    public var canUseGuest: Bool { attester != nil }

    public func choosePhone() {
        errorMessage = nil
        step = .phone
    }

    public func back() {
        errorMessage = nil
        codeInput = ""
        switch step {
        case .code: step = .phone
        case .phone, .welcome: step = .welcome
        }
    }

    public func sendCode() async {
        guard let phone = PhoneNumber(phoneInput, defaultCountryCode: defaultCountryCode) else {
            errorMessage = AuthMessages.message(for: .invalidPhone)
            return
        }
        await run {
            let challenge = try await self.api.requestOTP(phone: phone, channel: self.channel)
            self.challengeID = challenge.id
            self.resendAfterSeconds = challenge.retryAfterSeconds
            self.codeInput = ""
            self.step = .code(phoneMasked: phone.masked)
        }
    }

    public func verifyCode() async {
        let code = codeInput.filter(\.isNumber)
        guard !code.isEmpty, code.count == codeInput.count, let challengeID else {
            errorMessage = AuthMessages.message(for: .invalidCode)
            return
        }
        await run {
            let credentials = try await self.api.verifyOTP(challengeID: challengeID, code: code)
            try await self.session.adopt(credentials)
        }
    }

    /// `rawNonce` : le nonce brut dont le SHA-256 a été donné à Apple (le service le revérifie).
    public func signInWithApple(identityToken: String, rawNonce: String, authorizationCode: String? = nil) async {
        await run {
            let credentials = try await self.api.signInWithApple(identityToken: identityToken, rawNonce: rawNonce,
                                                                 authorizationCode: authorizationCode)
            try await self.session.adopt(credentials)
        }
    }

    public func continueAsGuest() async {
        guard let attester else {
            errorMessage = AuthMessages.message(for: .guestUnsupported)
            return
        }
        await run {
            let challenge = try await self.api.guestChallenge()
            let attestation = try await attester.attest(challenge: challenge)
            let credentials = try await self.api.signInAsGuest(attestation, challenge: challenge)
            try await self.session.adopt(credentials)
        }
    }

    /// L'utilisateur a annulé la fenêtre d'Apple : ce n'est pas une erreur à afficher.
    public func appleCancelled() { errorMessage = nil }

    public func appleFailed() { errorMessage = AuthMessages.message(for: .rejected) }

    private func run(_ work: @MainActor () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch let error as AuthError {
            errorMessage = AuthMessages.message(for: error)
            if case .tooManyAttempts(let seconds) = error { resendAfterSeconds = seconds }
        } catch {
            errorMessage = AuthMessages.message(for: .unavailable)
        }
    }
}
