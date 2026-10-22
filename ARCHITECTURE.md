# Architecture de l'app AVE

## Produit : trois façons d'utiliser AVE

| Mode | Qui | Authentification | Ce que l'app embarque |
|---|---|---|---|
| **App AVE grand public** (type Claude / ChatGPT / Gemini) | particuliers | compte utilisateur → jeton de session (Keychain) | l'app complète |
| **Intégration WoYo / TaGa** | nos propres apps | l'app hôte demande un jeton court à **son** backend | `AVEKit` (pas d'app) |
| **API B2B** (console, centres de relation client, sites, apps) | entreprises | clé API émise par la console, **côté serveur du client uniquement** | rien côté iOS ; SDK serveur et web |

Règle de fond : **aucune clé B2B dans un binaire mobile** (extractible). Le mobile ne voit que des jetons
courts, obtenus auprès du backend de l'hôte, qui échange sa clé contre un jeton (`POST /v1/token`, contrat E8).

## Modules (Swift Package `ios/Package.swift`)

```
AVECore   Domain + Core/Network + Core/Storage    Foundation seule, testable sans UI ni micro
            protocole, trames, client WebSocket, jeton, endpoint validé
AVEKit    Kit/  (puis Core/Audio, session, UI partageable)   ce que WoYo et TaGa importent
            AVEConfiguration → makeClient(), puis AVEAssistant (facade), orbe vocal, vue de chat
App AVE   App/ + écrans propres au grand public         compte, onboarding, historique, réglages, abonnement
```

Dépendances : `App AVE → AVEKit → AVECore`. Rien ne remonte : `AVECore` ne connaît ni SwiftUI ni AVFoundation.
Pas de dépendance tierce.

### Intégrer AVEKit dans une app hôte
```swift
let config = AVEConfiguration(
    endpoint: try AVEEndpoint(url),               // wss obligatoire
    tokenProvider: { try await monBackend.jetonAVE() })   // jamais une clé B2B
let client = config.makeClient(language: .french)
```
L'hôte garde la maîtrise de l'identité de l'utilisateur ; AVE ne voit qu'un jeton.

## Ce qui est volontairement différé
Facade `AVEAssistant`, audio (étape 3), écrans (étape 4), Live Activity (étape 5), thème personnalisable pour
l'intégration (WoYo/TaGa auront leur charte), compte utilisateur grand public (dépend du serveur : E10).

## Limites connues
Rien de ce code n'est compilé (pas de toolchain Swift dans l'environnement de dev). Un jeton introuvable fait
échouer la tentative de connexion, rejouée avec le backoff (jusqu'à ce que l'hôte fournisse un jeton).

## Connexion (grand public)
Trois méthodes, aucune obligatoire : téléphone + code (SMS/WhatsApp), Sign in with Apple, invité (App Attest). Un service de comptes **dédié**
(spécification : `contrat/CONTRAT.md` §6, non construit) garde la clé B2B et délivre des jetons AVE courts. Côté app : `Core/Auth`
(`AccountsAPI`, `AuthSession` avec cache de jeton, `HTTPAccountsAPI`), `Features/Auth` (parcours et écrans). En DEBUG sans service configuré,
l'app utilise `DevAccountsAPI` (faux, code « 000000 »). Les apps hôtes (WoYo, TaGa) ne l'utilisent pas : leur backend fournit le jeton.
