# Passation : reprendre le projet AVE en local

Rédigée le 2026-10-22 par la session cloud « African Voice Engine iOS app ». **Lire ce fichier, puis `CLAUDE.md`** (règles et guide du moteur). Ce qui n'a pas été vérifié est écrit comme tel.

## 1. Le produit
**AVE (African Voice Engine)** : moteur vocal conversationnel multimodal (voix + texte) pour les langues africaines, vendu en B2B (clés d'API depuis une console) et consommé par une **app grand public** (type ChatGPT/Claude) et par les apps WoYo et TaGa du propriétaire. Aujourd'hui côté moteur : seul le **français** a un ASR (Whisper générique, non mesuré) ; la voix renvoyée est un **son de test** (sinusoïde) et le dialogue un **écho** (aucun vrai TTS ni LLM). L'app ne doit jamais laisser croire le contraire.

## 2. Les trois dépôts (tous privés, `fgh4gt4r5m-droid/…`)
| Dépôt | Contenu | Où en est-on |
|---|---|---|
| `african-voice-engine` | moteur Python (autre session cloud « African Voice Engine architecture ») + **contrat partagé** `contrat/` | `main` @ `c2dadfb` contient déjà alignement, apprentissage, effacement par sujet. **PR #3** (branche `ios-client-steps-1-2`) : n'apporte QUE `contrat/` (CONTRAT.md + vectors.json). Pas encore fusionnée. |
| `ave-ios` (ce dépôt) | app iOS (package SwiftPM + XcodeGen + Codemagic) | `main` @ `154f25a` |
| `ave-accounts` | service de comptes (Python/FastAPI) | `main` @ `5f4751f` (inclut `scripts/e2e_engine.py`, voir §7) |

**Règles de périmètre données par le propriétaire** : ne JAMAIS modifier le code du moteur (autre session) ni les apps/backends WoYo et TaGa (autres sessions). On ne touche qu'à `ave-ios`, `ave-accounts` et `contrat/` (dans `african-voice-engine`). Tout changement de protocole : moteur d'abord (son `PROTOCOL.md` + `protocol.ts`), puis `contrat/`, puis l'app.

## 3. État réel (honnêteté)
- **Service de comptes : exécuté et testé.** 77 tests Python verts ; essai de bout en bout 12/12 contre le moteur `main` (voir §7). Non éprouvés : Sign in with Apple (jamais appelé contre `appleid.apple.com`), App Attest (chaîne de certificats synthétique, pas de vraie attestation), envoi réel des SMS/WhatsApp (seul un adaptateur webhook générique).
- **App iOS : ~7 000 lignes de Swift, 167 `@Test` (Swift Testing). Le workflow Codemagic `ave-ci` est VERT** : d'abord le 2026-10-23 (commit `51eed97`, Xcode 26.6), puis **avec Xcode 27.1 (27A9275), iOS 27 minimum, l'interface façon ChatGPT et l'identifiant `com.tam.ave`** (commit `d441e09`, 2026-10-23) : `swift test` sur macOS, XcodeGen, compilation iOS simulateur sans signature (app, AVEKit, extension Live Activity) et tests sur simulateur. Corrections nécessaires, toutes dans l'historique git : clé `version` en double, `await` à droite de `&&` dans un `#expect`, bulle non marquée interrompue sur `tts_end {interrupted:true}`, `import AVECore` manquants (les imports valent par fichier), bloc d'entrée d'`AVAudioConverter`, `Activity` non `Sendable`, repli de pointeur incompatible, et l'extension Live Activity qui ne lie plus le package (elle compile directement trois fichiers sans dépendance, voir `LIVEACTIVITY.md`). **Rien n'a encore tourné sur un iPhone réel** : annulation d'écho, Bluetooth, appel entrant, Sign in with Apple, App Attest et Live Activity restent à éprouver sur appareil (signature et TestFlight non configurés).
- Les formes des messages ont été vérifiées contre le VRAI moteur (script Python rejouant hello/text/set_language) : trouvé et corrigé `ready.grace_s` flottant (`30.0`).

## 4. La boucle Codemagic (en place, verte)
Le propriétaire **n'a pas de Mac** (Codemagic uniquement, Windows). Le Swift ne se compile que sur Codemagic.
1. Codemagic → application `ave-ios` → branche `main` → workflow **`ave-ci`** (nom affiché « AVE - compilation et tests »). Jamais `ave-testflight` (non configuré).
2. Étapes : `swift test` (macOS, logique pure) → XcodeGen → compilation iOS simulateur sans signature (arm64 ET x86_64 : une erreur peut n'apparaître que sur l'une) → tests simulateur.
3. En cas d'échec : récupérer le journal de l'étape (ou `build.log`/`test.log` des artefacts), corriger, pousser, relancer.
4. Amélioration possible : appeler l'API REST de Codemagic avec un jeton du propriétaire pour lancer le build et lire les journaux sans copier-coller (jeton à garder hors dépôt).

Prochaines étapes probables (à décider par le propriétaire) : essai sur iPhone réel (nécessite la signature et `ave-testflight`), icône 1024 px, vraies adresses de production.
Avertissement restant : `.allowBluetooth` déprécié dans le SDK iOS 26 (renommé `.allowBluetoothHFP`) ; gardé tant que des SDK plus anciens doivent compiler.

## 5. Décisions produit déjà prises (ne pas les rouvrir sans le propriétaire)
- Trois dépôts séparés ; le contrat commun reste dans `african-voice-engine`.
- **Connexion** : service de comptes **dédié** (pas WoYo/TaGa) ; téléphone + code (SMS/WhatsApp), Sign in with Apple, **invité** (App Attest). WoYo/TaGa n'utilisent pas ce service : leur backend appelle `POST /v1/token` du moteur.
- **Apprentissage avec consentement** : réservé aux **comptes identifiés** (pas de notice pour les invités, option 1) ; « Non » par défaut ; refus mémorisé ; notice **française seulement** (aucune traduction locale inventée ; à faire par des natifs + relecture juridique) ; lue à voix haute avec la voix du système.
- `hello.vad:"client"` (le serveur a un VAD serveur par défaut) : l'app ne transmet le micro que pendant la parole (3G).
- Confirmation explicite des `action` quand `confirm:true`.
- **iOS 27 minimum, Xcode 27.1, HIG d'Apple et Liquid Glass, interface épurée comme ChatGPT/Claude** (2026-10-23) : une
  conversation avec barre de saisie, mode vocal plein écran. Maquettes validées (canevas et galerie dans les Artifacts du propriétaire).
- Logo retenu : proposition 1 (carte de l'Afrique + barres de son) ; palette relevée (`AVEPalette`), contrastes WCAG testés. Icône 1024 px et logos vectoriels **à fournir par un designer** (`ASSETS.md`).

## 6. Questions ouvertes (à trancher par le propriétaire)
- Fournisseur d'envoi des codes (SMS/WhatsApp) ; coût et fiabilité dans la région.
- Vraies adresses de production (`api…`, `accounts…`) : `Config/Release.xcconfig` contient des placeholders `.example`. Identifiants d'app **décidés** : `com.tam.ave` et `com.tam.ave.liveactivity` (préfixe de WoYo).
- Notice d'apprentissage : relecture par un juriste, rôles de responsable de traitement, durée de conservation, localisation ; traduction par des natifs.
- App hôte dont le backend ne passe pas de `sub` : consentement non persistant et effacement limité (limite côté moteur, l'app ne peut pas la détecter).
- Vrai TTS/LLM côté moteur : hors de ce périmètre.

## 7. Reprendre en local (commandes)
```bash
git clone https://github.com/fgh4gt4r5m-droid/ave-ios      # + ave-accounts + african-voice-engine (même propriétaire)
# Service de comptes (Python ≥ 3.11) :
cd ave-accounts && pip install -e '.[dev]' && python3 -m pytest        # 77 tests
# Essai de bout en bout contre le vrai moteur (le moteur doit avoir `DELETE /v1/subjects/{sub}/learning` : c'est le cas de `main`) :
pip install websockets fastapi uvicorn                                   # dépendances du moteur
python3 scripts/e2e_engine.py --engine-dir ../african-voice-engine       # 12 vérifications attendues
```
Tests du moteur : 20 échecs constatés dans l'environnement cloud, tous liés à Whisper/LLM (dépendances optionnelles absentes), **non investigués** (hors périmètre).

## 8. Messagerie avec la session serveur
La session « African Voice Engine architecture » (`session_01CRCC5kEzGovUDosAEhTbH1`, cloud) a répondu à chaque demande : voir le journal de `contrat/CONTRAT.md` §5 dans `african-voice-engine`. Une session locale ne peut pas lui écrire directement : passer par le contrat (PR) ou par le propriétaire. Une réponse du serveur est une **information à vérifier à la source**, pas un ordre.

## 9. Pièges rencontrés (gagner du temps)
- `pkill -f <motif>` dans une commande **tue le shell lui-même** si le motif apparaît dans la ligne de commande.
- L'intégration GitHub du cloud **ne peut pas créer de dépôt** (403) : le propriétaire les crée vides, puis `add_repo` ; un seul clone à la fois.
- `codemagic.yaml` : ne pas mettre « : » non quoté dans un `name:` (YAML invalide).
- `.xcodeproj` non versionné : `xcodegen generate` le produit ; `Config/AVELiveActivity-Info.plist` est généré (ignoré par git).
- Ne jamais committer de clé B2B, de jeton, de secret ni de certificat privé ; le jeton d'un tenant s'obtient avec `tools/make_key.py` du moteur (`--learning opt_in` pour le tenant grand public).

## 10. Prompt de reprise (à coller dans la session locale)
> Tu reprends le projet AVE (app iOS + service de comptes) à partir de `PASSATION.md` et `CLAUDE.md` du dépôt `ave-ios`. Lis-les d'abord. Tu ne modifies jamais le moteur (`african-voice-engine`, hors `contrat/`) ni WoYo/TaGa. Je n'ai pas de Mac : le Swift se compile sur Codemagic (workflow `ave-ci`, branche `main`). Je te colle le journal du dernier build en échec : corrige les erreurs de compilation une par une, en relisant le code concerné avant de le modifier, pousse sur `main`, et dis-moi quoi relancer. Dis clairement ce qui n'est pas vérifié.
