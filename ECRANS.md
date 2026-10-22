# Écrans (étape 4) : décisions et limites

## Structure
- `Features/VoiceAssistant/SessionCoordinator` : une session, deux modes. Relie client WebSocket, audio, machine du
  barge-in, VAD et conversation. Basculer voix ↔ texte coupe le micro, jamais la session.
- `Features/Chat` : `ChatTranscript` (pur, testé), `ChatView`, bulles, cartes d'action.
- `Features/VoiceAssistant/FloatingVoiceOrbView` + `OrbState` (pur, testé).
- `Features/Shared` : `LanguageCatalog`/`LanguagePicker`, `UserMessages`, `AVETheme` (charte remplaçable par WoYo/TaGa).
- Les vues SwiftUI sont sous `#if os(iOS)` ; la logique est testable partout.

## Décisions à connaître
1. **Confirmation des actions** : exigée sauf si le serveur envoie explicitement `confirm: false`. Le serveur actuel
   n'envoie pas ce champ ; exécuter `order_ride` sans accord serait dangereux. À confirmer au contrat (Q1).
2. **Mode texte** : la saisie est désactivée avec une explication, car le protocole n'a pas de message pour le texte (E13).
   Rien n'est simulé.
3. **Texte des réponses** : sans `reply_text` (E3), la bulle affiche « Réponse vocale » avec « Réécouter ». Dès que
   `reply_text` existe, la bulle se construit phrase par phrase.
4. **Réécouter** : rejoue l'audio gardé en mémoire (4 Mo max, les plus anciens sortent d'abord), faute de message `speak` (E7).
5. **Langues** : liste en dur ; seul le français (et la détection, qui ne comprend que le français) est annoncé disponible.
   Les autres sont sélectionnables mais clairement signalées « pas encore disponible ». Aucune promesse de latence.
6. **Un seul flux d'événements** (état, protocole, audio) côté client : l'ordre est garanti.

## À valider dans Xcode / sur iPhone (rien n'a été compilé ni vu à l'écran)
- Compilation de toutes les vues et des macros `@Observable`.
- VoiceOver : ordre de lecture, annonces d'état, bulles et cartes ; Dynamic Type jusqu'aux plus grandes tailles ;
  « Réduire les animations » ; cibles ≥ 44 pt (conçues ainsi, non mesurées).
- Contraste de la charte par défaut, mode sombre.
- Info.plist : `AVEEndpoint`, `AVEAllowInsecureLocal`, `NSMicrophoneUsageDescription`.
