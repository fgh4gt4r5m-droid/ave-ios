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
    /// Numéro saisi SANS indicatif (l'indicatif est choisi à part, `countryCode`). Un numéro tapé avec « + » reste accepté.
    public var phoneInput = ""
    public var codeInput = ""
    public var channel: OTPChannel = .sms
    /// Indicatif choisi (sans « + », ex. « 224 »), proposé d'avance : on ne le tape pas.
    public var countryCode: String?
    /// Moment de l'envoi du dernier code : pour afficher le décompte avant de pouvoir en redemander un.
    public private(set) var codeSentAt: Date?
    /// Nom complet donné par Apple (seulement à la toute première connexion) : il pré-remplit l'écran du nom.
    public private(set) var suggestedFullName: String?

    /// Longueur des codes du service de comptes.
    public static let codeLength = 6

    @ObservationIgnored private let api: any AccountsAPI
    @ObservationIgnored private let session: AuthSession
    @ObservationIgnored private let attester: (any GuestAttesting)?
    @ObservationIgnored private var challengeID: String?
    /// Dernier code envoyé automatiquement : un code faux n'est pas renvoyé en boucle, seul un nouveau code part.
    @ObservationIgnored private var lastSubmittedCode: String?

    public init(api: any AccountsAPI, session: AuthSession, attester: (any GuestAttesting)? = nil,
                defaultCountryCode: String? = nil) {
        self.api = api
        self.session = session
        self.attester = attester
        self.countryCode = defaultCountryCode
    }

    public var canUseGuest: Bool { attester != nil }

    public func choosePhone() {
        errorMessage = nil
        step = .phone
    }

    public func back() {
        errorMessage = nil
        codeInput = ""
        lastSubmittedCode = nil
        switch step {
        case .code: step = .phone
        case .phone, .welcome: step = .welcome
        }
    }

    public func sendCode() async {
        guard let phone = PhoneNumber(phoneInput, defaultCountryCode: countryCode) else {
            errorMessage = AuthMessages.message(for: .invalidPhone)
            return
        }
        await run {
            let challenge = try await self.api.requestOTP(phone: phone, channel: self.channel)
            self.challengeID = challenge.id
            self.resendAfterSeconds = challenge.retryAfterSeconds
            self.codeSentAt = Date()
            self.codeInput = ""
            self.lastSubmittedCode = nil
            self.step = .code(phoneMasked: phone.masked)
        }
    }

    /// À chaque frappe dans le code : ne garde que les chiffres (6 au plus). Renvoie vrai quand le code est complet et
    /// pas encore essayé : la vue le valide alors toute seule, sans bouton (le code du SMS se colle d'un toucher).
    public func codeDidChange() -> Bool {
        let digits = String(codeInput.filter { ("0"..."9").contains($0) }.prefix(Self.codeLength))
        if digits != codeInput { codeInput = digits }
        guard digits.count == Self.codeLength, digits != lastSubmittedCode, !isWorking else { return false }
        lastSubmittedCode = digits
        return true
    }

    /// Secondes avant de pouvoir redemander un code, à l'instant `now` (`nil` : on peut redemander).
    public func resendCountdown(at now: Date = Date()) -> Int? {
        guard let wait = resendAfterSeconds, let sentAt = codeSentAt else { return nil }
        let remaining = wait - Int(now.timeIntervalSince(sentAt).rounded(.down))
        return remaining > 0 ? remaining : nil
    }

    /// « Renvoyer un code » : même numéro, même canal.
    public func resendCode() async {
        await sendCode()
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
    public func signInWithApple(identityToken: String, rawNonce: String, authorizationCode: String? = nil,
                                fullName: String? = nil) async {
        if let fullName { suggestedFullName = fullName }
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
