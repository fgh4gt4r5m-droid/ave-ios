# Audio : ce qui est testé, ce qui exige un iPhone

## Architecture (Core/Audio, module AVEKit)

| Fichier | Rôle | Testable sans matériel |
|---|---|---|
| `AVEAudio`, `PCMFramer`, `AudioLevel` | format 16 kHz/20 ms, découpage en trames, niveaux | oui |
| `VoiceActivityDetector`, `PreRollBuffer` | détection de parole (le client signale `end_of_speech`), pré-roll 200 ms | oui |
| `BargeInStateMachine` | écoute / réflexion / parole / interrompu → actions (purge, interrupt, end_of_speech) | oui |
| `PlaybackPrimer` | amorçage ~100 ms, purge | oui |
| `AudioSessionManager` | `.playAndRecord` + `.voiceChat`, interruptions, routes | non (iOS) |
| `VoiceEngine` | un seul `AVAudioEngine` + voice processing (annulation d'écho) | non (iOS) |
| `MicCapture` | tap (copie seule) → `AVAudioConverter` Int16/16 kHz/mono → trames de 20 ms | non (iOS) |
| `TTSPlayer` | `AVAudioPlayerNode`, amorçage, purge instantanée (`node.stop()`) | non (iOS) |

Les quatre derniers sont sous `#if os(iOS)` : ils ne sont compilés que dans la cible iOS.

## À valider sur un iPhone réel (rien de ceci n'a pu l'être)

1. **Écho** : sur haut-parleur, l'assistant ne doit pas se déclencher lui-même. Régler `assistantSpeakingMultiplier` et `absoluteThreshold` (valeurs actuelles = points de départ, non mesurés).
2. **Barge-in** : délai entre la voix de l'utilisateur et le silence du haut-parleur (cible : un ou deux tampons audio).
3. **Voice processing + moteur partagé** : formats réellement renvoyés par `inputNode` (mono ? 16 kHz ? 48 kHz ?) ; le convertisseur gère un changement de fréquence mais pas testé.
4. **Bluetooth (HFP)** : bascule de route en cours de conversation, fréquence 8/16 kHz, reprise après `AVAudioEngineConfigurationChange`.
5. **Interruptions** : appel entrant, Siri, alarme ; reprise du moteur après `interruptionEnded`.
6. **Autorisation micro** : ajouter `NSMicrophoneUsageDescription` à l'Info.plist de la cible (texte honnête, en français).
7. **Fond (étape 5)** : `UIBackgroundModes = audio` et comportement écran verrouillé.

## Limites connues
- Le niveau de lecture de l'orbe est calculé au moment de la programmation du chunk, donc en avance d'environ la durée d'amorçage.
- Pas de ré-amorçage automatique après une sous-alimentation (gigue réseau en 3G).
- Le callback du tap alloue un tableau (copie) : acceptable en pratique, pas temps réel strict.
- `.allowBluetooth` est renommé `.allowBluetoothHFP` dans le SDK iOS 26 : avertissement de dépréciation possible.
