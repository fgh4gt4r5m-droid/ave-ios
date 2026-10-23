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
  (`Canvas` + `TimelineView`, dessin vectoriel). Au REPOS, l'Afrique dessinée par 27 barres (+ Madagascar), qui respire :
  https://claude.ai/artifact/4tgbWQXgUiZav1sdrhDv4y. Tout le reste suit la première maquette
  (https://claude.ai/artifact/PWGH34u8DZuF78FJWJBmnt) : l'Afrique en contour devient cercle (écoute), onde puis cercle
  (réflexion, en boucle), bulle (parole), et les sept barres suivent le son réel ; naissance = cercle → Afrique, barres
  qui montent. Repos ↔ contour : fondu de 0,45 s. Où : chargement au démarrage et bienvenue (naissance puis repos),
  accueil d'une conversation vide (repos), « Réflexion… » sous la question, mode vocal. « Réduire les animations » :
  l'Afrique en barres, fixe. L'icône de l'app ne change pas. Le tracé est un relevé simplifié du logo : un designer
  peut affiner les points de `africaTrace` sans toucher aux animations.
- Avis « Version d'essai » : `SessionCoordinator.Configuration.demoNotice`, activé par `AVE_DEMO_ENGINE` (xcconfig) tant que le
  moteur répond par écho avec une voix de test.
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
