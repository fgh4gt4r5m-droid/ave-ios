# Apple Developer et App Store Connect : pas à pas (sans Mac)

Rédigé le 2026-10-23. Tout se fait dans un navigateur (ou l'app « Apple Developer » sur iPhone) ; la compilation et la
signature passent par Codemagic. **Aucune clé, aucun certificat, aucun fichier `.p8` ne doit être collé dans une
conversation ni commité dans un dépôt.**

## Compte existant (WoYo et Driver sont déjà sur l'App Store)
Le programme Apple Developer, l'équipe et l'intégration Codemagic existent déjà : **pas de nouvelle inscription** (§1 sauté).
- **AVE se publie dans la MÊME équipe** que WoYo et Driver (même nom de vendeur sur l'App Store).
- **Clé API** : réutiliser la clé App Store Connect déjà déclarée dans Codemagic pour WoYo/Driver (accès App Manager
  suffisant) ; `codemagic.yaml` doit porter **son nom exact** : `TAM_ASC_KEY`.
- **Certificat Apple Distribution** : réutiliser celui que Codemagic a déjà (Apple limite leur nombre par équipe ; en
  créer un nouveau sans besoin peut bloquer). Il signe aussi AVE : seuls les **profils** sont propres à AVE (§5, étape 2).
- **Identifiant de bundle** : suivre le préfixe déjà utilisé par WoYo et Driver (même domaine inversé).
- Ne rien modifier dans les identifiants, profils ou certificats de WoYo/Driver : on ne fait qu'en AJOUTER pour AVE.

## Service de comptes : réglages liés à l'identifiant (au déploiement de `ave-accounts`)
- `ACCOUNTS_APPLE_AUDIENCE=com.tam.ave` : sans lui, Sign in with Apple est désactivé (503).
- `ACCOUNTS_APPATTEST_APP_ID=<TEAM_ID>.com.tam.ave` : `<TEAM_ID>` = identifiant d'équipe à 10 caractères (developer.apple.com →
  Membership details), le même que pour WoYo. Sans lui, le mode invité est désactivé (403).

## 0. Décisions à prendre AVANT de commencer (irréversibles ou presque)
| Décision | Pourquoi c'est important |
|---|---|
| **Compte Individuel ou Organisation** | Le nom affiché comme vendeur sur l'App Store est le vôtre (individuel) ou celui de la société (organisation). Organisation = entité juridique + **numéro D-U-N-S** (gratuit, quelques jours à obtenir). Changer plus tard est long. |
| **Identifiant de bundle** | **Décidé (2026-10-23) : `com.tam.ave` (app) et `com.tam.ave.liveactivity` (extension)**, même préfixe que WoYo (`com.tam.woyo`). Définitif dès le premier build envoyé. Déjà aligné dans `project.yml`, `codemagic.yaml` et le Keychain. |
| **Nom de l'app** | 30 caractères maximum, unique sur l'App Store. Ex. « AVE – African Voice Engine » (26). |

## 1. Programme Apple Developer (99 USD/an)
1. Identifiant Apple avec **double authentification** activée.
2. https://developer.apple.com/programs/enroll/ (ou l'app « Apple Developer » sur iPhone, souvent plus simple pour l'identité).
3. Choisir Individuel ou Organisation (voir §0), payer, attendre la validation (de quelques heures à quelques jours).

## 2. Identifiants (developer.apple.com → Certificates, Identifiers & Profiles → Identifiers)
1. **App ID** « explicite » : `com.tam.ave`. Cocher les capacités :
   - **Sign in with Apple** (« Enable as a primary App ID ») ;
   - **App Attest**.
2. **App ID de l'extension** : `<bundle>.liveactivity`, aucune capacité.
3. Rien d'autre : pas de notifications push en v1 (la Live Activity est mise à jour localement).

## 3. Clé API App Store Connect (pour que Codemagic signe et envoie les builds)
1. App Store Connect → **Utilisateurs et accès → Intégrations → App Store Connect API → Clés d'équipe** → « + ».
2. Nom : `Codemagic` ; accès : **App Manager**.
3. Télécharger le fichier `.p8` (**une seule fois possible**), noter l'**Issuer ID** et le **Key ID**. Garder le `.p8` hors de tout dépôt.
4. Codemagic → **Team settings → Integrations → Developer Portal → Manage keys** → ajouter la clé sous le nom **`TAM_ASC_KEY`** (clé existante de l'équipe, partagée avec WoYo et Driver)
   (c'est le nom attendu par `codemagic.yaml`).
5. Codemagic → **Code signing identities → iOS certificates** → « Generate certificate » (type Apple Distribution) avec cette clé.
   Codemagic crée ensuite les profils de provisionnement à chaque build.

## 4. Fiche de l'app (App Store Connect → Apps → « + » → Nouvelle app)
- Plateforme : iOS ; nom (§0) ; langue principale : **Français** ; bundle : celui du §2 (il apparaît dans la liste une fois créé) ;
  SKU : libre, ex. `AVE-IOS-001` ; accès : complet.
- **Informations de l'app** : sous-titre (30 car.), ex. « Nos langues, votre avenir » ; catégorie (ex. Éducation ou Productivité) ;
  questionnaire d'**âge** (répondre honnêtement : contenus générés par un assistant, discussion libre).
- **URL de confidentialité** et **URL d'assistance** : obligatoires, pages web publiques à créer.
- **Confidentialité de l'app** (étiquettes) — à valider avec le juriste, base proposée :
  | Donnée | Liée à l'utilisateur | Usage |
  |---|---|---|
  | Numéro de téléphone | oui | Fonctionnement de l'app (connexion) |
  | Identifiant utilisateur | oui | Fonctionnement de l'app |
  | Audio (voix) et messages | oui si compte | Fonctionnement ; **amélioration du service seulement avec consentement** |
  Pas de pistage publicitaire, pas d'analytique tierce dans l'app aujourd'hui.

## 5. TestFlight pas à pas (testeurs internes, sans revue Apple)
Le workflow Codemagic **`ave-testflight`** est prêt (signature, numéro de build automatique, envoi). Il exporte un build
**réservé aux testeurs internes** (`testFlightInternalTestingOnly`) : pas de « Beta App Review », mais seuls les membres de
votre équipe App Store Connect peuvent l'installer (100 au maximum).

**Avant tout** : les §1 à §4 sont faits (programme payé, les DEUX identifiants créés, clé `TAM_ASC_KEY` dans Codemagic,
fiche de l'app créée). Identifiant de bundle : `com.tam.ave`, écrit dans
`project.yml`, `codemagic.yaml` et le Keychain, et le service de comptes doit le connaître (audience Sign in with Apple).

1. **Certificat** — Codemagic → Team settings → **Code signing identities → iOS certificates** : le certificat
   **Apple Distribution** de l'équipe (déjà utilisé pour WoYo/Driver) y est normalement. Seulement s'il n'y est pas :
   « Generate certificate », type Apple Distribution, avec la clé de l'équipe.
2. **Profils** (navigateur) — developer.apple.com → Certificates, Identifiers & Profiles → **Profiles** → « + » →
   **App Store Connect** (distribution) → App ID `com.tam.ave` → le certificat de l'étape 1 → nom « AVE App Store ».
   Recommencer pour `com.tam.ave.liveactivity` → nom « AVE Live Activity App Store ».
3. **Profils dans Codemagic** — Code signing identities → **iOS provisioning profiles** → « Fetch profiles » → cocher les deux.
4. **Adresses** — Codemagic → app `ave-ios` → Environment variables → groupe **`ave`** :
   `AVE_ENDPOINT` = `wss://…/v1/stream` (moteur) et `AVE_ACCOUNTS_URL` = `https://…` (service de comptes). Le workflow
   **refuse** de construire avec une adresse `.example`, `ws://` ou `http://`.
5. **Testeurs** — App Store Connect → Utilisateurs et accès : inviter chaque testeur (rôle « Développeur » ou
   « Marketing » suffit). Puis l'app → **TestFlight → Tests internes → « + »** : groupe « Équipe AVE », ajouter les testeurs,
   activer la **distribution automatique**.
6. **Lancer** — Codemagic → `ave-ci` doit être vert sur `main`, puis **`ave-testflight`** → « Start new build » → `main`.
   Compter ~20–30 min de build, puis 10–30 min de traitement chez Apple.
7. **Installer** — chaque testeur reçoit un e-mail, installe l'app **TestFlight** depuis l'App Store, accepte l'invitation, installe AVE.

### En attendant les serveurs : `ave-testflight-demo` (« démo interface »)
Même parcours **sans l'étape 4** (aucune adresse). Le build utilise le **faux service de comptes** : n'importe quel numéro,
code **`000000`**, aucun SMS envoyé, ce qu'un bandeau ambre dit sur l'écran de connexion. On touche tous les écrans
(connexion, conversation, mode vocal, langues, compte) ; le moteur étant injoignable, l'assistant ne répond pas (« Connexion… »).
Export réservé aux testeurs internes : ce build ne peut pas être soumis à l'App Store. Numéro de build = date et heure UTC
(`AAMMJJHHMM`) dans les deux workflows : jamais de doublon, même en alternant les deux comptes Codemagic.

**Ce qui fonctionnera, honnêtement** : l'app ne fait rien sans serveurs joignables. Sans moteur ni service de comptes
déployés (étape 4), on ne dépasse pas l'écran de connexion. L'icône est **provisoire** (`ASSETS.md`).

## 6. Publication publique : ce qui bloquera la revue Apple aujourd'hui (honnêteté)
- **Fonctionnalité minimale (règles 2.1 et 4.2)** : le moteur répond par écho avec un son de test ; une app publique dans cet état a de
  fortes chances d'être refusée. TestFlight interne est adapté ; la publication attend un vrai TTS/LLM côté moteur.
- **Compte de démonstration pour la revue** : la connexion par SMS ne fonctionne pas pour le relecteur. Le service de comptes devra
  accepter un numéro de test à code fixe, activé seulement pour la revue (**non construit** dans `ave-accounts`).
- **Suppression de compte avec Sign in with Apple (règle 5.1.1(v))** : le service doit révoquer le jeton Apple
  (`https://appleid.apple.com/auth/revoke`) à la suppression. **Non construit** dans `ave-accounts`.
- Captures d'écran iPhone 6,9 pouces (1320 × 2868) : à produire depuis le simulateur une fois l'interface finale.
