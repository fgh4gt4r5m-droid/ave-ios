# Compiler avec Codemagic

Il n'y a pas de fichier `.xcodeproj` dans le dépôt : `project.yml` (XcodeGen) le décrit et Codemagic le génère à chaque build.
Le code vit dans le package SwiftPM (`Package.swift`) ; le projet ne fait que l'habiller en app iOS + extension Live Activity.

## Première mise en route
1. Dans Codemagic : **Add application** → GitHub → autoriser l'accès au dépôt privé `ave-ios` → type de projet « Other / iOS native » → **utiliser `codemagic.yaml`**.
2. Lancer le workflow **`ave-ci`** (se déclenche aussi à chaque push). Il fait, dans l'ordre :
   1. `swift test` sur macOS (la logique pure : protocole, client WebSocket, audio sans matériel, écrans, authentification) ;
   2. génération du projet (`xcodegen generate`) ;
   3. compilation de l'app pour simulateur iOS, **sans signature**, ce qui compile aussi tout le code propre à iOS (AVFoundation, SwiftUI, ActivityKit) ;
   4. tests sur simulateur iOS.
3. **Le premier lancement échouera très probablement** : ce code n'a jamais été compilé. Envoyez-moi le journal (`build.log` / `test.log` sont fournis en artefacts) et je corrige.

## Ce qui reste à faire pour TestFlight (workflow `ave-testflight`, manuel)
- Identifiants d'app chez Apple : `fr.ave.app` et `fr.ave.app.liveactivity` (à adapter dans `project.yml` si vous préférez un autre préfixe), avec les capacités **Sign in with Apple** et **App Attest**.
- Intégration **App Store Connect** dans Codemagic, nommée `AVE_ASC_KEY` (ou changer le nom dans `codemagic.yaml`), et signature automatique iOS.
- Groupe de variables `ave` avec `AVE_ENDPOINT` (`wss://…/v1/stream`) et `AVE_ACCOUNTS_URL` (`https://…`) : les valeurs de `Config/Release.xcconfig` sont des **placeholders** (`.example`).
- Icône 1024 × 1024 px dans `AVE/App/Assets.xcassets/AppIcon.appiconset` (voir `ASSETS.md`).
- Aucune clé ni jeton dans le dépôt ni dans les variables : l'app n'en contient pas.

## Réglages
`Config/Debug.xcconfig` et `Config/Release.xcconfig` ; surcharges locales dans `Config/Secrets.xcconfig` (ignoré par git).
Debug autorise `ws://` vers le réseau local (exception ATS seulement dans `Config/AVE-Info-Debug.plist`, jamais en Release) et utilise un FAUX service de comptes (code « 000000 ») tant que `AVE_ACCOUNTS_URL` est vide.

## Limites connues
- `project.yml` n'a pas pu être exécuté avec XcodeGen dans l'environnement de développement (pas de macOS) : sa syntaxe est conforme à la documentation mais non vérifiée, notamment la référence aux tests du package dans le schéma (`package: AVEPackage/AVETests`).
- Les tests sur simulateur utilisent le premier iPhone disponible de l'image Codemagic.
