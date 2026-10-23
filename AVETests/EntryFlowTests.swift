import Foundation
import Testing
@testable import AVECore
@testable import AVEKit

// Entrée validée le 2026-10-23 : après la connexion, le nom complet, puis l'âge et les conditions.

@Suite("Entrée : nom, âge et conditions")
struct EntryFlowTests {
    private let accepted = AccountProfile(fullName: "Fatou Camara", termsVersion: Terms.currentVersion, adultConfirmed: true)

    @Test("compte neuf : le nom d'abord (pré-rempli par Apple s'il le donne), puis les conditions")
    func newAccount() {
        #expect(EntryFlow.next(kind: .phone, profile: AccountProfile(), localFullName: "", localTermsVersion: nil)
                == .name(suggestion: nil))
        #expect(EntryFlow.next(kind: .apple, profile: AccountProfile(), localFullName: "", localTermsVersion: nil,
                               suggestedName: "Fatou Camara") == .name(suggestion: "Fatou Camara"))
        #expect(EntryFlow.next(kind: .phone, profile: AccountProfile(fullName: "Fatou Camara"), localFullName: "",
                               localTermsVersion: nil) == .terms)
    }

    @Test("essai sans compte : pas d'écran de nom, mais les conditions")
    func guest() {
        #expect(EntryFlow.next(kind: .guest, profile: nil, localFullName: "", localTermsVersion: nil) == .terms)
    }

    @Test("réinstallation : le profil du compte suffit, rien n'est redemandé")
    func reinstall() {
        #expect(EntryFlow.next(kind: .phone, profile: accepted, localFullName: "", localTermsVersion: nil) == .done)
    }

    @Test("hors ligne : ce que l'iPhone a noté suffit ; nouvelle version des conditions ou âge non confirmé : redemandé")
    func offlineAndNewVersion() {
        #expect(EntryFlow.next(kind: .phone, profile: nil, localFullName: "Fatou", localTermsVersion: Terms.currentVersion)
                == .done)
        #expect(EntryFlow.next(kind: .phone, profile: nil, localFullName: "Fatou", localTermsVersion: "2025-01-v0") == .terms)
        let notAdult = AccountProfile(fullName: "Fatou", termsVersion: Terms.currentVersion, adultConfirmed: false)
        #expect(EntryFlow.next(kind: .phone, profile: notAdult, localFullName: "", localTermsVersion: nil) == .terms)
    }

    @Test("nom : nettoyé comme par le service ; prénom pour saluer ; nom d'Apple assemblé")
    func names() {
        #expect(EntryFlow.cleanedName("  Fatou   Camara \n") == "Fatou Camara")
        #expect(EntryFlow.cleanedName("F") == nil && EntryFlow.cleanedName(String(repeating: "a", count: 81)) == nil)
        #expect(EntryFlow.firstName(of: "Fatou Camara") == "Fatou")
        #expect(EntryFlow.appleName(given: "Fatou", family: " Camara ") == "Fatou Camara")
        #expect(EntryFlow.appleName(given: nil, family: "") == nil)
    }

    @Test("le texte des conditions dit l'âge minimum et ce qui reste sur l'iPhone")
    func termsText() {
        #expect(Terms.conditions.contains("18 ans ou plus"))
        #expect(Terms.privacy.contains("reste sur votre iPhone"))
        #expect(!Terms.currentVersion.isEmpty)
    }
}

@Suite("Entrée : profil du service de comptes")
struct AccountProfileAPITests {
    final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [URLRequest] = []
        func add(_ r: URLRequest) { lock.withLock { _requests.append(r) } }
        var requests: [URLRequest] { lock.withLock { _requests } }
    }

    private func api(status: Int = 200, body: String, capture: Capture) throws -> HTTPAccountsAPI {
        let base = try #require(URL(string: "https://accounts.test"))
        return try HTTPAccountsAPI(baseURL: base) { request in
            capture.add(request)
            guard let url = request.url,
                  let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
                throw AuthError.network
            }
            return (Data(body.utf8), http)
        }
    }

    @Test("GET et PATCH /account/profile : jeton long en en-tête, champs absents non envoyés, âge seulement à vrai")
    func routes() async throws {
        let cap = Capture()
        let body = #"{"full_name":"Fatou Camara","terms_version":"2026-10-v1","terms_accepted_at":1,"adult_confirmed":true}"#
        let a = try api(body: body, capture: cap)
        #expect(try await a.profile(refreshToken: "r1")
                == AccountProfile(fullName: "Fatou Camara", termsVersion: "2026-10-v1", adultConfirmed: true))
        _ = try await a.updateProfile(refreshToken: "r1", fullName: nil, termsVersion: "2026-10-v1", adultConfirmed: true)
        let get = try #require(cap.requests.first)
        #expect(get.httpMethod == "GET" && get.url?.path == "/account/profile")
        #expect(get.value(forHTTPHeaderField: "Authorization") == "Bearer r1")
        let patch = try #require(cap.requests.last)
        #expect(patch.httpMethod == "PATCH")
        let sent = try #require(try JSONSerialization.jsonObject(with: try #require(patch.httpBody)) as? [String: Any])
        #expect(sent["full_name"] == nil && sent["terms_version"] as? String == "2026-10-v1")
        #expect(sent["adult_confirmed"] as? Bool == true)
    }

    @Test("nom refusé par le service : message clair")
    func invalidName() async throws {
        let a = try api(status: 400, body: #"{"error":"invalid_name"}"#, capture: Capture())
        await #expect(throws: AuthError.invalidName) {
            _ = try await a.updateProfile(refreshToken: "r1", fullName: "x", termsVersion: nil, adultConfirmed: nil)
        }
        #expect(AuthMessages.message(for: .invalidName).contains("prénom"))
    }
}
