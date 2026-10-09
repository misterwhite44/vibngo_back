# Microservices

Proposition de découpage, à valider : les frontières n'ont pas encore été fixées, ceci est
une base de discussion construite à partir de `pg-liste.md`, `mongo-liste.md`,
`redis-liste.md` et des appels de `schema.md`.

## Comment définir un microservice

Un microservice = une capacité métier qui possède ses données et peut être déployée,
modifiée et mise à l'échelle sans toucher aux autres. Pour trouver les frontières, on se
pose ces questions dans l'ordre :

1. **Qui possède quelles données ?** Chaque microservice est seul à écrire dans ses
   tables. Deux services qui ont besoin de faire des jointures entre leurs données vont
   ensemble.
2. **Qui s'appelle tout le temps ?** Deux services qui échangent à chaque requête, ou qui
   doivent rester cohérents ensemble (une transaction), appartiennent au même
   microservice. Chaque appel réseau en plus coûte de la latence et des risques de panne.
3. **Qui a un profil différent ?** Ce qui est lent, lourd ou fragile (les appels LLM :
   plusieurs secondes, critère de validation < 30 s) se sépare de ce qui est rapide et
   simple (lecture du catalogue) : on ne les met pas à l'échelle ni ne les redémarre de la
   même façon.
4. **Qui change à quel rythme ?** Ce qui évolue indépendamment, ou est géré par des
   personnes différentes, se sépare.
5. **Commencer gros, découper plus tard.** Pour une petite équipe, peu de microservices
   larges valent mieux qu'une dizaine de minuscules : un découpage trop fin multiplie les
   appels réseau, les déploiements et les problèmes de cohérence. Le doc "Choix des
   technologies" le dit aussi : un microservice se justifie "si un domaine le justifie".

Test rapide pour chaque paire de services : *peut-on modifier et déployer A sans toucher
B ? A a-t-il besoin de joindre les tables de B ?* Si non à la première ou oui à la
seconde, ils vont dans le même microservice.

## Application à Triply : 3 microservices

| Microservice | Services inclus | Données | Pourquoi ensemble |
|---|---|---|---|
| **Identity** | Authentification, User, User_type, Settings, Notification (B) | PostgreSQL (schéma identity), Redis Session | Tout tourne autour du compte utilisateur. `User` → `User_type` et `Settings` sont couplés ; `Authentification` émet les JWT que tout le monde vérifie. |
| **Travel** | Catalog, Travel, Travel_history, Favorites, Commentary | PostgreSQL (schéma travel), Redis cache fiches + Queue | Ils partagent les mêmes données : `Favorites` et `Commentary` pointent vers `Catalog`, `GET /activities/:id` joint avis et fiche, `Travel` référence les activités du `Catalog`. |
| **IA** | Itinerary_generation, Chatbot, Chatbot_history, Analytics (B) | MongoDB, Redis cache IA | Tout ce qui appelle le LLM : lent, coûteux, à mettre à l'échelle à part. `Itinerary_generation` ne possède aucune donnée PostgreSQL (la proposition vit dans Redis tant qu'elle n'est pas validée). |

Hors microservices :

- **API Gateway** : routage, vérification du JWT (elle transmet l'`userId` aux services),
  `Rate_limit` (B).
- **Redis** : une seule instance partagée, clés préfixées par microservice. `Cache`,
  `Session` et `Queue` sont de l'infrastructure utilisée par les microservices, pas des
  microservices.

## Schéma

`(B)` = Bonus. `──▶` appel synchrone, `┄┄▶` événement asynchrone (Redis/BullMQ).

```
                                         ┌─────────────────┐
                                         │   Front (Expo)  │
                                         └─────────────────┘
                                                  │
                                                  ▼
                                  ┌───────────────────────────────┐
                                  │          API Gateway          │
                                  │   routage · JWT · rate limit  │
                                  └───────────────────────────────┘
                                                  │
               ┌──────────────────────────────────┼──────────────────────────────────┐
               │                                  │                                  │
               ▼                                  ▼                                  ▼
┌─────────────────────────────┐    ┌─────────────────────────────┐    ┌─────────────────────────────┐
│           Identity          │    │            Travel           │    │              IA             │
├─────────────────────────────┤    ├─────────────────────────────┤    ├─────────────────────────────┤
│ Authentification            │    │ Catalog                     │    │ Itinerary_generation        │
│ User                        │    │ Travel                      │    │ Chatbot                     │
│ User_type                   │    │ Travel_history              │    │ Chatbot_history             │
│ Settings                    │    │ Favorites                   │    │ Analytics (B)               │
│ Notification (B)            │    │ Commentary                  │    │                             │
└─────────────────────────────┘    └─────────────────────────────┘    └─────────────────────────────┘
               │                                  │                                  │
               ▼                                  ▼                                  ▼
┌─────────────────────────────┐    ┌─────────────────────────────┐    ┌─────────────────────────────┐
│ PostgreSQL                  │    │ PostgreSQL                  │    │ MongoDB                     │
│ schéma identity             │    │ schéma travel               │    │       │
│ Redis : Session             │    │ Redis : cache fiches, Queue │    │                             │
└─────────────────────────────┘    └─────────────────────────────┘    └─────────────────────────────┘

Appels entre microservices :

IA        ──▶  Travel                sync     lit les candidats (Catalog), persiste à la validation, met à jour une étape (Chatbot)
IA        ──▶  Identity              sync     lit le profil voyageur pour construire le prompt
IA        ──▶  Ollama / Google Maps  externe  génération et organisation de l'itinéraire, distances/trajets
Identity  ┄┄▶  Travel                async    événement user.deleted : purge des données de l'utilisateur
Identity  ┄┄▶  IA                    async    événement user.deleted : purge des conversations et des logs
Travel    ┄┄▶  Identity              async    rappel de réservation à envoyer : Notification
```

## Microservices et bases de données

La règle de base : **chaque microservice est seul propriétaire de ses données**. Personne
d'autre ne lit ni n'écrit directement dans ses tables. Les autres passent par son API, ou
par des événements.

```
IA ──(appel API)──▶ Travel ──▶ [schéma travel]
IA ─────────── ✗ accès direct à la base interdit
```

Ce que ça change concrètement pour Triply :

- **Une base par microservice ne veut pas dire un serveur par microservice.** On peut
  garder un seul serveur PostgreSQL avec un schéma par microservice (`identity`, `travel`)
  et des droits séparés. Ce qui compte, c'est que `Travel` ne puisse jamais lire le schéma
  `identity`, pas le nombre de serveurs.
- **Plus de jointure ni de clé étrangère entre microservices.** `trips.user_id` devient un
  simple identifiant, pas une clé étrangère vers `users` (qui est chez Identity). Si IA a
  besoin du type de voyageur, elle appelle `GET /users/me/type` d'Identity au lieu de lire
  la table `user_type`.
- **MongoDB appartient à IA seul.** Redis est une instance partagée, mais chaque service
  ne touche que ses propres clés préfixées.
- **Validation d'un itinéraire** : IA appelle l'API de Travel (créer le trip), et Travel
  écrit dans son schéma. IA n'écrit jamais dans les tables de Travel.
- **Plus de cascade SQL.** Quand un compte est supprimé, Identity émet `user.deleted` et
  chaque service purge ses propres données.

Le coût : pas de transaction qui couvre plusieurs services, et les jointures se remplacent
par des appels ou des copies de données. En échange, on peut changer le schéma d'un
service sans casser les autres.

## Ce qui reste à trancher

- **`Catalog` dans Travel ou à part ?** C'est le premier candidat à l'extraction (lecture
  massive, très cacheable), mais le séparer casse la jointure avis/favoris/fiche.
- **`Notification` (B)** est dans Identity pour l'instant ; à extraire si les notifications
  prennent de l'ampleur.
- **Sync ou async** pour chaque appel : proposé ci-dessus selon la règle "sync si
  l'utilisateur attend la réponse, async sinon". À confirmer.
- **`Itinerary_generation` est listé dans `pg-liste.md`** mais ne possède aucune donnée
  PostgreSQL : si tu valides ce découpage, il passe dans IA, et les endpoints
  `/trips/generate` de `api/postgres/` sont servis par ce microservice.
