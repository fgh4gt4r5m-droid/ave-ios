# Écrans (étape 4) : décisions et limites

## Structure
- `Features/VoiceAssistant/SessionCoordinator` : une session, deux modes. Relie client WebSocket, audio, machine du
  barge-in, VAD et conversation. Basculer voix ↔ texte coupe le micro, jamais la session.
- `Features/Chat` : `ChatTranscript` (pur, testé), `ChatView`, bulles, cartes d'action.
- `Features/VoiceAssistant/FloatingVoiceOrbView` + `OrbState` (pur, testé).
- `Features/Shared` : `LanguageCatalog`/`LanguagePicker`, `UserMessages`, `AVETheme` (charte remplaçable par WoYo/TaGa).
- Les vues SwiftUI sont sous `#if os(iOS)` ; la logique est testable partout.

## Décisions à connaître
1. **Confirmation des actions** : `action.confirm == true` ⇒ carte « Confirmer / Refuser » ; la voix seule ne valide jamais. `confirm == false`
   ⇒ l'action est rendue tout de suite à l'app hôte (`onAction`). Un `confirm` absent est traité comme `true`. Le serveur n'attend aucune réponse.
2. **Texte** : `text` envoyé tel quel (après `trim`, 1–4000 caractères). La bulle de l'utilisateur apparaît à l'écho `transcript {source:"text"}`, comme pour
   la voix : l'app n'en fabrique pas. Hors ligne, le message n'est pas perdu en silence : l'utilisateur est prévenu. Envoyer du texte pendant que l'assistant
   parle purge la lecture localement (le serveur coupe seul).
3. **Texte de la réponse** : bulle construite phrase par phrase par `utterance_id` (`reply_text`). Sans `reply_text`, bulle « Réponse vocale ».
4. **Réécouter** : rejoue l'audio gardé en mémoire (4 Mo max, plus anciens évincés). `speak` existe côté client mais n'a pas d'écran.
5. **Langues** : liste du serveur (`ready.languages`, disponibilité réelle) ; repli codé en dur si absente. Les langues indisponibles sont sélectionnables
   mais signalées. Aucune promesse de latence.
6. **`vad:"client"`** : voir `contrat/CONTRAT.md` §3 bis. **Un seul flux d'événements** côté client (état, ready, protocole, audio) : l'ordre est garanti.
7. **Honnêteté** : la voix reçue est aujourd'hui un son de test et le dialogue un écho (dit par le serveur). L'UI ne doit pas laisser croire le contraire.

## À valider dans Xcode / sur iPhone (rien n'a été compilé ni vu à l'écran)
- Compilation de toutes les vues et des macros `@Observable`.
- VoiceOver : ordre de lecture, annonces d'état, bulles et cartes ; Dynamic Type jusqu'aux plus grandes tailles ;
  « Réduire les animations » ; cibles ≥ 44 pt (conçues ainsi, non mesurées).
- Contraste de la charte par défaut, mode sombre.
- Info.plist : `AVEEndpoint`, `AVEAllowInsecureLocal`, `NSMicrophoneUsageDescription`.
