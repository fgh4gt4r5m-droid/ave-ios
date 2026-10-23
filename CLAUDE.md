# CLAUDE.md — AVE iOS (application native multimodale)

Guide pour Claude Code et tout développeur de l'app iOS **African Voice Engine**. À copier à la racine du
dépôt/dossier iOS. Langue du code, des commentaires, des commits et de la doc : **français** ; les commentaires
expliquent *pourquoi* (décisions écartées, mesures). Le serveur et son protocole vivent dans le dépôt
`african-voice-engine` (`docs/PROTOCOL.md` fait foi) ; **cette app n'est qu'un client**.

## Ce qu'on construit

Une vitrine multimodale (voix ET texte) de classe ChatGPT/Gemini/Claude Mobile pour converser dans les langues
africaines. Cibles de terrain : iPhone d'entrée de gamme récent, **3G/4G instable**, utilisateurs dont une grande part
**ne lit pas couramment** → l'interface est d'abord vocale et iconographique, le texte est un complément.

⚠️ **Honnêteté sur les capacités (à refléter dans l'UI, pas à masquer)** :
- Aujourd'hui, côté serveur, seul le **français** a un moteur (Whisper générique) ; soussou, poular, malinké,
  wolof, lingala, swahili… sont `planned` et répondent `turn_error language_unavailable`. L'app doit dire clairement
  « langue pas encore disponible », jamais simuler.
- La latence cible < 800 ms **n'est pas atteinte hors wifi** (mesures du banc serveur : ~760 ms wifi, ~1,1 s en 3G
  simulée, avec ASR simulé). Ne jamais promettre « ultra-faible latence » dans l'UI ; la mesurer (voir Tests).

## Différences volontaires avec le brief initial (le protocole réel prime)

| Brief initial | Réalité du protocole AVE v1 |
|---|---|
| « Chunks audio binaires » bruts | Chaque trame binaire = **5 octets d'en-tête** (`kind` u8 + `seq` u32 big-endian) + PCM16 |
| Reconnexion de `URLSessionWebSocketTask` | **N'existe pas** : à écrire (backoff + reprise de session par `session_id`/`last_seq`) |
| Capture « PCM 16 kHz » directement | Le micro iOS fournit du 44,1/48 kHz Float32 : **conversion** obligatoire (`AVAudioConverter`) |
| Barge-in = couper la lecture | Le serveur détecte la parole (`speech_start`) ET coupe sa synthèse ; le client doit **aussi** vider sa file locale et ignorer l'audio en vol |
| Bouton « lecture vocale (TTS) à la demande » | **Pas d'API serveur « lis ce texte »** : le TTS n'existe que dans un tour. v1 : rejouer l'audio mis en cache de la réponse ; « lire n'importe quel texte » = **dépendance serveur** (message `speak`, à créer) |
| Liste de langues dans l'app | Pas d'endpoint de statut des langues : **dépendance serveur** (`GET /v1/languages`, à créer). En attendant, liste codée avec statut `planned` sauf `fra` |
| Cartes/boutons d'action « JSON » | Ce sont les événements `action {name,args,confirm}` ; `confirm:true` impose une confirmation explicite |

## Pile et règles

- **iOS 27 minimum, Xcode 27.1** (décision du propriétaire, 2026-10-23 ; **Codemagic compile avec 27.0** depuis le même jour, accord du propriétaire : plus de machine 27.1 offerte aux comptes gratuits, voir `codemagic.yaml`), Swift 6 (concurrence stricte), SwiftUI + `@Observable`,
  async/await, `AsyncStream`. **Pas de Combine.** Aucune branche `#available` : les composants les plus récents partout.
- **Exigence du propriétaire : l'app native vise l'excellence et suit le HIG d'Apple.** Composants système d'abord (Liquid Glass :
  `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass/.glassProminent)`, barres d'outils système, `safeAreaBar`, feuilles
  natives) ; interface épurée comme ChatGPT, Claude ou Gemini sur iOS. Le verre est pour la couche de navigation et les contrôles,
  jamais pour le contenu (bulles, cartes). Les apps Flutter (WoYo, TaGa) peuvent être moins standard ; pas celle-ci.
- Clean Architecture / MVVM : `Domain` (types purs, sans UIKit/AVFoundation) ← `Core` (réseau, audio) ← `Features` (vues + view models).
- `@MainActor` uniquement pour l'état d'UI. Réseau et audio dans des **acteurs dédiés** ; aucun `DispatchQueue` sauf là où
  AVFoundation l'impose (callbacks du tap audio : ne rien allouer ni verrouiller dedans, pousser vers un `AsyncStream`).
- Pas de `!` (force unwrap/try). Logs via `os.Logger`, **jamais** de jeton, de texte utilisateur ni d'audio dans les journaux.
- Dépendances tierces : aucune sans décision écrite (mêmes contraintes de souveraineté/licence que le serveur).

## Arborescence

```
AVE/
  App/                      AVEApp.swift, injection des dépendances, configuration (URL serveur, tenant de démo)
  Domain/                   Message, Utterance, ServerEvent/ClientMessage (Codable), LanguageCode, ActionCard
  Core/
    Network/                AVEProtocol.swift (en-tête binaire, encodage/décodage, JSON)
                            WebSocketTransport.swift (protocole + implémentation URLSessionWebSocketTask)
                            AVEWebSocketClient.swift (acteur : handshake, seq, reconnexion, reprise, file micro)
    Audio/                  AudioSessionManager, MicCapture (AVAudioEngine → PCM16 16 kHz 20 ms),
                            TTSPlayer (AVAudioPlayerNode + file + purge), AudioLevelMeter
    Storage/                KeychainStore (jeton), cache d'audio par utterance_id
  Features/
    Chat/                   ChatView, ChatViewModel, MessageBubble, ActionCardView
    VoiceAssistant/         FloatingVoiceOrbView, VoiceViewModel
    Shared/                 SessionCoordinator (une session, deux modes), LanguagePicker
  LiveActivity/             extension Widget : ActivityAttributes + Dynamic Island
AVETests/                   vecteurs du protocole, client avec faux transport, machine d'états audio
```

## Contrat réseau (extraits ; la source de vérité est `docs/PROTOCOL.md` + `sdk/ts/src/protocol.ts`)

Endpoint `wss://…/v1/stream`. Premier message client : `hello` (JSON texte).
```json
{"type":"hello","version":1,"codec":"pcm16","lang":"auto","vad":"server",
 "output":["audio","text","actions"],"sample_rate":16000,"token":"<jeton>",
 "session_id":"<si reprise>","last_seq":64}
```
Serveur → `ready {session_id, resumed, last_mic_seq, seq}` ; en cas de reprise, rejeu des trames `seq > last_seq` puis `replayed`.

**Trames binaires** (octet 0 = `kind` : `0x01` micro client→serveur, `0x02` TTS serveur→client ; octets 1-4 = `seq` big-endian ; reste = PCM16 mono little-endian).
Vecteurs de référence (à tester tels quels, produits par le serveur) :
```
micro  seq=1   payload 01 00 02 00  →  01 00000001 01000200      = 010000000101000200
micro  seq=258 payload vide         →  01 00000102               = 0100000102
tts    seq=64  payload ff 7f        →  02 00000040 ff7f          = 0200000040ff7f
```
Le `seq` micro est propre au client (1, 2, 3…) ; le `seq` serveur est unique pour l'audio TTS ET les événements JSON
(sauf `ready`, `replayed`, `pong`, `error`, `speech_start/end`, `language_set`).

**Client → serveur** : `text {text}` (1–4000 car.), `end_of_speech`, `set_language {lang}`, `interrupt`, `ping`, `bye`.
**Serveur → client** : `transcript`, `reply_text {utterance_id,text,lang}` (une phrase à la fois, AVANT son audio), `action`,
`tts_start`, `tts_end {interrupted}`, `turn_end` (toujours), `turn_error {code}`, `interrupted`, `speech_start/speech_end`, `error {code}`.
Erreurs **définitives** (ne pas reconnecter) : `unauthorized`, `too_many_sessions`, `bad_version`, `unsupported_codec`.

Règles du client (`AVEWebSocketClient`) :
1. Mémoriser `lastSeq` (max des `seq` reçus) et `session_id` ; à la reconnexion renvoyer `hello` avec les deux.
2. **File micro** hors ligne bornée (≈ 500 trames de 20 ms) ; après `ready`, renvoyer celles dont `seq > last_mic_seq`.
3. Backoff 250 ms → 5 s ; `ping` applicatif toutes les ~15 s (les coupures silencieuses mobiles ne sont pas signalées vite).
4. Un `receive()` en boucle dans une `Task` ; messages `.string` = JSON, `.data` = trame audio. Toute erreur de décodage JSON est
   journalisée et ignorée (un événement inconnu ne doit jamais tuer la session — le protocole évoluera).
5. Opus : **non pris en charge côté iOS pour l'instant** (`codec: "pcm16"`). L'encodage Opus via AudioToolbox n'est pas validé ;
   à étudier plus tard, le gain visé est le débit en 3G (÷14), pas la latence.

## Pipeline audio

- `AVAudioSession` : catégorie `.playAndRecord`, mode `.voiceChat`, options `.defaultToSpeaker`, `.allowBluetooth`. Gérer interruptions
  (appel, Siri), changements de route (casque), et `UIBackgroundModes: audio` seulement si la session doit survivre en arrière-plan.
- **Annulation d'écho obligatoire** : activer le traitement vocal d'Apple (`inputNode.setVoiceProcessingEnabled(true)`) — sinon le micro
  réentend la synthèse, le serveur y voit de la parole (`speech_start`) et le barge-in se déclenche tout seul. À valider **sur appareil
  réel** (le simulateur n'est pas représentatif).
- Capture : `installTap` sur l'`inputNode`, `AVAudioConverter` vers **Int16 / 16 kHz / mono**, découpage en trames de 20 ms (320 échantillons =
  640 octets), envoi par `AsyncStream` → client WebSocket. Rien d'autre dans le callback du tap.
- Lecture : `AVAudioPlayerNode` ; convertir l'Int16 reçu au format du moteur ; petite file d'amorçage (tampon de gigue, valeur de départ ~80 ms,
  **à régler par mesure**). Les trames TTS arrivent par rafales : ne pas planifier chaque trame comme un buffer isolé sans file.
- **Barge-in côté client** (déclencheurs : `speech_start`, saisie de texte, bouton, geste) : `playerNode.stop()` + purge de la file, passer en état
  « interrompu », **ignorer les trames TTS jusqu'au prochain `tts_start`**, envoyer `interrupt` (sauf si l'événement vient déjà d'un envoi de `text`).
- Cache audio par `utterance_id` (pour « réécouter ») ; purge à la fin de session.

## Modes et écrans

- **SessionCoordinator** : une seule session WebSocket ; deux présentations (Chat / Voix) sur le même flux — bascule sans rompre la session.
  Voix → l'événement `transcript` s'inscrit comme bulle utilisateur dans le Chat ; l'utilisateur peut ensuite répondre par `text`.
- **Structure (décision du 2026-10-23)** : comme ChatGPT ou Claude, un seul écran de conversation avec une barre de saisie
  Liquid Glass en bas (texte, envoi, bouton « mode vocal ») ; le **mode vocal** s'ouvre en plein écran (`VoiceModeView`) sur la
  même session. La conversation s'ouvre en mode texte. Révisé le 2026-10-23 après essai sur iPhone (« trop voix d'abord ») :
  couleurs du système (clair/sombre), accueil sobre, bouton rond unique dans la barre de saisie, nouvelle conversation
  (un client = une session), voir `ECRANS.md`.
- **ChatView** : bulles ; la réponse assistant se construit phrase par phrase (`reply_text` par `utterance_id`) ; `action` → `ActionCardView`
  (boutons). **`confirm:true` = bouton de confirmation explicite avant de rendre l'action à l'application hôte** ; la voix seule ne valide jamais.
  `turn_error` → message clair et traduit, pas de silence.
- **FloatingVoiceOrbView** : orbe animé par le niveau RMS du micro (écoute) et de la lecture (parole), état distinct pour « réfléchit ».
  Respecter « Réduire les animations » ; VoiceOver sur chaque état ; cibles tactiles ≥ 44 pt ; Dynamic Type dans le Chat.
- **Dynamic Island / ActivityKit** : Live Activity avec états `écoute | réflexion | parole | interrompu`, démarrée app au premier plan,
  mises à jour locales (pas de push en v1), **terminée à la fin de session**. Elle n'ouvre pas le micro en arrière-plan : c'est
  `UIBackgroundModes: audio` + la session audio qui le permettent, et l'indicateur micro d'iOS reste visible.
- Interface localisée (`String Catalog`), français d'abord ; peu de texte, icônes explicites.

## Sécurité et données

- Transport `wss://` uniquement (ATS). Exception de développement `NSAllowsLocalNetworking` pour tester contre un serveur sur le réseau local, jamais en release.
- Le jeton d'API est lu depuis le **Keychain**, jamais dans l'URL, jamais journalisé.
- ⚠️ **Une clé B2B embarquée dans une app publique est extractible.** Pour la vitrine : tenant de démonstration à quotas et langues restreints, jeton
  révocable. Pour une diffusion large : il faut un échange de jeton côté serveur (**non construit**). Ne pas publier sur l'App Store avec une clé de production.
- `NSMicrophoneUsageDescription` en français, explicite ; manifeste de confidentialité renseigné. Aucun enregistrement audio persistant sans consentement.

## Tests

- Vecteurs d'octets du protocole ci-dessus, encodage/décodage de chaque `ClientMessage`/`ServerEvent` (y compris événement inconnu → ignoré).
- `AVEWebSocketClient` testé avec un **faux transport** (pas de réseau) : reconnexion, reprise `last_seq`, renvoi de la file micro, erreurs définitives, doublons.
- Machine d'états audio/barge-in testée sans matériel (le matériel est derrière des protocoles).
- Manuel sur **iPhone réel** : écho/AEC, bascule Bluetooth, appel entrant, mode avion → retour, 3G simulée (Network Link Conditioner).
- Test de bout en bout contre le serveur de dev : `AVE_AUTH=none python3 -m ave` sur le Mac, puis `ws://<IP du Mac>:8787/v1/stream`.

## Règles de travail

- Tout changement de protocole d'abord dans `african-voice-engine` (`docs/PROTOCOL.md` + `protocol.ts` + test), puis ici.
- Pas de fonctionnalité simulée présentée comme réelle (langues, latence, traduction) ; dire ce qui n'est pas testé.
- Mesurer avant d'optimiser (Instruments, signposts `os_signpost` sur : fin de parole → 1re trame audio reçue).

## Dépendances serveur à créer (hors de ce dépôt)

1. `GET /v1/languages` : langues, région, statut (`planned|experimental|production`) pour le sélecteur.
2. Message `speak {text, lang}` : synthèse à la demande (bouton « lire »), sans passer par le LLM.
3. Échange de jeton court (`POST /v1/token`) pour ne pas embarquer une clé durable dans l'app.
4. **Pièces jointes** : FAIT côté moteur (E16, E17, `contrat/` fusionné) et codé dans l'app le 2026-10-23 (`ECRANS.md`,
   « Fichiers, documents et images ») ; non compilé à la date de l'écriture, rien n'a tourné sur iPhone.
5. **Reprise d'une conversation avec son contexte** : FAIT (D9, `context`, moteur `main` @ `d14a002`), codé dans l'app le
   2026-10-23 (`ConversationContext`).
6. **Réponses écrites au fil de l'eau** : FAIT (D7, `text_delta` / `reply_delta`), codé dans l'app le 2026-10-23. Reste :
   **choix de la voix**.
7. **Génération de documents ou d'images** par l'assistant : outils côté moteur (appels d'outils du LLM), jamais dans l'app.
   Décision du propriétaire (2026-10-23) : **modèle d'images libre HÉBERGÉ par TAM, sans appeler d'API tierce**.
   Pistes à licence permissive (à vérifier sur la fiche de chaque modèle) : Z-Image-Turbo, Qwen-Image, FLUX.1 [schnell]
   (Apache 2.0), HiDream (MIT). Documents : produits localement par le moteur (bibliothèques libres), sans modèle.

---

## État réel de l'app et écarts avec ce guide (mis à jour le 2026-10-22)

Ce guide vient du dépôt du moteur (`docs/ios/CLAUDE.md`) ; ce qui suit décrit ce qui a été construit ici. **Le Swift compile et ses tests passent sur Codemagic** (workflow `ave-ci` vert avec Xcode 27.1, iOS 27 minimum, le 2026-10-23 : macOS, simulateur iOS) ; le projet Xcode est décrit par `project.yml` (XcodeGen), voir `CODEMAGIC.md`. **Rien n'a encore tourné sur un iPhone réel** (audio, Sign in with Apple, App Attest, Live Activity : à éprouver sur appareil).

**Dépôts** : moteur + contrat partagé = `african-voice-engine` (dossier `contrat/`, registre des extensions, vecteurs d'octets, journal) ; service de comptes = `ave-accounts` ; cette app = `ave-ios`. Tout changement de protocole commence dans le moteur, puis dans `contrat/`, puis ici.

**Structure** : package SwiftPM à la racine. `AVECore` (Domain, Core/Network, Core/Storage, Core/Auth : Foundation seule) ; `AVEKit` (Core/Audio, Features, Kit : ce que WoYo et TaGa intègrent) ; l'app (`AVE/App`) et l'extension Live Activity (`AVE/LiveActivity`) iront dans des cibles Xcode (non créées). Détails : `ARCHITECTURE.md`, `AUDIO.md`, `ECRANS.md`, `LIVEACTIVITY.md`, `ASSETS.md`.

**Écarts volontaires** :
- `hello.vad:"client"` (et non `server`) : l'app détecte la parole et ne transmet le micro que pendant la parole (PCM16 en continu = 256 kbit/s, prohibitif en 3G ; Opus non pris en charge côté iOS). Le serveur l'accepte.
- Un seul flux d'événements côté client (état, `ready`, protocole, audio) pour garantir l'ordre `tts_start` → audio.
- Jeton asynchrone à chaque (re)connexion (`AVETokenProvider`) : l'app ne contient AUCUNE clé B2B ; le jeton court vient du service de comptes (`ave-accounts`) ou, pour WoYo/TaGa, de leur backend.
- Connexion : téléphone + code, Sign in with Apple, invité (App Attest). L'apprentissage avec consentement est réservé aux comptes identifiés (pas de notice pour les invités).

**Honnêteté** : la voix reçue du moteur est aujourd'hui un son de test et le dialogue un écho (dit par le moteur). La notice d'apprentissage n'existe qu'en français (aucune traduction locale inventée) et doit être relue par un juriste.
