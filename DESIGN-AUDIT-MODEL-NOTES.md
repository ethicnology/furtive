# Faut-il basculer sur Fable pour l'audit design ? — notes juillet 2026

Contexte : ce document répond à la question posée pendant la passe de refonte
visuelle de l'app (thème, écrans, contraste WCAG). Rédigé après vérification
sur anthropic.com/claude/fable et claude.com/product/design (juillet 2026),
pas de mémoire non vérifiée.

## Ce qu'est réellement Fable (et ce qu'il n'est pas)

- **Claude Fable 5** est un *modèle* Claude (5ᵉ génération, sorti juin 2026,
  redéployé le 1ᵉʳ juillet après une interruption liée à des mesures de
  sécurité renforcées) — pas un outil ou un produit d'audit design dédié.
  C'est le pendant "généralement disponible" de Mythos 5, positionné comme
  le modèle le plus capable pour du travail long, ambitieux, autonome
  (agents tournant plusieurs jours, migrations complexes).
- Point pertinent pour notre usage : Fable 5 revendique explicitement
  l'usage de la vision pour **"checking outputs against the original design
  or goal"** — exactement le type de boucle que j'ai faite à la main
  (golden test → capture PNG → relecture visuelle → ajustement).
- **Claude Design** (claude.ai/design) est un produit *séparé*, en beta,
  pour créer des maquettes/prototypes/decks à partir d'une description —
  pas un outil d'audit d'une app déjà codée. Peu pertinent ici : on ne part
  pas d'une idée à maquetter, on corrige une UI Flutter existante.
- Je (cette session) tourne sur **Claude Sonnet 5**, pas Fable — confirmé
  par mon system prompt.

## Ce que Fable 5 apporterait concrètement sur cette tâche

Points forts documentés qui *pourraient* aider :
- Vision plus poussée pour l'auto-vérification visuelle (pertinent : j'ai dû
  lire moi-même chaque golden PNG et juger à l'œil — un modèle avec une
  vision plus fine catcherait potentiellement des détails que j'ai pu
  manquer, ex. alignement fin, subtilités de contraste).
- Meilleur sur du travail long/autonome à plusieurs étapes — pertinent si tu
  veux qu'un agent parcoure *tous* les écrans restants sans supervision
  serrée.
- "Implements designs with high fidelity" — pertinent pour la fidélité
  d'exécution une fois la direction validée.

Points qui ne changent rien pour cette tâche précise :
- Le travail le plus dur (tokens de couleur, hiérarchie de surfaces, choix
  de police, calculs WCAG, correction des deux erreurs de contraste) est
  **déjà fait et vérifié** (flutter analyze + test + rendu golden relu). Un
  modèle plus puissant n'aurait pas mieux fait ce travail rétroactivement.
- Le goulot d'étranglement réel n'était pas la capacité du modèle mais
  **l'absence d'émulateur/device réel** dans cet environnement — Fable ne
  résout pas ce problème, il reste tributaire du même outillage (golden
  tests headless) que moi.

## Coût et frictions à connaître avant de basculer

- **Tarif** : $10 / M tokens input, $50 / M tokens output — sensiblement
  plus cher que Sonnet. Pour un audit itératif (beaucoup d'aller-retours
  golden test → lecture image → ajustement, comme on l'a fait), le volume
  de tokens image + itérations peut faire grimper la facture vite.
- **Rétention de données 30 jours obligatoire** pour raisons de sécurité —
  point à noter par ironie pour une app qui se revendique "privacy-first",
  même si ça concerne les données de la session avec Anthropic, pas l'app
  elle-même.
- **Garde-fous cyber/bio** : sans rapport avec ce projet (aucune requête ne
  devrait être routée vers Opus en fallback ici).

## Recommandation

**Pas nécessaire de basculer pour continuer ce travail spécifique.** Le
principal levier de qualité restant n'est pas la puissance du modèle, c'est
**tester sur un vrai appareil/émulateur** (ce qu'aucun des deux modèles ne
peut faire à ma place dans cet environnement) — captures d'écran réelles,
retour tactile sur les boutons pilule, lisibilité en plein soleil réel.

Cas où Fable *deviendrait* pertinent :
- Si tu veux qu'un agent traite en une seule fois, de façon quasi autonome,
  un très gros volume d'écrans/composants restants sans revalidation
  fréquente de ta part (travail long-horizon).
- Si tu constates que je rate des détails visuels fins dans mes relectures
  de golden tests (limite de vision plutôt que de raisonnement) — dans ce
  cas spécifique, la vision plus poussée de Fable serait le bon levier.

En l'état, je recommande de rester sur Sonnet pour finir la passe (cohérence
de contexte avec tout ce qui a déjà été fait), et de réserver Fable pour un
futur chantier long et autonome (ex. le service natif de survie au kill de
process, différé précédemment, qui demanderait effectivement du travail
long-horizon avec tests d'instrumentation Android une fois le matériel
disponible).
