# Live Activity / Dynamic Island (étape 5)

## Ce qui est écrit
- `AVEKit` : `AVESessionAttributes` (partagé app + extension), `LiveActivityPhase` (pur), port `SessionActivityPresenting`,
  `SessionLiveActivityController` (ActivityKit). `SessionCoordinator` la démarre à l'ouverture de la session, ne lui envoie que les **changements**
  d'état, et l'arrête quand la session est perdue ou terminée.
- `AVE/LiveActivity/AVELiveActivityWidget.swift` : interface (écran verrouillé, Dynamic Island compacte/étendue/minimale). À ajouter à une **cible
  extension Widget** qui lie AVEKit (non créée : pas de projet Xcode dans le dépôt).
- Mises à jour **locales** uniquement (pas de push en v1). Aucun texte de conversation n'est affiché (visible sans déverrouiller).

## Branchement dans l'app
```swift
coordinator = SessionCoordinator(client: client, devices: try .system(), activity: SessionLiveActivityController())
```
Info.plist de l'app : `NSSupportsLiveActivities = YES`. L'extension n'a pas besoin d'accès au micro.

## À valider sur iPhone (rien n'a été compilé ni vu)
- Dynamic Island : iPhone 14 Pro ou plus ; sur les autres, seul l'écran verrouillé s'affiche.
- La demande de Live Activity échoue en arrière-plan ou si l'utilisateur l'a désactivée : volontairement silencieux.
- Le micro en arrière-plan dépend de `UIBackgroundModes: audio` et de la session audio, pas de la Live Activity ; l'indicateur micro d'iOS reste visible.
- VoiceOver sur les états ; chronomètre `Text(timerInterval:)` ; contraste sur `#010A29`.
