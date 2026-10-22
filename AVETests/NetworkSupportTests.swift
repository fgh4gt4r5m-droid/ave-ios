import Foundation
import Testing
@testable import AVECore

@Suite("Backoff et endpoint")
struct NetworkSupportTests {
    @Test("backoff 250 ms → 5 s, plafonné")
    func backoff() {
        let b = Backoff()
        let ms = (0..<8).map { b.delay(forAttempt: $0) }
        #expect(ms == [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(2),
                       .seconds(4), .seconds(5), .seconds(5), .seconds(5)])
    }

    @Test("wss accepté")
    func wss() throws {
        _ = try AVEEndpoint(#require(URL(string: "wss://api.example.com/v1/stream")))
    }

    @Test("ws refusé par défaut, même en local")
    func wsRefused() throws {
        let url = try #require(URL(string: "ws://192.168.1.10:8787/v1/stream"))
        #expect(throws: AVEEndpointError.insecureSchemeNotAllowed) { try AVEEndpoint(url) }
    }

    @Test("ws toléré en dev uniquement vers le réseau local")
    func wsLocal() throws {
        for host in ["192.168.1.10", "10.0.0.2", "172.16.5.5", "172.31.0.1", "127.0.0.1", "mac.local", "localhost"] {
            let url = try #require(URL(string: "ws://\(host):8787/v1/stream"))
            _ = try AVEEndpoint(url, allowInsecureLocalNetwork: true)
        }
        for host in ["8.8.8.8", "172.32.0.1", "example.com", "192.169.0.1"] {
            let url = try #require(URL(string: "ws://\(host):8787/v1/stream"))
            #expect(throws: AVEEndpointError.insecureSchemeNotAllowed) {
                try AVEEndpoint(url, allowInsecureLocalNetwork: true)
            }
        }
    }

    @Test("jeton dans l'URL refusé")
    func tokenInURL() throws {
        let q = try #require(URL(string: "wss://api.example.com/v1/stream?token=abc"))
        #expect(throws: AVEEndpointError.credentialsInURL) { try AVEEndpoint(q) }
        let u = try #require(URL(string: "wss://user:pw@api.example.com/v1/stream"))
        #expect(throws: AVEEndpointError.credentialsInURL) { try AVEEndpoint(u) }
    }

    @Test("schéma http refusé")
    func http() throws {
        let url = try #require(URL(string: "https://api.example.com/v1/stream"))
        #expect(throws: AVEEndpointError.invalidURL) { try AVEEndpoint(url) }
    }

    @Test("TokenStore en mémoire")
    func tokenStore() throws {
        let s = InMemoryTokenStore()
        #expect(s.readToken() == nil)
        try s.saveToken("a")
        #expect(s.readToken() == "a")
        try s.deleteToken()
        #expect(s.readToken() == nil)
    }
}
