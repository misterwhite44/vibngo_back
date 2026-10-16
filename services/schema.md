# Schéma des services 

Vue d'ensemble des services et de leur regroupement en microservices. Le détail de chaque
service est dans `service.md`, la méthode de découpage dans `microservices.md`, les
décisions et points ouverts dans `decisions.md`.

**Périmètre : backend uniquement.** Le service IA de l'équipe IA (questionnaire, vecteurs,
similarité, recommandation de destinations) est une dépendance externe appelée via API. Le
backend ne recalcule jamais ce qu'il calcule. Contrat : `contrat-service-ia.md`.

`(B)` = Bonus, hors MVP strict. `──▶` appel synchrone (REST). `┄┄▶` événement asynchrone
(Redis/BullMQ).

## Vue d'ensemble

```
                         ┌──────────────────────────┐
                         │   Front (React Native)   │
                         └──────────────────────────┘
                                      │ HTTPS · /api/v1
                                      ▼
                    ┌───────────────────────────────────┐
                    │            API Gateway            │
                    │   routage · JWT · rate limit (B)  │
                    └───────────────────────────────────┘
                                      │ réseau privé
         ┌────────────────────────────┼────────────────────────────┐
         ▼                            ▼                            ▼
┌──────────────────┐        ┌──────────────────┐        ┌────────────────────┐
│     Identity     │        │      Travel      │        │     Assistant      │
├──────────────────┤        ├──────────────────┤        ├────────────────────┤
│Authentification  │        │Catalog           │        │Itinerary_generation│
│User              │        │Travel            │        │Recommendation      │
│User_type         │        │Travel_history    │        │Chatbot             │
│Settings          │        │Favorites         │        │Chatbot_history     │
│Notification (B)  │        │Commentary        │        │Analytics (B)       │
└──────────────────┘        └──────────────────┘        └────────────────────┘
         │                            │                            │
         ▼                            ▼                            ▼
┌──────────────────┐        ┌──────────────────┐        ┌────────────────────┐
│ PostgreSQL       │        │ PostgreSQL       │        │ MongoDB            │
│ schéma identity  │        │ schéma travel    │        │ Redis : cache,     │
│                  │        │                  │        │ propositions       │
└──────────────────┘        └──────────────────┘        └────────────────────┘

Infrastructure Redis (voir « Règles d'architecture ») :
  redis-core   sessions/révocation JWT, files BullMQ, clés d'idempotence, propositions   (aucune éviction)
  redis-cache  cache des fiches, des classements et des générations                       (éviction autorisée)

Dépendances externes (appelées uniquement via un client dédié) :

┌──────────────────────┬──────────────────────┬──────────────────────────┐
│ Service IA           │ Ollama (LLM local)   │ Google Maps (API)        │
│ équipe IA            │ via LlmClient        │ via RoutingProvider      │
└──────────────────────┴──────────────────────┴──────────────────────────┘
```

## Appels clés entre services

```
Auth                  ──▶  Session (Redis)      révocation JWT (déconnexion, compte compromis)
Identity (User)       ──▶  Service IA           envoie les réponses A/B/C/D, reçoit vecteur + code de profil
Identity (User_type)  ──▶  Service IA           lit le référentiel des 8 profils (code, nom, description), mis en cache
User                  ──▶  User_type            enregistre le résultat renvoyé par l'IA
Assistant             ──▶  Identity             lit le profil voyageur (scores + code de profil)
Recommendation        ──▶  Service IA           demande le classement des destinations pour un profil
Recommendation        ──▶  Travel (Catalog)     complète le classement avec les fiches (lecture en lot)
Recommendation        ──▶  Cache                classement déjà calculé pour ce profil ?
Itinerary_generation  ──▶  Cache                résultat déjà calculé pour ces contraintes ?
Itinerary_generation  ──▶  Recommendation       destinations/candidats classés
Itinerary_generation  ──▶  Travel (Catalog)     lit les activités candidates
Itinerary_generation  ──▶  Ollama / Google Maps génération, organisation, distances (via LlmClient, RoutingProvider)
Itinerary_generation  ──▶  Travel               crée l'itinéraire SI l'utilisateur valide
Chatbot               ──▶  Chatbot_history      lecture / écriture de l'historique de conversation
Chatbot               ──▶  Ollama               réponse (via LlmClient)
Chatbot               ──▶  Travel               met à jour une étape SI l'utilisateur valide (V1.2)
Chatbot               ┄┄▶  Analytics (B)        log asynchrone, sans bloquer la réponse
Notification (B)      ┄┄▶  Queue                envoi différé via BullMQ
Identity              ┄┄▶  Travel, Assistant    événement user.deleted : purge des données
Travel                ┄┄▶  Identity             rappel de réservation à envoyer (Notification)
```

## Répartition Backend / Service IA

| Sujet                                          | Service IA   | Backend                                        |
|------------------------------------------------|:------------:|------------------------------------------------|
| 12 questions et association aux 6 dimensions   | ✔ définit    | transmet les réponses (source des questions : à confirmer) |
| Conversion A/B/C/D en valeurs                  | ✔            | envoie les lettres, jamais des nombres         |
| Vecteur utilisateur à 6 dimensions             | ✔ calcule    | stocke (Identity)                              |
| Traveler profile final                         | ✔ calcule    | stocke le code et expose (Identity)            |
| Similarité et classement des destinations      | ✔ calcule    | appelle, met en cache, expose (Assistant)      |
| Liste des 100 destinations, vecteurs           | ✔ produit    | stocke le contenu affichable (Travel/Catalog)  |
| Chatbot, génération d'itinéraire               | à confirmer  | ✔ (Assistant) — hypothèse                      |
| Utilisateur, authentification, sessions        |              | ✔ (Identity)                                   |
| Persistance et lien avec l'utilisateur         | sans état    | ✔                                              |

Le service IA est **sans état** (confirmé par l'équipe IA) : il reçoit les données,
calcule, renvoie. On ne lui envoie donc aucun identifiant d'utilisateur.

## Règles d'architecture

1. **Propriété des données.** Chaque microservice est seul à écrire dans ses données. Aucun
   accès direct à la base d'un autre : uniquement son API ou des événements. Un serveur
   PostgreSQL peut héberger plusieurs schémas (`identity`, `travel`) avec des droits séparés.
   Pas de clé étrangère entre microservices : `trips.user_id` est un simple identifiant.
2. **Services sans état.** Aucun état en mémoire. Sessions, cache, files et propositions sont
   dans Redis, ce qui permet de répliquer chaque microservice horizontalement.
3. **REST entre services** : JSON, OpenAPI par microservice, versionné (`/api/v1`), erreurs au
   format `application/problem+json`, pagination par curseur.
4. **Asynchrone (BullMQ/Redis)** pour ce qui n'a pas besoin de bloquer l'utilisateur :
   notifications, export du carnet, analytics, purge RGPD, ingestion de données.
5. **Appels sortants protégés.** Chaque appel (autre microservice, service IA, Ollama, Google
   Maps) a un timeout, un nombre limité de réessais avec attente croissante et un circuit
   breaker. Les clients sont isolés derrière des interfaces : `AiClient`, `LlmClient`,
   `RoutingProvider`. Aucune logique métier ne connaît l'URL ni le format brut d'un
   fournisseur.
6. **Dégradation maîtrisée.** Si le service IA est lent ou indisponible : dernier classement
   en cache, sinon destinations populaires ; le profil reste « en attente » et son calcul est
   relancé via `Queue`. Jamais d'erreur bloquante pour toute l'application.
7. **Aucune écriture sans validation** : `Itinerary_generation` et `Chatbot` produisent des
   propositions. Seul `Travel` persiste, après accord explicite de l'utilisateur.
8. **Génération asynchrone.** Une génération peut durer jusqu'à 30 secondes : la requête
   répond `202` avec un identifiant de tâche, le résultat se lit ensuite.
9. **Idempotence.** Les écritures rejouables (questionnaire, confirmation d'itinéraire,
   envoi de message) acceptent un header `Idempotency-Key`, mémorisé dans `redis-core`.
10. **Redis en deux rôles.** `redis-cache` accepte l'éviction ; `redis-core` n'en accepte
    aucune (exigence de BullMQ) et est persistant. Clés préfixées par microservice
    (`identity:`, `travel:`, `assistant:`).
11. **Gateway et sécurité.** La gateway vérifie localement la signature du JWT (jeton d'accès
    de courte durée) et lit en lecture seule la liste de révocation dans `redis-core`
    (format de clé documenté par Identity). Elle injecte l'identité dans un en-tête interne.
    Les microservices sont sur un réseau privé ; les routes `/internal/...` ne passent jamais
    par la gateway et exigent un jeton de service.
12. **RGPD.** Minimisation : le service IA ne reçoit jamais d'identifiant d'utilisateur ; le
    LLM reçoit un code de profil, jamais le vecteur brut, ni nom, ni email. Chiffrement en
    transit et au repos. Réponses au questionnaire, vecteur et profil (données de
    personnalité) chiffrés et supprimés avec le compte. Suppression : événement `user.deleted`,
    puis chaque microservice purge et confirme (travail durable, réessais, file des échecs
    surveillée). Google Maps et Ollama figurent au registre de traitement.
13. **Qualité de code.** Clean Architecture dans chaque microservice : `controller` (routes
    fines) → `service` (métier) → `repository` (interface ; ORM derrière). DTO validés
    (`class-validator`), SOLID, configuration par variables d'environnement, migrations
    versionnées exécutées par le déploiement, tests unitaires et d'intégration (Definition of
    Done), `correlationId` sur tous les appels, logs structurés sans donnée personnelle,
    `/health` par microservice.