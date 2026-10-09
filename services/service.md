# Services — documentation

Ce que fait chaque service, regroupé par microservice (voir `microservices.md`). Un service
= un module NestJS (classes injectables) portant une responsabilité métier précise. Relations
entre services : `schema.md`. Endpoints : `../api/<microservice>/endpoints.md`.

Phases : **MVP**, **V1.1**, **V1.2**, **V2.0** (voir la roadmap), **B** = Bonus.

## Conventions communes

- **Structure d'un module** : `controller` (routes fines, aucune logique) → `service` (métier)
  → `repository` (interface ; l'ORM reste derrière). Les DTO valident toutes les entrées et
  n'exposent jamais une entité de base directement.
- **Principes** : une responsabilité par classe (SOLID), injection de dépendances, aucun
  secret en dur.
- **API** : versionnée (`/api/v1`), documentée en OpenAPI, erreurs `problem+json`, listes
  paginées. Détail : `../api/conventions.md`.
- **Appels externes** : uniquement via `AiClient`, `LlmClient` ou `RoutingProvider`, avec
  timeout, réessais limités et circuit breaker.
- **Tests** : unitaires sur le métier, d'intégration sur les endpoints, Definition of Done.

---

# Microservice Identity

Données : PostgreSQL (schéma `identity`), Redis `Session`.

**Authentification** (MVP)
Inscription, connexion par email/mot de passe et par OAuth (Google, Apple), hash du mot de
passe, émission et vérification des JWT (access de courte durée + refresh), réinitialisation
du mot de passe. Les révocations (déconnexion, compte compromis) sont écrites dans
`Session` ; la gateway les lit en lecture seule.

**User** (MVP)
Compte utilisateur et collecte des réponses au questionnaire de personnalité. Transmet les
réponses **A/B/C/D** au service IA via `AiClient`, sans les interpréter, puis demande à
`User_type` d'enregistrer le résultat. Si l'IA est indisponible, les réponses sont
enregistrées et le calcul est relancé via `Queue` (profil « en attente »). Émet
`user.deleted` à la suppression du compte.

**User_type** (MVP)
Stocke et expose le résultat calculé par l'IA : scores nommés par dimension (`urbanite`,
`intensite`, `planification`, `social`, `confort`, `decouverte`), code du traveler profile,
`modelVersion`, `questionnaireVersion`. **Ne calcule rien.** Le vecteur reçu de l'IA (tableau) est converti en scores nommés par
`AiClient`. Il sert aussi le référentiel des 8 profils (code stable, nom, description), lu
auprès du service IA et mis en cache : le nom et la description peuvent évoluer, seul le
code est stocké chez les utilisateurs. Conserve aussi les réponses
A/B/C/D : le service IA étant sans état, c'est la seule façon de recalculer un profil si
le modèle change. Ces données de personnalité sont chiffrées au repos et supprimées avec le
compte. Expose le profil aux autres microservices via `/internal`.

**Settings** (MVP ; réglages avancés de vie privée : Could)
Paramètres de confidentialité et de notifications (géolocalisation, visibilité
communautaire). `offlineModeEnabled` est un paramètre préparé d'avance : le mode hors-ligne
lui-même est en V2.0.

**Notification** (B)
Envoi des notifications push (rappels, alertes). Empile les envois différés dans `Queue`.

---

# Microservice Travel

Données : PostgreSQL (schéma `travel`), Redis cache des fiches, `Queue` (export du carnet).

**Catalog** (MVP)
Contenu consultable : les 100 destinations du MVP, activités, hébergements, partenaires,
fiches et photos. Chaque destination a une clé interne (UUID) et un `sourceId`, l'identifiant
fourni par l'équipe IA, unique et jamais modifié ; l'import du fichier de l'équipe IA est
idempotent (il met à jour par `sourceId`). `recommendedProfiles` contient des codes de
traveler profile (chaînes, pas d'enum), validés à l'import contre la liste des 8 profils. Sert les pages Destination/Activité et fournit les
fiches en lot (`GET /internal/destinations?sourceIds=`). **Aucun calcul de similarité ni de
génération.** Ne stocke aucun vecteur de destination (hypothèse : l'IA les détient).

**Travel** (MVP)
Persistance et édition d'un itinéraire confirmé : jours, étapes, transport, références de
réservation. Reçoit la première version d'`Itinerary_generation` après validation
(`POST /internal/trips`), puis gère les modifications manuelles (modifier, remplacer,
supprimer une étape). Les modifications proposées par `Chatbot` arrivent en V1.2.

**Travel_history** (carnet : V1.2)
Itinéraires terminés et carnet de voyage (photos, notes, export PDF via `Queue`).

**Favorites** (MVP)
Destinations, activités ou villes en favori (« favori » ou « envisagée »).

**Commentary** (consultation des avis : MVP ; publication : à confirmer)
Avis et commentaires sur les activités/destinations (note, texte, modération basique). La
note moyenne n'est affichée qu'à partir d'un nombre minimum d'avis.

---

# Microservice Assistant

Données : MongoDB, Redis `Cache` (classements, générations) et propositions en cours.

**Recommendation** (MVP)
Expose les destinations recommandées. Lit le profil auprès d'Identity, demande le classement
au service IA (`AiClient`, avec le vecteur et sans identifiant d'utilisateur), complète le
résultat avec les fiches de `Catalog`, met en cache. Clé de cache : empreinte du profil +
filtres + `modelVersion`. Si l'IA est indisponible : dernier classement en cache, sinon
destinations populaires (réponse marquée `degraded`).

**Itinerary_generation** (MVP)
Orchestre la génération à partir du formulaire de besoins. Vérifie `Cache`, lit les
candidats via `Recommendation` et `Catalog`, appelle Ollama (`LlmClient`) pour choisir et
organiser le planning et Google Maps (`RoutingProvider`) pour les distances (voir
`../flux/principal.md`). **Valide ensuite le résultat par des règles de code** (pas de
chevauchement, horaires cohérents, trajets réalistes, budget) avant de le proposer.
Fonctionne en asynchrone : la requête renvoie un identifiant de tâche. Produit une
*proposition* conservée dans Redis (durée de vie limitée) ; ne persiste rien lui-même et ne
crée l'itinéraire dans `Travel` que si l'utilisateur valide.

**Chatbot** (MVP basique ; modification d'itinéraire : V1.2)
Gère un échange en cours : construit le contexte (profil sous forme de code, itinéraire lié,
derniers échanges), appelle Ollama (`LlmClient`), retourne la réponse. Au MVP il ne modifie
pas l'itinéraire. En V1.2, il peut renvoyer une *proposition* de modification, appliquée à
`Travel` seulement après validation. Les prompts sont versionnés dans le dépôt.

**Chatbot_history** (MVP)
Stocke et relit l'historique ; compresse en résumé au-delà de 10 échanges pour garder un
contexte léger.

**Analytics** (B)
Journalise les événements d'interaction (affichage et clic sur une recommandation, étapes du
parcours) de façon asynchrone, sans jamais ralentir une réponse.

---

# Infrastructure partagée (hors microservices)

**API Gateway** — routage, vérification du JWT, `Rate_limit` (B) ; la règle la plus spécifique
l'emporte (`/trips/generate` va à Assistant, le reste de `/trips` à Travel).

**Cache** (`redis-cache`) — fiches destination/activité, classements, générations. Clés
versionnées, durée de vie par type de donnée.

**Session** (`redis-core`) — révocation immédiate des JWT.

**Queue** (`redis-core`, BullMQ) — notifications, export du carnet, purge RGPD, relance du
calcul de profil, ingestion de données externes.

**Rate_limit** (B) — limite de requêtes par utilisateur et par route (notamment les routes
qui appellent l'IA ou Google Maps).