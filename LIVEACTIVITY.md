# Live Activity / Dynamic Island (étape 5)

## Ce qui est écrit
- `AVEKit` : `AVESessionAttributes` (partagé app + extension), `LiveActivityPhase` (pur), port `SessionActivityPresenting`,
  `SessionLiveActivityController` (ActivityKit). `SessionCoordinator` la démarre à l'ouverture de la session, ne lui envoie que les **changements**
  d'état, et l'arrête quand la session est perdue ou terminée.
- `AVE/LiveActivity/AVELiveActivityWidget.swift` : interface (écran verrouillé, Dynamic Island compacte/étendue/minimale), cible
  **extension Widget** `AVELiveActivity` de `project.yml`. L'extension **ne lie pas AVEKit** : elle compile directement
  `AVESessionAttributes.swift`, `LiveActivityPhase.swift` et `AVEPalette.swift` (sans dépendance). Lier le package depuis l'app
  (AVECore + AVEKit) et depuis l'extension (AVEKit) fait échouer Xcode ; ActivityKit associe les deux côtés par le nom du type.
  Ce qui dépend du reste d'AVEKit (`LiveActivityPhase(orb:)`, `SessionActivityPresenting`) est dans `SessionActivityPresenting.swift`.
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
