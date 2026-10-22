import Foundation
import Testing
@testable import AVECore
@testable import AVEKit

@Suite("AVEConfiguration")
struct AVEConfigurationTests {
    @Test("le client créé utilise l'endpoint et le fournisseur de jeton asynchrone de l'hôte")
    func clientUsesHostTokenProvider() async throws {
        let url = try #require(URL(string: "wss://ave.test/v1/stream"))
        let config = AVEConfiguration(endpoint: try AVEEndpoint(url), defaultLanguage: .french,
                                      tokenProvider: { "jeton-de-l-hote" })
        let factory = FakeTransportFactory()
        let client = config.makeClient(transportFactory: factory.factory)
        await client.start()
        let t = try #require(await factory.waitForTransport(0))
        #expect(await eventually { !t.sentJSON.isEmpty })
        #expect(t.sentJSON[0]["token"] as? String == "jeton-de-l-hote")
        #expect(t.sentJSON[0]["lang"] as? String == "fra")
        await client.stop()
    }

    @Test("un fournisseur qui lève fait échouer la tentative puis réessaie")
    func throwingProviderRetries() async throws {
        struct NoToken: Error {}
        let url = try #require(URL(string: "wss://ave.test/v1/stream"))
        let counter = Counter()
        let config = AVEConfiguration(endpoint: try AVEEndpoint(url), tokenProvider: {
            if await counter.next() < 2 { throw NoToken() }
            return "ok"
        })
        let factory = FakeTransportFactory()
        let client = config.makeClient(transportFactory: factory.factory)
        await client.start()
        #expect(await eventually(timeout: .seconds(5)) { factory.count >= 3 })
        await client.stop()
    }
}

actor Counter {
    private var n = 0
    func next() -> Int { defer { n += 1 }; return n }
}
