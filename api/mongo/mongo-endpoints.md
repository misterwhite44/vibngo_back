# API MongoDB (microservice Assistant) — endpoints

Périmètre **MongoDB** du microservice Assistant : `Chatbot`, `Chatbot_history`, `Analytics`.
Conventions : `../conventions.md`. Corps des requêtes et collections : `schemas.md`.

**Source de vérité** pour ces routes : `../assistant/endpoints.md` ne les répète pas.

**Origine de chaque élément** : `Doc` = repris des documents du projet ; `Décidé` = tranché
ensemble ; `Proposé` = proposition à valider.

## Chatbot (`Chatbot`)

Au MVP, le chatbot est basique et **ne modifie pas l'itinéraire** (MoSCoW, roadmap).

| Méthode | Endpoint | Description | Auth | Phase | Origine |
|---|---|---|---|---|---|
| POST | `/chatbot/conversations` | Ouvre une conversation (liée optionnellement à un itinéraire) | oui | MVP | Décidé |
| POST | `/chatbot/conversations/:id/messages` | Envoie un message, retourne la réponse | oui | MVP | Doc |
| POST | `/chatbot/proposals/:proposalId/confirm` | Valide une modification d'itinéraire proposée | oui | V1.2 | Doc |
| POST | `/chatbot/proposals/:proposalId/reject` | Refuse une modification proposée | oui | V1.2 | Doc |

## Historique des conversations (`Chatbot_history`)

| Méthode | Endpoint | Description | Auth | Phase | Origine |
|---|---|---|---|---|---|
| GET | `/chatbot/conversations` | Conversations de l'utilisateur, plus récentes d'abord | oui | MVP | Doc |
| GET | `/chatbot/conversations/:id` | Détail d'une conversation (sans les messages) | oui | MVP | Proposé |
| GET | `/chatbot/conversations/:id/messages` | Messages d'une conversation, paginés | oui | MVP | Doc |
| DELETE | `/chatbot/conversations/:id` | Supprime une conversation et ses messages (RGPD) | oui | MVP | Doc (droit à l'effacement) |

## Analytics (`Analytics`)

| Méthode | Endpoint | Description | Auth | Phase | Origine |
|---|---|---|---|---|---|
| POST | `/analytics/events` | Enregistre des événements `recommendation_viewed` / `recommendation_clicked` ; traitement asynchrone | oui | B | Décidé |

Les événements `funnel_step` sont émis **par le backend lui-même**, sans route. Aucune route
de lecture pour l'utilisateur : la consultation est un usage interne.

## Ce dont cette partie dépend (appels sortants)

| Besoin | Appel | Quand | Origine |
|---|---|---|---|
| Code de profil de l'utilisateur | `GET /internal/users/:id/type` (Identity) | À chaque réponse du chatbot | Proposé |
| Itinéraire lié à la conversation | `GET /internal/trips/:id?userId=` (Travel) | À l'ouverture avec `tripId` (vérifie l'appartenance) et à chaque réponse | Proposé |
| Réponse du modèle | `LlmClient` (Ollama) | À chaque message | Doc |
| Appliquer une modification validée | `POST /internal/trips/:id/changes` (Travel) | V1.2 seulement | Doc |

## Événement consommé

- `user.deleted` (émis par Identity) : supprime les `conversations`, `messages` et
  `analytics_events` de l'utilisateur, puis confirme. *(Doc : `microservices.md`)*

## Comportements

- **Réponse du chatbot** *(Décidé)* : le message de l'utilisateur est enregistré **avant**
  l'appel au modèle, la réponse **après**. Si le modèle est indisponible, le message reste
  enregistré et la réponse est `503` (`retryable: true`) ; le front peut proposer
  « Réessayer ». Cible : moins de 5 secondes *(Doc)*.
- **Titre** *(Décidé)* : créé automatiquement à partir des premiers mots du premier message
  (coupé à 50 caractères). Aucun appel au modèle, aucune route.
- **Idempotence** *(Proposé)* : `POST .../messages` accepte `Idempotency-Key` (mémorisée dans
  `redis-core`). Un réessai ne crée ni doublon ni second appel au modèle.
- **Limite de requêtes** *(Proposé)* : routes du chatbot limitées par utilisateur (valeurs à
  décider) ; `429` au-delà.
- **Résumé** *(Doc : après 10 échanges ; mécanisme Proposé)* : tâche en arrière-plan via
  `Queue`, jamais pendant la réponse. `GET .../messages` renvoie toujours les messages d'origine.
- **Analytics** *(Doc)* : répond `202` immédiatement et ne ralentit jamais une action ; si
  l'écriture échoue, l'événement est perdu sans impact visible.
- **Isolation** *(Proposé)* : la conversation d'un autre utilisateur répond `404`, jamais `403`.
- **RGPD** *(Doc)* : le contenu des messages et des événements n'apparaît jamais dans les logs
  techniques ; `userId` est l'identifiant interne (UUID), jamais l'email ni le nom.