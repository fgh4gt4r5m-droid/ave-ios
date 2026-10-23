# AVE : app iOS (voix et texte)

Cible : iOS 27+ (Xcode 27.1), Swift 6, composants système et HIG d'Apple. Le cœur testable (Domain, Core/Network, Core/Storage) est un package SwiftPM ;
l'app SwiftUI et la Live Activity iront dans des cibles Xcode (non créées à ce stade).

```bash
swift test          # sur Mac, Xcode 16+ (Swift Testing)
```

**Rien de ce code n'a été compilé** : la session de développement n'avait pas de toolchain Swift
(téléchargement bloqué). Les écarts avec le serveur et les extensions du protocole sont suivis dans `contrat/CONTRAT.md` du dépôt `african-voice-engine`. Lire `CLAUDE.md` en premier.

## Test de bout en bout contre le serveur de dev

```bash
python3 -m ave                       # depuis la racine du dépôt `african-voice-engine` ; AVE_AUTH=none pour le dev ; AVE_HOST=0.0.0.0 pour y accéder depuis l'iPhone
# URL : ws://<IP du Mac>:8787/v1/stream
```

`ws://` n'est accepté qu'avec `allowInsecureLocalNetwork: true` et vers un hôte local. Pour l'app, ajouter
une exception ATS **limitée à la configuration Debug** (`NSAllowsLocalNetworking`), jamais en Release.

## Sécurité

- Jeton : Keychain uniquement (`KeychainTokenStore`), envoyé dans le `hello`, jamais dans l'URL.
- Logs : constantes, codes et compteurs uniquement (voir `AVELogger`).
- Aucune clé dans le dépôt.

## Compilation
Pas de Mac nécessaire : voir `CODEMAGIC.md` (projet généré par XcodeGen, build et tests sur Codemagic).

## Dépôts
- `african-voice-engine` : moteur + contrat partagé (`contrat/`).
- `ave-accounts` : service de comptes (connexion, jetons courts).
- `ave-ios` : cette app.
