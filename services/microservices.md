# Microservices

Découpage retenu : **Identity, Travel, Assistant**, plus une API Gateway. Les frontières
restent révisables (voir « Ce qui reste à trancher »).

## Comment définir un microservice

Un microservice = une capacité métier qui possède ses données et peut être déployée,
modifiée et mise à l'échelle sans toucher aux autres. Questions, dans l'ordre :

1. **Qui possède quelles données ?** Chaque microservice est seul à écrire dans ses tables.
   Deux services qui doivent se joindre vont ensemble.
2. **Qui s'appelle tout le temps ?** Deux services qui échangent à chaque requête ou doivent
   rester cohérents ensemble (transaction) vont ensemble : chaque appel réseau coûte de la
   latence et des risques de panne.
3. **Qui a un profil différent ?** Ce qui est lent, lourd ou fragile (appels LLM, plusieurs
   secondes, critère < 30 s) se sépare de ce qui est rapide (lecture du catalogue).
4. **Qui change à quel rythme ?** Ce qui évolue indépendamment se sépare.
5. **Commencer gros, découper plus tard.** Peu de microservices larges valent mieux qu'une
   dizaine de minuscules pour une petite équipe.

Test rapide pour chaque paire : *peut-on modifier et déployer A sans toucher B ? A a-t-il
besoin de joindre les tables de B ?* Si non à la première ou oui à la seconde : même
microservice.

## Application à vibngo : 3 microservices

| Microservice | Services inclus | Données | Pourquoi ensemble |
|---|---|---|---|
| **Identity** | Authentification, User, User_type, Settings, Notification (B) | PostgreSQL (schéma identity), Redis Session | Tout tourne autour du compte. `User` → `User_type` et `Settings` sont couplés ; l'authentification émet les JWT que tout le monde vérifie. |
| **Travel** | Catalog, Travel, Travel_history, Favorites, Commentary | PostgreSQL (schéma travel), Redis cache fiches, Queue | Données partagées : `Favorites` et `Commentary` pointent vers `Catalog`, `GET /activities/:id` joint avis et fiche, `Travel` référence les activités du `Catalog`. |
| **Assistant** | Itinerary_generation, Recommendation, Chatbot, Chatbot_history, Analytics (B) | MongoDB, Redis cache, propositions | Tout ce qui orchestre l'intelligence : lent, coûteux, à dimensionner à part. N'a aucune donnée PostgreSQL : la proposition vit dans Redis tant qu'elle n'est pas validée. |

**Nom « Assistant ».** Il remplace l'ancien nom « IA », qui prêtait à confusion avec le
**service IA de l'équipe IA** (questionnaire, vecteurs, similarité). Les deux sont
distincts : *Assistant* est un microservice du backend, *service IA* est externe.

Hors microservices :

- **Service IA** (équipe IA) : externe, sans état, appelé via `AiClient` (`contrat-service-ia.md`).
- **Ollama, Google Maps** : externes, derrière `LlmClient` et `RoutingProvider`.
- **API Gateway** : routage, JWT, `Rate_limit` (B).
- **Redis** : deux rôles (`redis-core`, `redis-cache`), clés préfixées par microservice.
  `Cache`, `Session` et `Queue` sont de l'infrastructure, pas des microservices.

Schéma complet et appels : `schema.md`.

## Microservices et bases de données

Règle : **chaque microservice est seul propriétaire de ses données.** Les autres passent par
son API ou par des événements.

```
Assistant ──(appel API)──▶ Travel ──▶ [schéma travel]
Assistant ─────────── ✗ accès direct à la base interdit
```

- Un serveur PostgreSQL peut héberger un schéma par microservice, avec des droits séparés.
- Pas de jointure ni de clé étrangère entre microservices : `trips.user_id` est un simple
  identifiant. Si Assistant a besoin du profil voyageur, il appelle Identity.
- MongoDB appartient à Assistant seul. Chaque microservice ne touche que ses clés Redis.
- **Validation d'un itinéraire** : Assistant appelle l'API interne de Travel (créer le trip),
  Travel écrit dans son schéma.
- **Suppression de compte** : Identity émet `user.deleted`, chaque service purge ses données
  et confirme.

Le coût : pas de transaction qui couvre plusieurs services, et les jointures sont remplacées
par des appels ou des copies de données.

## Ce qui reste à trancher

- **`Catalog` dans Travel ou à part ?** Premier candidat à l'extraction (lecture massive,
  très cacheable), mais le séparer casse la jointure avis/favoris/fiche.
- **`Notification` (B)** est dans Identity ; à extraire si elle prend de l'ampleur.
- **`pg-liste.md`** contient encore `Itinerary_generation`, qui ne possède aucune donnée
  PostgreSQL : il appartient à Assistant.