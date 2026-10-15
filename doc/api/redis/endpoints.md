# API Redis — endpoints

Redis est une infrastructure partagée, pas un microservice exposé directement au client.
Les routes ci-dessous sont une proposition de contrats HTTP pour les fonctionnalités qui
s'appuient sur Redis (`Session`, `Cache`, `Queue` et `Rate_limit`). Elles sont à valider
avec les contrats des services Identity, Travel et Assistant.

## Conventions

- Base : `/api`. Les chemins ci-dessous sont relatifs à cette base.
- Auth : header `Authorization: Bearer <accessToken>` sur toutes les routes sauf mention
  contraire.
- Réponses en JSON. Erreurs standard : `401` (non authentifié), `403` (non autorisé),
  `404` (introuvable), `422` (validation), `429` (limite de débit), `503` (Redis ou un
  traitement indispensable indisponible).
- Une réponse `202` signifie que le travail est accepté, pas qu'il est terminé.
- Aucun endpoint ne permet de lire ou modifier directement une clé Redis.

---

## Sessions (`Session`, Identity)

| Méthode | Endpoint | Description | Auth |
|---|---|---|---|
| POST | `/auth/logout` | Révoque la session courante jusqu'à l'expiration de son jeton | oui |
| GET | `/auth/sessions` | Liste les sessions actives de l'utilisateur | oui |
| DELETE | `/auth/sessions/:sessionId` | Révoque une session de l'utilisateur | oui |
| DELETE | `/auth/sessions` | Révoque toutes les sessions de l'utilisateur | oui |

## Génération et propositions (`Cache`, `Queue`, Assistant)

| Méthode | Endpoint | Description | Auth |
|---|---|---|---|
| POST | `/trips/generate` | Démarre une génération ; retourne un identifiant de tâche | oui |
| GET | `/trips/generations/:taskId` | Consulte l'état et, si disponible, la proposition générée | oui |
| POST | `/trips/generations/:taskId/regenerate` | Demande une nouvelle proposition à partir d'une tâche terminée | oui |
| POST | `/trips/proposals/:proposalId/confirm` | Confirme la proposition ; la persistance est déléguée à Travel | oui |
| DELETE | `/trips/proposals/:proposalId` | Abandonne une proposition non confirmée | oui |

Le cache est transparent pour le client : une réponse en cache utilise le même format
qu'un résultat calculé. Une proposition reste temporaire et liée à son propriétaire.

## Travaux asynchrones (`Queue`)

| Méthode | Endpoint | Description | Auth |
|---|---|---|---|
| POST | `/trips/:tripId/journal/exports` | Planifie l'export PDF du carnet | oui |
| GET | `/jobs/:jobId` | Consulte l'état d'un export ou d'un autre travail appartenant à l'utilisateur | oui |
| DELETE | `/jobs/:jobId` | Annule un travail encore en attente, si l'annulation est possible | oui |

Les files BullMQ restent internes. Les routes publiques créent ou consultent des travaux
auprès du service propriétaire ; elles n'exposent ni le nom des files ni leurs clés.

## Limitation de débit (`Rate_limit`, Bonus)

La limitation s'applique aux routes publiques via la Gateway, sans endpoint de gestion
Redis dédié. Une requête limitée reçoit `429 Too Many Requests` et, si possible, un
en-tête `Retry-After`. Les seuils et fenêtres sont configurés côté serveur.

## Erreurs liées à Redis

| Situation | Réponse proposée |
|---|---|
| Redis cache indisponible | Le service continue sans cache si sa source de données ou son calcul est disponible. |
| Vérification de révocation impossible | `503 Service Unavailable` ; la Gateway ne valide pas le jeton par défaut. |
| Travail non placé en file | `503 Service Unavailable` ; aucun succès `202` n'est renvoyé. |
| Travail ou proposition expiré/introuvable | `404 Not Found`. |
| Travail encore en cours | `202 Accepted` avec son état courant. |
