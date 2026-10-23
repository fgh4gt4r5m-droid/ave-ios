# Écrans (étape 4) : décisions et limites

## Structure
- **Proposition 2 (validée le 2026-10-23)** — galerie : https://claude.ai/artifact/KVa5A58yaBPxPvL8TUNYrG
  - Premier lancement (`Features/Onboarding`) : promesse + choix de la langue avant la connexion.
  - Historique LOCAL (`Features/History`) : `FileConversationStore` (JSON par conversation, Application Support, protégé par
    iOS, exclu des sauvegardes), titre automatique, regroupement par date, recherche, renommer, supprimer, tout effacer.
    Rouvrir = réafficher ; l'assistant repart SANS mémoire (nouvelle session) et l'app le dit (`resumedWithoutMemory`).
  - Accueil : salutation (prénom facultatif, gardé sur l'iPhone) + 4 suggestions (débuts de phrase, ou mode vocal).
  - Réponses mises en forme (`MarkdownBlocks` pur et testé + `RichText`), actions copier / lire / partager / réessayer /
    avis, appui long = menu natif (copier, modifier ma question, lire, partager).
  - Hors connexion : `SessionCoordinator.pendingTexts`, bulles « en attente », envoi dans l'ordre au retour du réseau.
  - Mode vocal : sous-titres en direct, micro coupé (`setMicMuted`), interrompre, terminer.
  - Réglages (`Features/Settings`, remplace « Mon compte ») : prénom, langue, lecture auto (`autoPlayInTextMode`, l'audio
    reste gardé), sous-titres, vibrations, thème, historique, aide à l'amélioration, compte, version.
  - Raccourcis : App Intent « Parler à AVE » (Siri, Spotlight, Raccourcis, bouton Action). **Pas encore** : widget et
    commande du Centre de contrôle (extension, même intention) ; pièces jointes (protocole du moteur à prévoir d'abord).
- `Features/VoiceAssistant/SessionCoordinator` : une session, deux modes. Relie client WebSocket, audio, machine du
  barge-in, VAD et conversation. Basculer voix ↔ texte coupe le micro, jamais la session.
- **Standards ChatGPT / Claude / Gemini (2026-10-23, après essai sur iPhone)** : couleurs et fonds du SYSTÈME (clair et
  sombre ; la marque ne colore que l'accent, en variante assombrie sur fond clair), barre du haut = compte · « AVE + langue ⌄ »
  · nouvelle conversation, accueil = une question centrée, UNE barre de saisie dont le bouton rond est « mode vocal » champ
  vide et « envoyer » dès qu'on écrit, mention d'essai en petit sous la saisie, réponses : copier / réécouter / avis.
  Mode vocal : orbe, état, gros boutons ronds en bas (Interrompre, Terminer). Galerie des maquettes À JOUR (2026-10-23) : https://claude.ai/artifact/Qm7XF3upJBk5SRVppqgFkf (le canevas de départ est antérieur).
- `Features/Chat` : `ChatTranscript` (pur, testé), `ChatView` (conversation + barre de saisie Liquid Glass, comme ChatGPT/Claude),
  `MessageBubble` (la personne en bulle, l'assistant en texte libre), cartes d'action, `NoticeBanner`.
- `Features/VoiceAssistant/VoiceModeView` : mode vocal plein écran ouvert depuis la barre de saisie, même session.
  Le logo vivant y remplace l'orbe (toucher pendant la parole = interrompre, mêmes annonces VoiceOver). `OrbState` (pur,
  testé ; `caption` = légende visible, `hint` = aide VoiceOver). `FloatingVoiceOrbView` reste dans AVEKit pour les apps hôtes.
- **Logo vivant (maquettes validées le 2026-10-23)** : `Features/Shared/AVEMarkGeometry` (pur, testé) + `AVELiveMark`
  (`Canvas` + `TimelineView`, dessin vectoriel). Au REPOS, l'Afrique dessinée par les barres, recalée
  sur les fichiers du propriétaire (19 barres, 2 barres ambre devant, ligne d'onde qui découpe les barres, Madagascar en
  3 barres ; mesures gardées en pixels du fichier 1254 px), qui respire : https://claude.ai/artifact/4k9RuD9VduaUH72cAyQE8a. Tout le reste suit la première maquette
  (https://claude.ai/artifact/PWGH34u8DZuF78FJWJBmnt) : l'Afrique en contour devient cercle (écoute), onde puis cercle
  (réflexion, en boucle), bulle (parole), et les sept barres suivent le son réel ; naissance = cercle → Afrique, barres
  qui montent. Repos ↔ contour : fondu de 0,45 s. Où : chargement au démarrage et bienvenue (naissance puis repos),
  accueil d'une conversation vide (repos), « Réflexion… » sous la question, mode vocal. « Réduire les animations » :
  l'Afrique en barres, fixe. L'icône de l'app ne change pas. Le tracé est un relevé simplifié du logo : un designer
  peut affiner les points de `africaTrace` sans toucher aux animations.
- Avis « Version d'essai » : `SessionCoordinator.Configuration.demoNotice`, activé par `AVE_DEMO_ENGINE` (xcconfig) tant que le
  moteur répond par écho avec une voix de test.
- **Écrans d'entrée et mot AVE (maquettes validées le 2026-10-23)** : https://claude.ai/artifact/NbMeb9X23PNU8uwaNF7rbr et
  https://claude.ai/artifact/NheM8vLbqjYwhNdmAFw3df. `Features/Shared/AVEWordmarkGeometry` (pur, testé, mesures en pixels
  du fichier du propriétaire) + `AVEWordmark` (le A puis le V se tracent, les barres du E s'allongent, le point tombe,
  puis le sous-titre ; en clair lettres `#1C1C1E` et dernière barre `#00BFD6`). Bienvenue : logo qui naît, mot dessous
  sur le même axe, slogan « Nos langues · votre avenir » (seul écran qui le montre). Connexion : logo au repos, numéro et
  Apple au même poids, « Essayer sans compte » discret. Numéro : indicatif à choisir (`PhoneCountry`, +224 d'avance).
  Code : six cases sur un vrai champ invisible (`oneTimeCode`, VoiceOver, collage), validé seul dès 6 chiffres
  (`SignInViewModel.codeDidChange`, jamais deux fois le même code), décompte puis « Renvoyer un code ». Les fichiers de
  marque sont dans « DOSSIER AVE » sur le bureau du propriétaire.
- **Démo hors ligne (2026-10-23)** : `AVE_DEMO_OFFLINE=YES`, seulement dans le workflow `ave-testflight-demo`. Le client parle
  à `Kit/DemoEngineTransport` (faux serveur sur l'iPhone, VRAI protocole : ready, transcript, reply_text, voix de test,
  tts_end, turn_end, interrupt, speak, ping) au lieu du moteur, sans jeton. Il fait ce que le moteur fait aujourd'hui
  (écho annoncé « Démo hors ligne », son de test) et ne reconnaît pas la parole (un message vocal est dit tel quel). Avis
  permanent sous la barre de saisie (`UserMessages.demoOffline`). La connexion au compte reste RÉELLE si le service de
  comptes répond sur Render (préproduction) ; sinon faux service (code 000000). Jamais dans `ave-testflight`.
- La vue n'arrête jamais la session (`onDisappear` est aussi appelé quand le mode vocal la recouvre) : le propriétaire du
  coordinateur appelle `stop()`.
- `Features/Shared` : `LanguageCatalog`/`LanguagePicker`, `UserMessages`, `AVETheme` (charte remplaçable par WoYo/TaGa).
- Les vues SwiftUI sont sous `#if os(iOS)` ; la logique est testable partout.

## Décisions à connaître
1. **Confirmation des actions** : `action.confirm == true` ⇒ carte « Confirmer / Refuser » ; la voix seule ne valide jamais. `confirm == false`
   ⇒ l'action est rendue tout de suite à l'app hôte (`onAction`). Un `confirm` absent est traité comme `true`. Le serveur n'attend aucune réponse.
2. **Texte** : `text` envoyé tel quel (après `trim`, 1–4000 caractères). La bulle de l'utilisateur apparaît à l'écho `transcript {source:"text"}`, comme pour
   la voix : l'app n'en fabrique pas. Hors ligne, le message n'est pas perdu en silence : l'utilisateur est prévenu. Envoyer du texte pendant que l'assistant
   parle purge la lecture localement (le serveur coupe seul).
3. **Texte de la réponse** : bulle construite phrase par phrase par `utterance_id` (`reply_text`). Sans `reply_text`, bulle « Réponse vocale ».
4. **Lire à voix haute** (2026-10-23) : rejoue l'audio gardé en mémoire (4 Mo max, plus anciens évincés) ; sinon le demande au moteur par `speak` (E7, ≤ 1000 caractères, synthèse seule). Cette lecture ne crée pas de bulle et son audio est gardé pour la fois suivante. Pas de bouton pour une réponse plus longue ou une carte d'action.
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

## Apprentissage et consentement (E15)
Voir `contrat/CONTRAT.md` §7. Logique pure : `Features/Learning/LearningConsent.swift` (règles, notice versionnée, mémoire locale du refus) ;
intégration : `SessionCoordinator` ; écrans : `LearningPromptView`, `LearningSettingsView`, 👍/👎 dans les bulles. À valider sur iPhone : lecture
à voix haute (voix système fr-FR, interaction avec la session audio `.voiceChat`), VoiceOver (pas de double lecture), parcours d'un utilisateur qui ne lit pas.
**Avant tout lancement : notice relue par un juriste et traduite par des natifs ; rôles de responsable de traitement et durée de conservation à fixer.**

## Fichiers, documents et images (E16, E17 ; maquette validée le 2026-10-23, codé le 2026-10-23)
Contrat : `docs/PROTOCOL.md` du moteur (« Fichiers, images, documents », « Signaler un contenu généré »). Code :
`Core/Network/AVEFilesClient.swift` (HTTP : envoi, téléchargement, signalement), `Domain/MediaTask.swift` (tâches et
événements `task_*`), `Features/Media/` (modèle, stockage sur l'iPhone, photos, vues, feuilles),
`SessionCoordinator+Media.swift` (enchaînements). Tests : `AVETests/MediaTests.swift`.
1. **« + » dans la barre** : Photos (sélecteur du système, sans accès à la photothèque), Appareil photo, Fichier (PDF, Word,
   texte), Créer une image. Absent quand le moteur n'est pas joignable (démo hors ligne) et pour les apps hôtes sans fichiers.
2. **Photos** : toujours réencodées en JPEG sur l'iPhone (HEIC refusé par le moteur ; métadonnées EXIF, dont la position,
   retirées), réduites à 4096 px et sous 10 Mo plutôt que refusées. Un PNG léger part tel quel.
3. **Envoi** dès le choix, avec aperçu et croix dans la barre ; clé d'idempotence = la pièce jointe (pas de doublon en 3G).
   Le moteur oublie un fichier en 1 h : avant une tâche, l'app le renvoie depuis l'iPhone si besoin.
4. **Actions** en raccourcis sous la dernière pièce jointe, et par appui long : photo → Recadrer (sur l'iPhone, sans envoi),
   Prolonger, Agrandir 1080p/4K, Modifier ; document → Traduire (anglais, français seulement), Résumer, Reformuler.
5. **Case d'accord** (CGU §2, rien de coché d'avance) avant toute retouche d'une photo envoyée, une fois par photo ; aussi
   pour une image d'AVE dont le moteur a oublié le fichier (elle repart de l'iPhone comme une photo envoyée).
6. **Carte de tâche** : durée ANNONCÉE par le moteur (« Environ 35 s »), barre plafonnée à 95 %, « Annuler ». Annuler avant
   `task_started` : l'annulation part dès que le moteur annonce la tâche. Hors ligne : rien n'est mis en file, « Réessayer ».
7. **Résultats** : téléchargés aussitôt et gardés avec l'historique (dossier Media, exclu d'iCloud, effacé avec la
   conversation). Image : « Générée par IA » toujours, « Image de démonstration » + phrase tant que `simulated` ; Enregistrer
   (Photos, ajout seul), Partager, Refaire, Signaler, Plus. Document : Ouvrir (aperçu d'iOS), Partager, Enregistrer dans Fichiers.
8. **Signaler** : sept motifs, image masquée tout de suite ; « Merci » seulement si le moteur a gardé le signalement
   (`reports_disabled` : on le dit). `file_id` et `task_id` sont gardés dans l'historique, même expirés : le moteur accepte
   le signalement d'une image dont il a oublié le fichier (D3, `main` @ `35a4757`). Historiques d'avant : pas de `file_id`,
   l'app dit que le signalement n'a pas pu être enregistré.
9. **Session perdue pendant une tâche** (coupure plus longue que le délai de grâce, D1) : une tâche déjà annoncée
   (`task_started`) est suivie par `GET /v1/tasks/{task_id}`, une requête toutes les 3 s au plus et un tour toutes les 10 s,
   jusqu'au résultat, à l'échec ou au bout d'1 h (« Le résultat n'est plus disponible ») ; une demande pas encore annoncée
   est perdue (« La connexion a été coupée… », Réessayer). L'app relancée ne reprend pas les cartes (elles ne sont pas
   gardées dans l'historique).

À vérifier sur iPhone (rien n'a tourné) : sélecteur de photos et appareil photo, conversion HEIC, aperçu QuickLook,
enregistrement dans Photos et Fichiers, VoiceOver sur les cartes, mise en page des raccourcis en grande taille de texte.
Côté moteur : les images restent simulées tant que la machine GPU ne tourne pas, et le tenant `ave-grand-public` doit avoir
les `features` `images` et `documents`, sinon chaque demande répond « Cette fonction n'est pas encore disponible. ».

## Assistant du quotidien (maquettes validées le 2026-10-23, les cinq écrans)
Validées une par une par le propriétaire sur la page « Validation des maquettes AVE ».
- **Accueil** : six exemples du quotidien (organiser, écrire, comprendre, chercher, cuisiner, parler) ; la barre dit
  « Demandez ce que vous voulez » tant que la conversation est vide.
- **Arrêter** : pendant que l'assistant prépare, écrit ou dit sa réponse, le bouton rond devient un carré. Il envoie
  `interrupt`, marque la bulle « Interrompu » (ce qui est écrit reste) et ignore le reste du tour jusqu'à son `turn_end`
  (repli : le `transcript` du tour suivant, tant que la PR #28 du moteur n'est pas déployée). Comportement du moteur
  confirmé par sa session le 2026-10-23 (PR #28).
- **Tableaux** : `| a | b |` suivi de `|---|---|` ; un tableau plus large que l'écran défile dans la réponse.
- **Mention d'essai** : suit `ready.engine` (D6) à chaque session : écho et son de test → mention complète ; dialogue
  réel et voix de test → « la voix de l'assistant est un son de test » ; tout réel → aucune. Sans `engine` (moteur ancien,
  démo hors ligne) : le réglage du build.
- **Réponse au fil de l'eau (D7, moteur `main` @ `d14a002`, en ligne)** : l'app demande `text_delta` et affiche les
  `reply_delta` ; les `reply_text` ne servent plus qu'à la voix (jamais les deux). Sans fragments, les `reply_text` sont
  concaténés SANS rien ajouter : le texte du moteur est exact, listes et tableaux restent intacts. Repli : un moteur ancien
  qui refuse `text_delta` (`bad_output`) fait reconnecter sans.
- **Mémoire (D9)** : à chaque session neuve (conversation rouverte, ou session expirée en cours de route), l'app envoie
  les derniers échanges lisibles (`ConversationContext` : 20 messages, 4000 caractères chacun, 8000 en tout) AVANT toute
  entrée. L'avis « l'assistant ne se souvient pas » n'apparaît plus que si le moteur refuse le contexte (l'app se
  reconnecte alors sans) ; « se souvient des N derniers messages » si le moteur en a écarté.
- **Pas encore codé, en attente du moteur** : sources (D8, après le choix du moteur de recherche par le propriétaire),
  titre généré (D10). Non vérifié : fluidité des fragments sur un vrai téléphone, comportement avec le vrai modèle.

## Écrans épurés, lumière douce et nouvelle entrée (validés le 2026-10-23)
Remplacent les écrans « assistant du quotidien » de la même soirée. Règles du propriétaire : le symbole et ses animations
ne changent pas ; **composants natifs d'iOS uniquement** (boutons en verre, interrupteurs, menus, feuilles du système) ;
une maquette HTML ne montre qu'une intention.
- **Accueil** : le symbole au repos, « Bonjour, Fatou » (prénom tiré du nom complet), « Comment puis-je vous aider ? ».
  Idées rangées : une pastille « Idées » au-dessus de la saisie ; touchée, une rangée de boutons en verre défile (écrire
  une lettre, comprendre une facture, budget du mois, créer une image, résumer un document, chercher une info) ; elles se
  rangent dès qu'on écrit ou qu'on en choisit une.
- **Saisie en deux étages** : « Demandez à AVE », puis « + » à gauche et le bouton rond à droite (Envoyer en bleu AVE
  #2F5BE0, seul aplat de couleur ; Arrêter et Mode vocal en noir). Dessous, en petit : la mention d'essai (selon le moteur)
  puis « AVE peut se tromper. Vérifiez les informations importantes. »
- **Réponse** : le symbole en tête de la DERNIÈRE réponse (réflexion pendant l'écriture, repos ensuite) ; dessous :
  copier, écouter, bon et mauvais (seulement avec l'accord d'aide à l'amélioration : sans lui le moteur ne garde rien),
  « Plus » (partager, régénérer).
- **Mode vocal** : toujours sombre ; la langue en haut ; trois boutons de 64 points (couper le micro, sous-titres,
  Terminer en rouge à droite) ; toucher le symbole coupe la voix d'AVE.
- **Lumière douce** (`AmbientGlow`, `GlowLevel`) : sur le pourtour en mode vocal, froide quand on parle, chaude quand AVE
  parle ; intensité selon le son lissé, de 20 % à 80 % par paliers de 5 % avec une transition d'une demi-seconde, couleurs
  qui tournent en 8 s ; fixe avec « Réduire les animations », absente en contraste élevé. Dans la conversation écrite,
  seulement un halo léger autour de la saisie quand AVE lit à voix haute.
- **Historique** : la suppression se confirme.
- **Entrée** : bienvenue, numéro, code (remplissage automatique d'iOS), puis le nom complet (pré-rempli par Apple ; pas
  d'écran pour un essai sans compte), puis « Avant de commencer » : 18 ans ou plus et conditions, deux interrupteurs jamais
  mis d'avance. Profil gardé par `ave-accounts` (`/account/profile`) et sur l'iPhone. Conditions et politique de
  confidentialité : brouillons dans l'app (`Terms`), à faire relire par un juriste ; changer leur fond = changer
  `Terms.currentVersion`, l'accord est alors redemandé.
- **Dictée** (décision du propriétaire, 2026-10-23) : le micro de la barre utilise la reconnaissance vocale d'Apple SUR
  L'IPHONE (`DictationRecognizer`, `requiresOnDeviceRecognition`) ; sans reconnaissance locale du français, la dictée n'est
  pas proposée (jamais de repli sur les serveurs d'Apple). Un toucher : on dicte, le texte s'écrit à la suite de la barre ;
  second toucher : fini ; rien ne part sans « Envoyer ». Autorisation `NSSpeechRecognitionUsageDescription`. La politique
  de confidentialité le dit : conditions passées en `2026-10-v2`, l'accord est redemandé.
- **Pas fait** : les sources (D8) attendent le moteur de recherche. Non vérifié : tout l'aspect à l'écran, la fluidité de la
  lumière, et la dictée pendant qu'une session audio est ouverte (deux moteurs audio) sur un vrai iPhone.
