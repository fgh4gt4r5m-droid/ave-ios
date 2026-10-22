# AVE — app iOS (étapes 1–2)

Cible : iOS 17+, Swift 6. Le cœur testable (Domain, Core/Network, Core/Storage) est un package SwiftPM ;
l'app SwiftUI, l'audio et la Live Activity iront dans une cible Xcode (non créée à ce stade).

```bash
cd ios && swift test          # sur Mac, Xcode 16+ (Swift Testing)
```

**Rien de ce code n'a été compilé** : la session de développement n'avait pas de toolchain Swift
(téléchargement bloqué). Voir `../DEPENDANCES-SERVEUR.md` pour les écarts avec le serveur.

## Test de bout en bout contre le serveur de dev

```bash
python3 -m ave                       # depuis la racine du dépôt ; AVE_HOST=0.0.0.0 pour y accéder depuis l'iPhone
# URL : ws://<IP du Mac>:8787/v1/stream
```

`ws://` n'est accepté qu'avec `allowInsecureLocalNetwork: true` et vers un hôte local. Pour l'app, ajouter
une exception ATS **limitée à la configuration Debug** (`NSAllowsLocalNetworking`), jamais en Release.

## Sécurité

- Jeton : Keychain uniquement (`KeychainTokenStore`), envoyé dans le `hello`, jamais dans l'URL.
- Logs : constantes, codes et compteurs uniquement (voir `AVELogger`).
- Aucune clé dans le dépôt.
