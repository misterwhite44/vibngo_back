# Contrat avec le service IA (proposition)

Brouillon de l'interface entre le backend et le service de l'équipe IA, à rédiger ensuite en
OpenAPI versionné (`/v1`) **avec** l'équipe IA et à tester des deux côtés (tests de contrat).
Tout ce qui est marqué *(à confirmer)* est une hypothèse.

## Principes

- **Service sans état** (confirmé) : il reçoit les données, calcule, renvoie. Aucune donnée
  d'utilisateur conservée chez lui.
- **Aucun identifiant d'utilisateur** dans les appels : le backend garde le lien avec
  l'utilisateur. Seul un `correlationId` technique circule.
- **Appelé uniquement via `AiClient`** : timeout, réessais limités, circuit breaker.
- Authentification de service à service ; le service n'est pas exposé publiquement.
- Erreurs au format `application/problem+json` avec un code, un indicateur `retryable` et le
  `correlationId`.
- Engagement de temps de réponse écrit (cible : moins de 2 s pour les recommandations).
- Chaque réponse de calcul porte une `modelVersion`.

## Dimensions et vecteur (confirmé)

Les **dimensions** sont les 6 axes qui décrivent un voyageur. Elles servent à déterminer le
**profil** (un parmi 8) et à classer les destinations. Le vecteur est un **tableau de 6
nombres**, dans cet ordre fixe :

| Position | Dimension (nom technique) |
|:-:|---|
| 0 | `urbanite` |
| 1 | `intensite` |
| 2 | `planification` |
| 3 | `social` |
| 4 | `confort` |
| 5 | `decouverte` |

Plage de valeurs : *(à confirmer, probablement 0 à 1)*.

**Règle côté backend** : cette table est écrite **à un seul endroit** (l'adaptateur
`AiClient`), qui convertit le tableau de l'IA en objet nommé
`{ urbanite, intensite, ... }` à la réception, et l'inverse à l'envoi. Tout le reste du
backend (stockage, API, front) manipule les scores **par nom**. Un changement d'ordre ne
touche donc qu'une classe.

## Profils voyageurs (confirmé : liste fermée de 8)

Explorateur Aventurier · Explorateur Urbain · Aventurier Nature · Globe-trotter Social ·
Voyageur Épicurien · Voyageur Zen · Voyageur Organisé · Explorateur Authentique.

Chaque profil a un **code technique stable** *(codes à fournir par l'équipe IA quand ils
auront terminé)*. Le nom et la description peuvent évoluer sans changer le code. Le backend
stocke uniquement le code (chaîne, pas d'enum) et lit le nom et la description dans le
référentiel ci-dessous.

## Routes

### Référentiel des profils *(route confirmée, chemin à confirmer)*
```
GET /v1/profiles
← 200 { profiles: [{ code: string, name: string, description: string }], modelVersion: string }
```
Identity met la réponse en cache et la sert au front (`GET /traveler-profiles`).

### Questionnaire *(à confirmer : route ou stockage côté backend)*
```
GET /v1/questionnaire
← 200 { version: string,
        questions: [{ id: string, label: string, options: [{ code: "A"|"B"|"C"|"D", label: string }] }] }
```
L'association question → dimension reste interne à l'IA et n'est jamais exposée.

### Calcul du profil
```
POST /v1/profiles/compute
→ { questionnaireVersion: string,
    responses: { "<questionId>": "A"|"B"|"C"|"D" } }     // forme exacte à confirmer (dictionnaire probable)
← 200 { vector: number[6],                                // ordre : voir table ci-dessus
        profile: { code: string },
        modelVersion: string }
```

### Recommandations
```
POST /v1/recommendations
→ { vector: number[6],
    filters?: { budget?: number, durationDays?: number },
    limit?: number }
← 200 { items: [{ destinationId: string, score: number }],   // destinationId = sourceId du Catalog
        modelVersion: string }
```
Hypothèse : le service IA détient les vecteurs des destinations *(à confirmer)*. Sinon, le
backend devrait les envoyer à chaque appel.

## Ce que le backend conserve (parce que l'IA ne retient rien)

Les réponses A/B/C/D, `questionnaireVersion`, les scores (par nom), le code de profil,
`modelVersion` (Identity). Si le modèle change, le profil peut ainsi être recalculé.