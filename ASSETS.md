# Assets de la marque (app AVE)

Logo retenu : la **carte de l'Afrique en volutes avec barres de son** (proposition 1). Les deux propositions reçues sont des images
raster de 1254 px, probablement générées par IA : elles ne sont **pas** dans le dépôt (droits et qualité non établis).

## Ce qu'il faut fournir (designer)
| Fichier | Spécification |
|---|---|
| `AppIcon` | 1024 × 1024 px, PNG **opaque**, sans texte ni transparence : symbole seul (carte + barres) centré sur le fond `#010A29`, marges ≥ 10 %. iOS applique lui-même les coins arrondis. |
| Symbole vectoriel | SVG, fond transparent, variantes claire et sombre. |
| Logo complet | SVG avec « AFRICAN VOICE ENGINE » (écran de lancement, site, console) : illisible comme icône. |
| Glyphe Live Activity | Barres de son seules, **monochrome** (SF Symbol personnalisé ou PDF vectoriel). Provisoire : symboles SF (`waveform`…). |

À déposer dans `AVE/App/Assets.xcassets/AppIcon.appiconset/` en remplaçant `AppIcon-1024.png`.
**Icône actuelle (2026-10-23)** : générée par le propriétaire à partir des prompts fournis (carte de l'Afrique en volutes,
barres de son, barre centrale ambre) : `AppIcon-1024.png` (clair, fond bleu nuit), `AppIcon-Dark-1024.png` (sombre, fond
noir) et `AppIcon-Tinted-1024.png` (teintée, niveaux de gris), 1024 px opaques, vérifiées lisibles à 60 et 29 px.
`AVELogo` : le même logo DÉTOURÉ (fond transparent, tiré de la version sombre) pour l'écran de lancement et les animations.
Images générées par IA : recherche d'antériorité sur le logo à faire avant le lancement public ; vectorisation à prévoir.

## Palette (relevée sur le logo, approximative)
`AVEPalette` : fond `#010A29`, bleu `#5EA0FD`, ambre `#FEBD3F`, violet `#813EF3`, surface `#101C4D` (dérivée).
Règles d'usage, vérifiées par `BrandAndActivityTests` : texte et icônes **sur le bleu : bleu nuit** (7,4:1 ; le blanc ne fait que 2,7:1) ;
violet **jamais en texte** (3,6:1) ; ambre pour mises en avant et avertissements (11,7:1 sur le fond).

## Marque
Avant tout lancement public : version redessinée par un designer, recherche d'antériorité sur le nom et le logo.
