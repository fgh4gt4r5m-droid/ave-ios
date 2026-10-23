# Apple Developer et App Store Connect : pas à pas (sans Mac)

Rédigé le 2026-10-23. Tout se fait dans un navigateur (ou l'app « Apple Developer » sur iPhone) ; la compilation et la
signature passent par Codemagic. **Aucune clé, aucun certificat, aucun fichier `.p8` ne doit être collé dans une
conversation ni commité dans un dépôt.**

## 0. Décisions à prendre AVANT de commencer (irréversibles ou presque)
| Décision | Pourquoi c'est important |
|---|---|
| **Compte Individuel ou Organisation** | Le nom affiché comme vendeur sur l'App Store est le vôtre (individuel) ou celui de la société (organisation). Organisation = entité juridique + **numéro D-U-N-S** (gratuit, quelques jours à obtenir). Changer plus tard est long. |
| **Identifiant de bundle** | Le code utilise `fr.ave.app` (app) et `fr.ave.app.liveactivity` (extension) : c'est une **hypothèse**. Une fois l'app créée dans App Store Connect, il ne change plus. Convention : un domaine que vous possédez, à l'envers. Me dire la valeur choisie : je l'aligne dans `project.yml`, `codemagic.yaml` et le Keychain. |
| **Nom de l'app** | 30 caractères maximum, unique sur l'App Store. Ex. « AVE – African Voice Engine » (26). |

## 1. Programme Apple Developer (99 USD/an)
1. Identifiant Apple avec **double authentification** activée.
2. https://developer.apple.com/programs/enroll/ (ou l'app « Apple Developer » sur iPhone, souvent plus simple pour l'identité).
3. Choisir Individuel ou Organisation (voir §0), payer, attendre la validation (de quelques heures à quelques jours).

## 2. Identifiants (developer.apple.com → Certificates, Identifiers & Profiles → Identifiers)
1. **App ID** « explicite » : bundle choisi au §0 (ex. `fr.ave.app`). Cocher les capacités :
   - **Sign in with Apple** (« Enable as a primary App ID ») ;
   - **App Attest**.
2. **App ID de l'extension** : `<bundle>.liveactivity`, aucune capacité.
3. Rien d'autre : pas de notifications push en v1 (la Live Activity est mise à jour localement).

## 3. Clé API App Store Connect (pour que Codemagic signe et envoie les builds)
1. App Store Connect → **Utilisateurs et accès → Intégrations → App Store Connect API → Clés d'équipe** → « + ».
2. Nom : `Codemagic` ; accès : **App Manager**.
3. Télécharger le fichier `.p8` (**une seule fois possible**), noter l'**Issuer ID** et le **Key ID**. Garder le `.p8` hors de tout dépôt.
4. Codemagic → **Team settings → Integrations → Developer Portal → Manage keys** → ajouter la clé sous le nom **`AVE_ASC_KEY`**
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

## 5. TestFlight (premier essai sur iPhone)
Ce qui manque encore, côté app et service — **à faire avant le premier envoi** :
- **Icône 1024 × 1024 px** opaque, symbole seul (voir `ASSETS.md`) : sans elle, Apple refuse le build.
- **Vraies adresses** du moteur (`wss://…`) et du service de comptes (`https://…`) déployés publiquement, passées à Codemagic par le
  groupe de variables `ave` (`AVE_ENDPOINT`, `AVE_ACCOUNTS_URL`).
- `ITSAppUsesNonExemptEncryption = NO` dans l'Info.plist (chiffrement standard HTTPS/WSS seulement) : évite la question à chaque build.
- Puis Codemagic → workflow **`ave-testflight`** (manuel). Testeurs **internes** (membres de l'équipe, jusqu'à 100) : pas de revue Apple.
  Testeurs **externes** : revue « Beta App Review » d'Apple.

## 6. Publication publique : ce qui bloquera la revue Apple aujourd'hui (honnêteté)
- **Fonctionnalité minimale (règles 2.1 et 4.2)** : le moteur répond par écho avec un son de test ; une app publique dans cet état a de
  fortes chances d'être refusée. TestFlight interne est adapté ; la publication attend un vrai TTS/LLM côté moteur.
- **Compte de démonstration pour la revue** : la connexion par SMS ne fonctionne pas pour le relecteur. Le service de comptes devra
  accepter un numéro de test à code fixe, activé seulement pour la revue (**non construit** dans `ave-accounts`).
- **Suppression de compte avec Sign in with Apple (règle 5.1.1(v))** : le service doit révoquer le jeton Apple
  (`https://appleid.apple.com/auth/revoke`) à la suppression. **Non construit** dans `ave-accounts`.
- Captures d'écran iPhone 6,9 pouces (1320 × 2868) : à produire depuis le simulateur une fois l'interface finale.
