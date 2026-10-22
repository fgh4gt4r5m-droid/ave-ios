# Passation : reprendre le projet AVE en local

Rédigée le 2026-10-22 par la session cloud « African Voice Engine iOS app ». **Lire ce fichier, puis `CLAUDE.md`** (règles et guide du moteur). Ce qui n'a pas été vérifié est écrit comme tel.

## 1. Le produit
**AVE (African Voice Engine)** : moteur vocal conversationnel multimodal (voix + texte) pour les langues africaines, vendu en B2B (clés d'API depuis une console) et consommé par une **app grand public** (type ChatGPT/Claude) et par les apps WoYo et TaGa du propriétaire. Aujourd'hui côté moteur : seul le **français** a un ASR (Whisper générique, non mesuré) ; la voix renvoyée est un **son de test** (sinusoïde) et le dialogue un **écho** (aucun vrai TTS ni LLM). L'app ne doit jamais laisser croire le contraire.

## 2. Les trois dépôts (tous privés, `fgh4gt4r5m-droid/…`)
| Dépôt | Contenu | Où en est-on |
|---|---|---|
| `african-voice-engine` | moteur Python (autre session cloud « African Voice Engine architecture ») + **contrat partagé** `contrat/` | `main` @ `c2dadfb` contient déjà alignement, apprentissage, effacement par sujet. **PR #3** (branche `ios-client-steps-1-2`) : n'apporte QUE `contrat/` (CONTRAT.md + vectors.json). Pas encore fusionnée. |
| `ave-ios` (ce dépôt) | app iOS (package SwiftPM + XcodeGen + Codemagic) | `main` @ `154f25a` |
| `ave-accounts` | service de comptes (Python/FastAPI) | `main` @ `44621fa` ; **`scripts/e2e_engine.py` ajouté, à committer** (voir §7) |

**Règles de périmètre données par le propriétaire** : ne JAMAIS modifier le code du moteur (autre session) ni les apps/backends WoYo et TaGa (autres sessions). On ne touche qu'à `ave-ios`, `ave-accounts` et `contrat/` (dans `african-voice-engine`). Tout changement de protocole : moteur d'abord (son `PROTOCOL.md` + `protocol.ts`), puis `contrat/`, puis l'app.

## 3. État réel (honnêteté)
- **Service de comptes : exécuté et testé.** 77 tests Python verts ; essai de bout en bout 12/12 contre le moteur `main` (voir §7). Non éprouvés : Sign in with Apple (jamais appelé contre `appleid.apple.com`), App Attest (chaîne de certificats synthétique, pas de vraie attestation), envoi réel des SMS/WhatsApp (seul un adaptateur webhook générique).
- **App iOS : ~7 000 lignes de Swift, 166 `@Test` (Swift Testing), JAMAIS compilées avant Codemagic.** Premier build Codemagic (`swift test`, étape 3) : une erreur de compilation (clé `version` en double dans `ClientMessage.Keys`), corrigée dans `93b5cef`. Le compilateur s'arrête au premier module en échec : **`AVEKit`, les vues, la Live Activity et les tests n'ont encore jamais été compilés.** Attendre d'autres erreurs.
- Les formes des messages ont été vérifiées contre le VRAI moteur (script Python rejouant hello/text/set_language) : trouvé et corrigé `ready.grace_s` flottant (`30.0`).

## 4. Prochaine étape immédiate : la boucle Codemagic
Le propriétaire **n'a pas de Mac** (Codemagic uniquement ; sans doute Windows). Le Swift ne peut donc être compilé que sur Codemagic.
1. Codemagic → application `ave-ios` → branche `main` → workflow **`ave-ci`** (nom affiché « AVE - compilation et tests »). Jamais `ave-testflight` (non configuré).
2. Étapes : `swift test` (macOS, logique pure) → XcodeGen → compilation iOS simulateur sans signature (compile tout le code iOS) → tests simulateur.
3. Récupérer le journal de l'étape en échec (ou `build.log`/`test.log` des artefacts), corriger, pousser, relancer. **Plusieurs allers-retours à prévoir.**
4. Amélioration possible : appeler l'API REST de Codemagic avec un jeton du propriétaire pour lancer le build et lire les journaux sans copier-coller (jeton à garder hors dépôt).

Zones à risque connues (jamais compilées) : concurrence stricte Swift 6 (`@Observable`/`@MainActor` dans `SessionCoordinator`), `AVAudioEngine`/voice processing, `ActivityKit`, `SignInWithAppleButton`, `Package.swift` (deux cibles qui partagent le dossier `AVE` avec des listes `sources` disjointes), `project.yml` (jamais passé dans XcodeGen ; en particulier `test: targets: - package: AVEPackage/AVETests`), macros Swift Testing.

## 5. Décisions produit déjà prises (ne pas les rouvrir sans le propriétaire)
- Trois dépôts séparés ; le contrat commun reste dans `african-voice-engine`.
- **Connexion** : service de comptes **dédié** (pas WoYo/TaGa) ; téléphone + code (SMS/WhatsApp), Sign in with Apple, **invité** (App Attest). WoYo/TaGa n'utilisent pas ce service : leur backend appelle `POST /v1/token` du moteur.
- **Apprentissage avec consentement** : réservé aux **comptes identifiés** (pas de notice pour les invités, option 1) ; « Non » par défaut ; refus mémorisé ; notice **française seulement** (aucune traduction locale inventée ; à faire par des natifs + relecture juridique) ; lue à voix haute avec la voix du système.
- `hello.vad:"client"` (le serveur a un VAD serveur par défaut) : l'app ne transmet le micro que pendant la parole (3G).
- Confirmation explicite des `action` quand `confirm:true`.
- Logo retenu : proposition 1 (carte de l'Afrique + barres de son) ; palette relevée (`AVEPalette`), contrastes WCAG testés. Icône 1024 px et logos vectoriels **à fournir par un designer** (`ASSETS.md`).

## 6. Questions ouvertes (à trancher par le propriétaire)
- Fournisseur d'envoi des codes (SMS/WhatsApp) ; coût et fiabilité dans la région.
- Vraies adresses de production (`api…`, `accounts…`) : `Config/Release.xcconfig` contient des placeholders `.example`. Identifiants d'app : `fr.ave.app` et `fr.ave.app.liveactivity` sont une **hypothèse**.
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
Si le script `ave-accounts/scripts/e2e_engine.py` n'est pas dans `main`, il est dans la copie de travail de la session cloud : le recréer ou demander au propriétaire. Tests du moteur : 20 échecs constatés dans l'environnement cloud, tous liés à Whisper/LLM (dépendances optionnelles absentes), **non investigués** (hors périmètre).

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
