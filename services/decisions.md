# Décisions et points ouverts

Statuts : **Décidé** (validé), **Recommandé** (proposition retenue pour avancer, à confirmer),
**Ouvert** (attend une réponse). La dernière colonne dit comment l'architecture est protégée
si la réponse change.

## Décidées

| Sujet | Décision |
|---|---|
| Stack | React Native (front), NestJS (backend) |
| Architecture | Microservices : Identity, Travel, Assistant, avec API Gateway |
| Protocole | REST entre services ; BullMQ/Redis pour l'asynchrone |
| Service IA | Sans état ; reçoit les données, calcule, renvoie ; persistance chez nous |
| Questionnaire | Géré par l'équipe IA (12 questions, 6 dimensions, conversion A/B/C/D) |
| Dimensions | 6 dimensions, ordre fixe 0 à 5 : urbanité, intensité, planification, social, confort, découverte. Elles déterminent le profil |
| Vecteur | Tableau de 6 valeurs côté IA ; converti en scores nommés dans `AiClient` |
| Profils | Liste fermée de 8 profils, chacun avec un code stable ; nom et description évolutifs |
| Nom et description des profils | Fournis par une route de l'IA ; Identity les met en cache |
| Auth | JWT avec révocation via Redis ; email/mot de passe + OAuth |
| Nom du microservice | « Assistant » (ancien « IA ») |
| Rangement des fichiers | Par microservice (`api/identity`, `api/travel`, `api/assistant`) |
| Trajets | Google Maps côté backend ; Mapbox reste pour la carte du front |

## Recommandées (à confirmer)

| Sujet | Recommandation | Si ça change |
|---|---|---|
| Rôle d'Ollama | Appelé par Assistant via `LlmClient` (chatbot et génération côté backend) | Seul `LlmClient` et le périmètre d'Assistant changent |
| Recommandations | Module `Recommendation` dans Assistant | Extractible en microservice plus tard |
| ORM / ODM | Prisma (un projet par microservice) + Mongoose, derrière des interfaces de dépôt | Le métier ne voit pas l'ORM : remplaçable |
| Profils | Code stocké en chaîne, jamais d'énumération en dur | Aucune migration si la liste évolue |
| Génération | Asynchrone (`202` + tâche) | — |
| Redis | Deux rôles : `redis-core` (sans éviction) et `redis-cache` | — |
| Scores du profil | Stockés par nom ; la correspondance avec les positions du tableau n'existe que dans `AiClient` | Un changement d'ordre ne touche qu'une classe |
| Destinations | Clé interne (UUID) + `sourceId` fourni par l'IA, import idempotent | Un identifiant instable est rattrapé à l'import |

## Ouvertes : à poser à l'équipe IA

| # | Question | Impact | Bloque ? |
|---|---|---|---|
| 1 | Chatbot et génération d'itinéraire : bien côté backend ? | Taille du microservice Assistant | Non (hypothèse oui) |
| 2 | Les vecteurs des 100 destinations sont-ils détenus par l'IA ? | Contenu de la requête `/recommendations`, éventuelle colonne dans `Catalog` | Non |
| 3 | Plage de valeurs du vecteur, normalisé ? | Validation côté backend | Non |
| 4 | Format exact de `responses` | Un seul adaptateur dans `AiClient` | Non |
| 5 | 12 questions : route à exposer, ou stockage côté backend ? | Source de `GET /users/me/questionnaire` (invisible pour le front) | Non |
| 6 | **Codes** des 8 profils (annoncés à la fin de leur travail) | Remplissage de `recommendedProfiles` dans le catalogue, validation à l'import | **Oui, pour le contenu du catalogue** |
| 7 | Chemin exact de la route des profils (`GET /v1/profiles` ?) | Un seul appel dans `AiClient` | Non |
| 8 | Dataset des 100 destinations : format, identifiant stable d'une version à l'autre | Import dans `Catalog` | **Oui, pour l'import** |
| 9 | Relation destination / ville : une destination est-elle une ville ? | Modèle `Catalog` (`cityId`) | Non |

Points internes encore ouverts : durée de vie des propositions en cache, durées de
conservation des messages et des événements analytics (RGPD), publication d'avis au MVP,
Catalog dans Travel ou à part.

## Message prêt à envoyer à l'équipe IA

> Merci pour les 8 profils, l'ordre des dimensions et les réponses. Il nous reste :
> 1. Le chatbot et la génération d'itinéraire (planning jour par jour) sont bien côté backend ?
> 2. Les vecteurs des 100 destinations sont chez vous (on ne vous envoie que le vecteur utilisateur) ?
> 3. Plage de valeurs du vecteur (0 à 1 ?) et normalisation ?
> 4. Format exact de `responses` (clés, valeurs A/B/C/D) ?
> 5. Les 12 questions : route à exposer, ou on les stocke de notre côté ?
> 6. Chemin exact de la route des profils, et date prévue pour les codes ?
> 7. Dataset des 100 destinations : format (CSV/JSON), identifiant stable d'une version à l'autre ?
> 8. Une destination correspond-elle à une ville, ou à un lieu plus précis ?