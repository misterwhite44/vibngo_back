# API PostgreSQL — endpoints

Endpoints des services adossés à PostgreSQL (`services/pg-liste.md`). Voir
`services/service.md` pour ce que fait chaque service, `services/schema.md` pour leurs
relations entre eux.

## Conventions

- Base : `/api`. Toutes les routes ci-dessous sont relatives à cette base
  (ex : `POST /trips/generate` = `POST /api/trips/generate`).
- Auth : header `Authorization: Bearer <access_token>` sur toutes les routes sauf
  `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh`.
- Réponses en JSON. Erreurs standard : `401` (non authentifié), `403` (non autorisé),
  `404` (introuvable), `422` (validation).
- **Pattern proposition/validation** (voir `flux/principal.md`) : `/trips/generate`
  renvoie une *proposition* non persistée. Rien n'est écrit en base tant qu'un endpoint
  `.../confirm` n'a pas été appelé explicitement par l'utilisateur.

---

## Authentification (`Auth`)

| Méthode | Endpoint | Description | Auth |
|---|---|---|---|
| POST | `/auth/register` | Créer un compte (email, mot de passe) | non |
| POST | `/auth/login` | Connexion, retourne `access_token` + `refresh_token` | non |
| POST | `/auth/refresh` | Renouvelle l'`access_token` à partir du `refresh_token` | non |
| POST | `/auth/logout` | Révoque la session courante | oui |

## Compte & profil voyageur (`User`, `User_type`, `Settings`)

| Méthode | Endpoint | Description | Auth |
|---|---|---|---|
| GET | `/users/me` | Compte de l'utilisateur connecté | oui |
| PATCH | `/users/me` | Mise à jour du compte (email, téléphone...) | oui |
| DELETE | `/users/me` | Suppression du compte | oui |
| GET | `/users/me/questionnaire` | Questions du test de personnalité voyageur | oui |
| POST | `/users/me/questionnaire` | Soumet les réponses ; déclenche le calcul de `User_type` | oui |
| GET | `/users/me/type` | Profil voyageur calculé (type dominant + scores) | oui |
| GET | `/users/me/settings` | Préférences (confidentialité, notifications) | oui |
| PATCH | `/users/me/settings` | Modifie les préférences | oui |

## Notifications (`Notification`, Bonus)

| Méthode | Endpoint | Description | Auth |
|---|---|---|---|
| GET | `/notifications` | Notifications de l'utilisateur connecté | oui |
| PATCH | `/notifications/:id/read` | Marque une notification comme lue | oui |

## Catalogue (`Catalog`)

| Méthode | Endpoint | Description | Auth |
|---|---|---|---|
| GET | `/destinations` | Liste des destinations (filtrable par ville/pays) | oui |
| GET | `/destinations/:id` | Fiche détaillée d'une destination | oui |
| GET | `/destinations/:id/activities` | Activités/hébergements de cette destination | oui |
| GET | `/activities/:id` | Fiche détaillée d'une activité | oui |

## Génération d'itinéraire (`Itinerary_generation`)

| Méthode | Endpoint | Description | Auth |
|---|---|---|---|
| POST | `/trips/generate` | Soumet le formulaire de besoins ; retourne une proposition (`proposalId` + itinéraire), pas encore sauvegardée | oui |
| POST | `/trips/generate/:proposalId/regenerate` | Rejette la proposition, en redemande une autre | oui |
| POST | `/trips/generate/:proposalId/confirm` | Valide la proposition → persistée via `Travel`, retourne le `trip` créé | oui |

## Itinéraires (`Travel`)

| Méthode | Endpoint | Description | Auth |
|---|---|---|---|
| GET | `/trips` | Itinéraires actifs/à venir de l'utilisateur | oui |
| GET | `/trips/:id` | Détail d'un itinéraire (jours, étapes, transport) | oui |
| PATCH | `/trips/:id` | Édition générale (dates, titre...) | oui |
| DELETE | `/trips/:id` | Supprime un itinéraire | oui |
| PATCH | `/trips/:id/steps/:stepId` | Modifie une étape (remplacer l'activité, horaires...) | oui |
| DELETE | `/trips/:id/steps/:stepId` | Supprime une étape | oui |
| POST | `/trips/:id/bookings` | Ajoute une référence de réservation | oui |

## Historique & carnet (`Travel_history`)

| Méthode | Endpoint | Description | Auth |
|---|---|---|---|
| GET | `/trips/history` | Itinéraires terminés | oui |
| GET | `/trips/:id/journal` | Carnet de voyage associé | oui |
| POST | `/trips/:id/journal` | Ajoute une entrée (photo, note) au carnet | oui |
| GET | `/trips/:id/journal/export` | Export du carnet (PDF) | oui |

## Favoris (`Favorites`)

| Méthode | Endpoint | Description | Auth |
|---|---|---|---|
| GET | `/favorites` | Favoris de l'utilisateur | oui |
| POST | `/favorites` | Ajoute une destination/activité/ville en favori | oui |
| DELETE | `/favorites/:id` | Retire un favori | oui |

## Avis (`Commentary`)

| Méthode | Endpoint | Description | Auth |
|---|---|---|---|
| GET | `/activities/:id/reviews` | Avis sur une activité | oui |
| POST | `/activities/:id/reviews` | Publie un avis (note + texte) | oui |
| DELETE | `/reviews/:id` | Supprime son propre avis | oui |
