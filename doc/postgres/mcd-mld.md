# MCD et MLD — PostgreSQL

Sous-ticket #94 de #93. Ce document décrit les données PostgreSQL des services listés
dans `services/pg-liste.md` : Authentification, User, User_type, Settings, Notification
(Bonus), Catalog, Itinerary_generation, Travel, Travel_history, Favorites, Commentary.

Il se lit avec :

- `services/microservices.md` — le découpage qui impose **deux schémas** (`identity`,
  `travel`) et **aucune clé étrangère entre microservices** ;
- `doc/postgres/endpoints.md` et `doc/postgres/schemas.md` — les routes et les corps que
  ce schéma doit savoir servir (vérification en fin de document) ;
- `services/service.md` — ce que fait chaque service.

Deux niveaux, comme demandé par le ticket :

- le **MCD** (modèle conceptuel) : entités, associations, cardinalités. Pas de type, pas
  de clé, pas de technique ;
- le **MLD** (modèle logique) : tables, colonnes, types PostgreSQL, clés primaires, clés
  étrangères et contraintes.

Les deux schémas sont aussi fournis en PlantUML, à côté de ce document :
`mcd.puml` (notation Merise) et `mld.puml` (notation patte de corbeau). Les trois fichiers
doivent rester cohérents : toute correction ici se reporte dans les scripts, et
inversement.

## Conventions

| Sujet | Règle |
|---|---|
| Nommage | Tables au pluriel, colonnes en `snake_case`, anglais (les contrats d'API de `schemas.md` sont en `camelCase` : la conversion est faite par l'ORM) |
| Clé primaire | `id uuid` par défaut (`gen_random_uuid()`, extension `pgcrypto`). Un identifiant non devinable : il circule entre microservices et apparaît dans les URL |
| Dates | `timestamptz` pour un instant, `date` pour un jour sans heure (dates de voyage, journée d'itinéraire) |
| Horodatage | `created_at` sur toute table, `updated_at` sur toute table modifiable |
| Listes fermées techniques | `text` + `CHECK (... IN (...))` — pas de `CREATE TYPE ... AS ENUM` |
| Listes métier | Table de référence avec un **code `text` en clé primaire** (types de voyageur, axes, catégories d'activité) |
| Lien entre microservices | Colonne `uuid` nue, commentée « identifiant \<service\> ». Jamais de `REFERENCES` |
| Suppression | `ON DELETE CASCADE` à l'intérieur d'un agrégat (un voyage et ses jours), `RESTRICT` sur les référentiels, `SET NULL` sur les rattachements facultatifs |

**Pourquoi pas de type `ENUM` PostgreSQL.** Le ticket le demande explicitement pour le
profil voyageur, et on applique la même logique partout :

- le profil voyageur et les axes sont des **données métier** qui vont bouger (ajouter un
  cinquième type, renommer un axe). Avec un `ENUM`, chaque changement est un `ALTER TYPE`
  plus une regénération du client Prisma plus un déploiement ; avec une table de
  référence, c'est une ligne insérée. C'est pour ça que `traveler_types` et
  `profile_axes` sont des tables, et que `traveler_profiles.dominant_type_code` est un
  `text` ;
- les listes vraiment fermées et purement techniques (`outbound|return|intra`,
  `planned|confirmed|modified|skipped`) restent du `text` + `CHECK` : lisible dans un dump
  SQL, modifiable par une simple migration, et aucune valeur à administrer.

Conséquence : les valeurs des `CHECK` sont exactement celles des `enum(...)` de
`doc/postgres/schemas.md`. Les deux documents doivent rester alignés.

## Vue d'ensemble

Deux schémas dans un seul serveur PostgreSQL, un rôle SQL par schéma (voir
`doc/postgres/orm.md` sur `develop` pour le détail Prisma et les chaînes de connexion).

```
┌──────────────────────────────────────┐   ┌──────────────────────────────────────┐
│          schéma  identity            │   │           schéma  travel             │
│  microservice Identity               │   │  microservice Travel                 │
├──────────────────────────────────────┤   ├──────────────────────────────────────┤
│ users                                │   │ countries                            │
│ traveler_types            (référence)│   │ cities                               │
│ profile_axes              (référence)│   │ destinations                         │
│ questionnaire_questions              │   │ activity_categories       (référence)│
│ questionnaire_answers                │   │ partners                             │
│ traveler_profiles                    │   │ activities                           │
│ traveler_profile_scores              │   │ activity_media                       │
│ settings                             │   │ activity_recommended_profiles        │
│ notifications                     (B)│   │ trips                                │
│                                      │   │ trip_travelers                       │
│                                      │   │ trip_days                            │
│                                      │   │ trip_steps                           │
│                                      │   │ trip_transports                      │
│                                      │   │ bookings                             │
│                                      │   │ journal_entries                      │
│                                      │   │ journal_photos                       │
│                                      │   │ journal_exports                      │
│                                      │   │ favorites                            │
│                                      │   │ reviews                              │
└──────────────────────────────────────┘   └──────────────────────────────────────┘
                 ▲                                           ▲
                 │ rôle triply_identity                      │ rôle triply_travel
                 │                                           │
        aucun GRANT croisé : triply_travel n'a pas USAGE sur identity, et inversement

Les colonnes qui traversent la frontière (identifiants nus, pas de clé étrangère) :

travel.trips.user_id                                  ──▶  identity.users.id
travel.trip_travelers.user_id                         ──▶  identity.users.id
travel.favorites.user_id                              ──▶  identity.users.id
travel.reviews.user_id                                ──▶  identity.users.id
travel.journal_entries.user_id                        ──▶  identity.users.id
travel.journal_exports.user_id                        ──▶  identity.users.id
travel.activity_media.user_id                         ──▶  identity.users.id
travel.activity_recommended_profiles.traveler_type_code ──▶ identity.traveler_types.code
```

`Itinerary_generation` n'a **aucune table** : la proposition vit dans Redis jusqu'à la
validation (`flux/principal.md`), et c'est `Travel` qui écrit. Seule trace en base :
`trips.proposal_id`.

---

# Schéma `identity`

Services : Authentification, User, User_type, Settings, Notification (Bonus).

## MCD — `identity`

Entités — `#` marque l'identifiant, `(R)` une **identification relative** (l'entité n'est
identifiée qu'au sein de celle qui la porte), *réf.* un référentiel alimenté par le seed :

```
UTILISATEUR        # email · mot de passe · téléphone · statut · date de création
PARAMÈTRES         notifications · géolocalisation · visibilité communautaire ·
                   niveau de confidentialité · mode hors-ligne        (R) UTILISATEUR
QUESTION           # code · libellé · position · poids · inversée
AXE                # code · libellé · position                        réf.
PROFIL VOYAGEUR    date de calcul                                     (R) UTILISATEUR
TYPE VOYAGEUR      # code · libellé · description                     réf.
NOTIFICATION (B)   type · message · date d'envoi · date de lecture
```

Associations et cardinalités. Chaque cardinalité est écrite **du côté de l'entité qu'elle
décrit** — notation Merise : « une occurrence de cette entité participe de *min* à *max*
fois à cette association ». C'est l'inverse du placement des multiplicités UML, et c'est
cette convention-là qui vaut dans tout ce document et dans `mcd.puml` :

```
UTILISATEUR  (1,1)──« est paramétré par »──(1,1)  PARAMÈTRES
UTILISATEUR  (0,1)──« est profilé par »────(1,1)  PROFIL VOYAGEUR
UTILISATEUR  (0,n)──« répond »─────────────(0,n)  QUESTION          porte : valeur
UTILISATEUR  (0,n)──« reçoit »─────────────(1,1)  NOTIFICATION (B)
QUESTION     (1,1)──« mesure »─────────────(0,n)  AXE
PROFIL       (1,n)──« est noté sur »───────(0,n)  AXE               porte : score
PROFIL       (1,1)──« a pour dominante »───(0,n)  TYPE VOYAGEUR
```

Lectures utiles :

- **`UTILISATEUR (0,1) ─ (1,1) PROFIL VOYAGEUR`** : un compte existe avant d'avoir répondu
  au questionnaire — côté utilisateur, le minimum est 0. Le profil n'apparaît qu'au premier
  `POST /users/me/questionnaire`, et il appartient toujours à exactement un compte.
- **`UTILISATEUR (1,1) ─ (1,1) PARAMÈTRES`** : les paramètres sont créés avec le compte,
  avec des valeurs par défaut. `GET /users/me/settings` ne renvoie jamais `404`.
- **« répond »** est une association porteuse (la valeur de la réponse) : elle devient une
  table. On ne garde que la **réponse courante** de chaque utilisateur à chaque question —
  l'historique des soumissions n'est pas un besoin exprimé.
- **« est noté sur »** est porteuse aussi (le score sur l'axe) : une ligne par axe, pas une
  colonne par axe. Ajouter un septième axe n'est alors pas une migration. Le `(1,n)` côté
  profil dit qu'un profil calculé est noté sur tous ses axes, jamais sur aucun.

## MLD — `identity`

### `identity.users`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `email` | `text` | `NOT NULL`, unique sur `lower(email)` |
| `password_hash` | `text` | `NOT NULL` — argon2id, jamais le mot de passe |
| `phone` | `text` | `NULL` |
| `status` | `text` | `NOT NULL DEFAULT 'active'`, `CHECK (status IN ('active','suspended','deleted'))` |
| `created_at` | `timestamptz` | `NOT NULL DEFAULT now()` |
| `updated_at` | `timestamptz` | `NOT NULL DEFAULT now()` |
| `deleted_at` | `timestamptz` | `NULL` |

```sql
CREATE UNIQUE INDEX users_email_key ON identity.users (lower(email));
```

Unicité sur `lower(email)` et non sur `email` : sinon `Jean@triply.fr` et
`jean@triply.fr` sont deux comptes.

`DELETE /users/me` ne fait pas un `DELETE` SQL : `status = 'deleted'`, `deleted_at`
renseigné, email et téléphone anonymisés, puis émission de l'événement `user.deleted` que
chaque microservice consomme pour purger ses propres données
(`services/microservices.md`). La ligne reste le temps de la purge, puis est supprimée —
le calendrier exact relève du ticket RGPD, pas de celui-ci.

### `identity.traveler_types` *(référence)*

| Colonne | Type | Contraintes |
|---|---|---|
| `code` | `text` | **PK** — `explorateur`, `epicurien`, `sociable`, `connecteur` |
| `label` | `text` | `NOT NULL` |
| `description` | `text` | `NULL` |
| `is_active` | `boolean` | `NOT NULL DEFAULT true` |

C'est **ici** que se joue le « profil voyageur en texte, pas en enum » du ticket : les
quatre types sont des lignes insérées par le seed, pas des valeurs d'un type SQL.

### `identity.profile_axes` *(référence)*

| Colonne | Type | Contraintes |
|---|---|---|
| `code` | `text` | **PK** — `urbanite`, `intensite`, `planification`, `social`, `confort`, `decouverte` |
| `label` | `text` | `NOT NULL` |
| `position` | `smallint` | `NOT NULL`, `UNIQUE` — ordre d'affichage |

Les six codes sont exactement les clés de `scores` dans `GET /users/me/type`.

### `identity.questionnaire_questions`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `code` | `text` | `NOT NULL UNIQUE` — stable, utilisé par le front et le seed |
| `label` | `text` | `NOT NULL` |
| `axis_code` | `text` | `NOT NULL`, **FK** → `profile_axes(code)` `ON DELETE RESTRICT` |
| `position` | `smallint` | `NOT NULL UNIQUE` |
| `weight` | `numeric(4,2)` | `NOT NULL DEFAULT 1` — contribution au score de l'axe |
| `reverse_scored` | `boolean` | `NOT NULL DEFAULT false` — question inversée |
| `is_active` | `boolean` | `NOT NULL DEFAULT true` |

`GET /users/me/questionnaire` renvoie `axis` : c'est `axis_code`.

### `identity.questionnaire_answers`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `user_id` | `uuid` | `NOT NULL`, **FK** → `users(id)` `ON DELETE CASCADE` |
| `question_id` | `uuid` | `NOT NULL`, **FK** → `questionnaire_questions(id)` `ON DELETE RESTRICT` |
| `value` | `smallint` | `NOT NULL`, `CHECK (value BETWEEN 1 AND 5)` |
| `answered_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

```sql
ALTER TABLE identity.questionnaire_answers
  ADD CONSTRAINT questionnaire_answers_user_question_key UNIQUE (user_id, question_id);
```

L'unicité fait de `POST /users/me/questionnaire` un **upsert** : repasser le test écrase
les réponses, il n'en existe jamais deux pour la même question. `RESTRICT` sur la
question : on désactive une question (`is_active = false`), on ne la supprime pas sous les
réponses déjà collectées.

### `identity.traveler_profiles`

| Colonne | Type | Contraintes |
|---|---|---|
| `user_id` | `uuid` | **PK**, **FK** → `users(id)` `ON DELETE CASCADE` |
| `dominant_type_code` | `text` | `NOT NULL`, **FK** → `traveler_types(code)` `ON DELETE RESTRICT` |
| `computed_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

La clé primaire **est** la clé étrangère : c'est ce qui matérialise le `(1,1) ─ (0,1)` du
MCD, une ligne au plus par utilisateur.

### `identity.traveler_profile_scores`

| Colonne | Type | Contraintes |
|---|---|---|
| `user_id` | `uuid` | **FK** → `traveler_profiles(user_id)` `ON DELETE CASCADE` |
| `axis_code` | `text` | **FK** → `profile_axes(code)` `ON DELETE RESTRICT` |
| `score` | `numeric(5,2)` | `NOT NULL`, `CHECK (score BETWEEN 0 AND 100)` |

**PK** `(user_id, axis_code)` — la table de l'association porteuse « est noté sur ».

`GET /users/me/type` lit `traveler_profiles` plus ses six lignes de score et les remonte
en objet `{ urbanite: …, intensite: … }`. Six lignes plutôt que six colonnes : un axe de
plus est une ligne de seed, pas un `ALTER TABLE` plus un changement de contrat.

### `identity.settings`

| Colonne | Type | Contraintes |
|---|---|---|
| `user_id` | `uuid` | **PK**, **FK** → `users(id)` `ON DELETE CASCADE` |
| `notifications_enabled` | `boolean` | `NOT NULL DEFAULT true` |
| `geolocation_enabled` | `boolean` | `NOT NULL DEFAULT false` |
| `community_visible` | `boolean` | `NOT NULL DEFAULT true` |
| `privacy_level` | `text` | `NOT NULL DEFAULT 'standard'`, `CHECK (privacy_level IN ('standard','strict'))` |
| `offline_mode_enabled` | `boolean` | `NOT NULL DEFAULT false` |
| `updated_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

Géolocalisation à `false` par défaut : consentement explicite (voir
`documentation/Triply_officiel/Normes et conformité.pdf`). La ligne est créée dans la même
transaction que le compte.

### `identity.notifications` *(Bonus)*

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `user_id` | `uuid` | `NOT NULL`, **FK** → `users(id)` `ON DELETE CASCADE` |
| `type` | `text` | `NOT NULL` — `booking_reminder`, `trip_start`, … |
| `message` | `text` | `NOT NULL` |
| `payload` | `jsonb` | `NULL` — de quoi ouvrir le bon écran (`tripId`, `bookingId`) |
| `scheduled_at` | `timestamptz` | `NULL` — envoi différé via `Queue` |
| `sent_at` | `timestamptz` | `NULL` |
| `read_at` | `timestamptz` | `NULL` |
| `created_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

```sql
CREATE INDEX notifications_user_created_idx
  ON identity.notifications (user_id, created_at DESC);
```

`read_at` plutôt qu'un booléen `read` : même information, plus la date. L'API expose
`read: read_at IS NOT NULL`, et `PATCH /notifications/:id/read` écrit `read_at = now()`.

---

# Schéma `travel`

Services : Catalog, Travel, Travel_history, Favorites, Commentary.

## MCD — `travel`

Mêmes conventions que pour `identity` (`#` identifiant, `(R)` identification relative,
*réf.* référentiel) :

```
PAYS             # code ISO · nom
VILLE            # nom · latitude · longitude · fuseau            (R) PAYS
DESTINATION      # nom · description · image de couverture ·
                   score de popularité                            (R) VILLE
CATÉGORIE        # code · libellé · est un hébergement            réf.
PARTENAIRE       # nom · contacts
ACTIVITÉ         # nom · description · adresse · coordonnées ·
                   fourchette de prix · horaires · contacts ·
                   lien de réservation                            (R) DESTINATION
MÉDIA            url · origine (officiel / communauté)            (R) ACTIVITÉ
VOYAGE           titre · statut · dates · budget · mode de transport
JOURNÉE          # index du jour · date                           (R) VOYAGE
ÉTAPE            # ordre · type · horaires · statut · notes       (R) JOURNÉE
TRAJET           segment · mode · départ · arrivée · distance · durée
RÉSERVATION      catégorie · prestataire · référence · statut · rappel
ENTRÉE DE CARNET texte · mot résumé
PHOTO            url · position                                   (R) ENTRÉE DE CARNET
EXPORT           statut · url du PDF
FAVORI           type de cible · statut (favori / envisagée)
AVIS             note · commentaire · statut
```

`VOYAGE`, `TRAJET`, `RÉSERVATION`, `ENTRÉE DE CARNET`, `EXPORT`, `FAVORI` et `AVIS` n'ont
pas d'identifiant naturel : leur identifiant est technique (le `uuid` du MLD). Un titre de
voyage est facultatif et se répète, il ne peut pas identifier.

Associations et cardinalités (même convention : la cardinalité décrit l'entité à côté de
laquelle elle est écrite) :

```
PAYS         (0,n)──« contient »──────────────(1,1)  VILLE
VILLE        (0,n)──« héberge »───────────────(1,1)  DESTINATION
DESTINATION  (0,n)──« propose »───────────────(1,1)  ACTIVITÉ
CATÉGORIE    (0,n)──« classe »────────────────(1,1)  ACTIVITÉ
PARTENAIRE   (0,n)──« exploite »──────────────(0,1)  ACTIVITÉ
ACTIVITÉ     (0,n)──« est illustrée par »─────(1,1)  MÉDIA
ACTIVITÉ     (0,n)──« est recommandée à »─────(0,n)  TYPE VOYAGEUR  ⟵ autre microservice
ACTIVITÉ     (0,n)──« reçoit »────────────────(1,1)  AVIS

VOYAGE       (1,n)──« se déroule sur »────────(1,1)  JOURNÉE
JOURNÉE      (0,n)──« enchaîne »──────────────(1,1)  ÉTAPE
ÉTAPE        (0,1)──« réalise »───────────────(0,n)  ACTIVITÉ
VOYAGE       (0,n)──« emprunte »──────────────(1,1)  TRAJET
VOYAGE       (0,n)──« regroupe »──────────────(1,1)  RÉSERVATION
RÉSERVATION  (0,1)──« couvre »────────────────(0,1)  ÉTAPE
VOYAGE       (0,n)──« est raconté par »───────(1,1)  ENTRÉE DE CARNET
ENTRÉE       (0,1)──« illustre »──────────────(0,n)  ÉTAPE
ENTRÉE       (0,n)──« contient »──────────────(1,1)  PHOTO
VOYAGE       (0,n)──« est exporté en »────────(1,1)  EXPORT
VILLE        (0,n)──« est origine de »────────(0,1)  VOYAGE
VILLE        (0,n)──« est destination de »────(1,1)  VOYAGE

VOYAGE       (1,n)──« réunit »────────────────(0,n)  UTILISATEUR    ⟵ autre microservice
                                                      porte : rôle
FAVORI       (1,1)──« appartient à »──────────(0,n)  UTILISATEUR    ⟵ autre microservice
FAVORI       (0,1)──« cible une ville »───────(0,n)  VILLE          ⎫ exclusion (X)
FAVORI       (0,1)──« cible une destination »─(0,n)  DESTINATION    ⎬ une cible et
FAVORI       (0,1)──« cible une activité »────(0,n)  ACTIVITÉ       ⎭ une seule
AVIS         (1,1)──« est rédigé par »────────(0,n)  UTILISATEUR    ⟵ autre microservice
```

Lectures utiles :

- **ACTIVITÉ couvre aussi les hébergements.** `service.md` parle de « destinations,
  activités, hébergements, partenaires » ; l'API les sert par la même route
  (`GET /destinations/:id/activities`) avec le même corps. Une seule entité, distinguée
  par la catégorie (`activity_categories.is_accommodation`). Deux entités auraient
  dupliqué adresse, horaires, médias et avis.
- **`ÉTAPE (0,1) ─ (0,n) ACTIVITÉ`** : une étape de type `transport` ou `meal` ne pointe
  vers aucune fiche du catalogue (minimum 0 côté étape), et une même activité peut être
  programmée dans plusieurs voyages (maximum n côté activité).
- **`VOYAGE (1,n) ─ (1,1) JOURNÉE`** : un voyage a au moins une journée — un voyage sans
  journée n'aurait rien à afficher ; une journée appartient à un seul voyage.
- **VOYAGE ─ UTILISATEUR est une association porteuse vers un autre microservice** : la
  table existe (`trip_travelers`, pour `travelersUserIds` de `POST /trips/generate`), mais
  son côté `UTILISATEUR` est un identifiant nu. Le `(1,n)` côté voyage : il y a toujours
  au moins le propriétaire.
- **FAVORI a trois cibles possibles.** Une seule entité avec un couple
  (type de cible, identifiant), pas trois tables : `GET /favorites` renvoie une liste
  mélangée, et `DELETE /favorites/:id` ne connaît pas le type.
- **TYPE VOYAGEUR apparaît ici sans appartenir à ce schéma** : `recommendedProfiles` est
  une liste de codes recopiés, pas une jointure.

## MLD — `travel`

### Catalogue

#### `travel.countries`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `code` | `char(2)` | `NOT NULL UNIQUE` — ISO 3166-1 alpha-2 |
| `name` | `text` | `NOT NULL` |

#### `travel.cities`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `country_id` | `uuid` | `NOT NULL`, **FK** → `countries(id)` `ON DELETE RESTRICT` |
| `name` | `text` | `NOT NULL` |
| `latitude` | `numeric(9,6)` | `NULL`, `CHECK (latitude BETWEEN -90 AND 90)` |
| `longitude` | `numeric(9,6)` | `NULL`, `CHECK (longitude BETWEEN -180 AND 180)` |
| `timezone` | `text` | `NULL` — IANA (`Europe/Paris`) |

```sql
ALTER TABLE travel.cities
  ADD CONSTRAINT cities_country_name_key UNIQUE (country_id, name);
```

#### `travel.destinations`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `city_id` | `uuid` | `NOT NULL`, **FK** → `cities(id)` `ON DELETE RESTRICT` |
| `name` | `text` | `NOT NULL` |
| `description` | `text` | `NULL` |
| `cover_image_url` | `text` | `NULL` |
| `popularity_score` | `numeric(5,2)` | `NOT NULL DEFAULT 0`, `CHECK (popularity_score >= 0)` |
| `created_at` | `timestamptz` | `NOT NULL DEFAULT now()` |
| `updated_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

```sql
ALTER TABLE travel.destinations
  ADD CONSTRAINT destinations_city_name_key UNIQUE (city_id, name);

CREATE INDEX destinations_city_idx ON travel.destinations (city_id);
CREATE INDEX destinations_name_trgm_idx
  ON travel.destinations USING gin (name gin_trgm_ops);   -- extension pg_trgm
```

L'index trigramme sert le `?search=` de `GET /destinations` (recherche partielle,
insensible à la casse). `?city=` et `?country=` passent par `city_id` et la jointure sur
`cities`. `popularity_score` est **stockée** et recalculée par un job (favoris, avis,
étapes programmées) : la trier à la volée demanderait d'agréger trois tables à chaque
appel de liste.

#### `travel.activity_categories` *(référence)*

| Colonne | Type | Contraintes |
|---|---|---|
| `code` | `text` | **PK** — `musee`, `restaurant`, `hebergement`, `randonnee`, … |
| `label` | `text` | `NOT NULL` |
| `is_accommodation` | `boolean` | `NOT NULL DEFAULT false` |
| `is_active` | `boolean` | `NOT NULL DEFAULT true` |

Le `category: string` de `GET /destinations/:id/activities` est ce `code`, et c'est aussi
la valeur du `?category=`.

#### `travel.partners`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `name` | `text` | `NOT NULL` |
| `contact_email` | `text` | `NULL` |
| `contact_phone` | `text` | `NULL` |
| `website` | `text` | `NULL` |
| `created_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

Aucune route ne l'expose aujourd'hui : table prévue parce que `service.md` cite les
partenaires dans le périmètre de `Catalog`.

#### `travel.activities`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `destination_id` | `uuid` | `NOT NULL`, **FK** → `destinations(id)` `ON DELETE CASCADE` |
| `category_code` | `text` | `NOT NULL`, **FK** → `activity_categories(code)` `ON DELETE RESTRICT` |
| `partner_id` | `uuid` | `NULL`, **FK** → `partners(id)` `ON DELETE SET NULL` |
| `name` | `text` | `NOT NULL` |
| `description` | `text` | `NULL` |
| `address` | `text` | `NULL` |
| `latitude` | `numeric(9,6)` | `NULL`, `CHECK (latitude BETWEEN -90 AND 90)` |
| `longitude` | `numeric(9,6)` | `NULL`, `CHECK (longitude BETWEEN -180 AND 180)` |
| `price_range` | `text` | `NULL`, `CHECK (price_range IN ('€','€€','€€€','€€€€'))` |
| `opening_hours` | `jsonb` | `NULL` — un objet par jour, correspond au `openingHours: object?` |
| `contact_phone` | `text` | `NULL` |
| `contact_website` | `text` | `NULL` |
| `booking_url` | `text` | `NULL` |
| `created_at` | `timestamptz` | `NOT NULL DEFAULT now()` |
| `updated_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

```sql
CREATE INDEX activities_destination_idx ON travel.activities (destination_id);
CREATE INDEX activities_category_idx    ON travel.activities (category_code);
```

`latitude`/`longitude` sont là pour l'appel Google Maps de la génération
(`flux/principal.md`) : sans coordonnées, pas de calcul de trajet entre deux étapes.
`opening_hours` en `jsonb` et non en table dédiée : la donnée est lue en bloc, jamais
filtrée en SQL.

**`averageRating` n'est pas une colonne.** `GET /activities/:id` et
`GET /activities/:id/reviews` la calculent (`AVG(rating)` sur `reviews`, requête TypedSQL
comme dans `orm.md`). Une colonne dénormalisée serait à maintenir à chaque avis publié,
modifié ou masqué ; à introduire seulement si la mesure montre que c'est nécessaire.

#### `travel.activity_media`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `activity_id` | `uuid` | `NOT NULL`, **FK** → `activities(id)` `ON DELETE CASCADE` |
| `url` | `text` | `NOT NULL` |
| `origin` | `text` | `NOT NULL`, `CHECK (origin IN ('official','community'))` |
| `user_id` | `uuid` | `NULL` — identifiant Identity, auteur si `community` |
| `position` | `smallint` | `NOT NULL DEFAULT 0` |
| `created_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

```sql
ALTER TABLE travel.activity_media
  ADD CONSTRAINT activity_media_origin_author_chk
  CHECK ((origin = 'official') = (user_id IS NULL));
```

Un média officiel n'a pas d'auteur, un média communautaire en a toujours un : les deux cas
interdits sont fermés par une seule contrainte.

#### `travel.activity_recommended_profiles`

| Colonne | Type | Contraintes |
|---|---|---|
| `activity_id` | `uuid` | **FK** → `activities(id)` `ON DELETE CASCADE` |
| `traveler_type_code` | `text` | `NOT NULL` — **identifiant Identity**, pas de FK |

**PK** `(activity_id, traveler_type_code)`.

C'est l'illustration la plus nette de la règle : le code (`explorateur`, …) est
**recopié** depuis `identity.traveler_types`, sans clé étrangère, parce que la table de
référence appartient à l'autre microservice. Deux conséquences assumées : rien n'empêche
en base d'écrire un code inexistant (c'est l'API de Catalog qui valide à l'écriture), et
renommer un type côté Identity demande une migration de données ici. Le `?recommended=`
de `GET /destinations/:id/activities` filtre sur cette table avec le type dominant de
l'appelant, obtenu par un appel à Identity.

### Itinéraires

#### `travel.trips`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `user_id` | `uuid` | `NOT NULL` — **identifiant Identity**, pas de FK (propriétaire) |
| `title` | `text` | `NULL` |
| `status` | `text` | `NOT NULL DEFAULT 'generated'`, `CHECK (status IN ('draft','generated','active','completed','archived'))` |
| `start_date` | `date` | `NOT NULL` |
| `end_date` | `date` | `NOT NULL` |
| `budget` | `numeric(10,2)` | `NULL`, `CHECK (budget >= 0)` |
| `transport_mode` | `text` | `NULL`, `CHECK (transport_mode IN ('plane','train','car','bus','boat','bike','walk'))` |
| `origin_city_id` | `uuid` | `NULL`, **FK** → `cities(id)` `ON DELETE RESTRICT` |
| `destination_city_id` | `uuid` | `NOT NULL`, **FK** → `cities(id)` `ON DELETE RESTRICT` |
| `proposal_id` | `text` | `NULL` — clé Redis de la proposition validée (traçabilité) |
| `created_at` | `timestamptz` | `NOT NULL DEFAULT now()` |
| `updated_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

```sql
ALTER TABLE travel.trips
  ADD CONSTRAINT trips_dates_chk CHECK (end_date >= start_date);

CREATE INDEX trips_user_status_idx ON travel.trips (user_id, status);
CREATE INDEX trips_user_start_idx  ON travel.trips (user_id, start_date DESC);
```

`GET /trips` filtre sur `(user_id, status)`, `GET /trips/history` sur les statuts
`completed` et `archived` : même table, même index, deux services (`Travel` et
`Travel_history`) qui la lisent — ils sont dans le même microservice, c'est permis.

`proposal_id` garde le lien avec la proposition Redis qui a produit le voyage : utile pour
comprendre, après coup, ce que le LLM avait proposé. Pas de clé étrangère, Redis n'en a
pas, et la clé expire.

#### `travel.trip_travelers`

| Colonne | Type | Contraintes |
|---|---|---|
| `trip_id` | `uuid` | **FK** → `trips(id)` `ON DELETE CASCADE` |
| `user_id` | `uuid` | — **identifiant Identity**, pas de FK |
| `role` | `text` | `NOT NULL DEFAULT 'guest'`, `CHECK (role IN ('owner','guest'))` |
| `joined_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

**PK** `(trip_id, user_id)`.

```sql
CREATE UNIQUE INDEX trip_travelers_one_owner_idx
  ON travel.trip_travelers (trip_id) WHERE role = 'owner';
```

Un seul propriétaire par voyage, garanti par un index unique partiel. `trips.user_id`
reste malgré la redondance avec la ligne `owner` : la quasi-totalité des lectures
(`GET /trips`, autorisation sur `GET /trips/:id`) n'ont alors pas de jointure à faire.

#### `travel.trip_days`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `trip_id` | `uuid` | `NOT NULL`, **FK** → `trips(id)` `ON DELETE CASCADE` |
| `day_index` | `smallint` | `NOT NULL`, `CHECK (day_index >= 1)` |
| `date` | `date` | `NOT NULL` |

```sql
ALTER TABLE travel.trip_days
  ADD CONSTRAINT trip_days_trip_index_key UNIQUE (trip_id, day_index),
  ADD CONSTRAINT trip_days_trip_date_key  UNIQUE (trip_id, date);
```

Les deux unicités : pas deux « jour 2 », et pas deux journées sur la même date.
`day_index` est conservé en plus de la date parce que l'API l'expose (`dayIndex`) et que
le front l'utilise pour l'affichage.

#### `travel.trip_steps`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `trip_day_id` | `uuid` | `NOT NULL`, **FK** → `trip_days(id)` `ON DELETE CASCADE` |
| `sequence` | `smallint` | `NOT NULL`, `CHECK (sequence >= 1)` |
| `type` | `text` | `NOT NULL`, `CHECK (type IN ('activity','transport','accommodation','meal'))` |
| `activity_id` | `uuid` | `NULL`, **FK** → `activities(id)` `ON DELETE SET NULL` |
| `start_time` | `timestamptz` | `NULL` |
| `end_time` | `timestamptz` | `NULL` |
| `status` | `text` | `NOT NULL DEFAULT 'planned'`, `CHECK (status IN ('planned','confirmed','modified','skipped'))` |
| `notes` | `text` | `NULL` |
| `created_at` | `timestamptz` | `NOT NULL DEFAULT now()` |
| `updated_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

```sql
-- ordre des étapes dans la journée : 1..n, sans trou, sans doublon
ALTER TABLE travel.trip_steps
  ADD CONSTRAINT trip_steps_day_sequence_key UNIQUE (trip_day_id, sequence)
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE travel.trip_steps
  ADD CONSTRAINT trip_steps_times_chk
    CHECK (start_time IS NULL OR end_time IS NULL OR end_time >= start_time),
  ADD CONSTRAINT trip_steps_activity_required_chk
    CHECK (type <> 'activity' OR activity_id IS NOT NULL);

CREATE INDEX trip_steps_day_idx      ON travel.trip_steps (trip_day_id, sequence);
CREATE INDEX trip_steps_activity_idx ON travel.trip_steps (activity_id);
```

**L'ordre des étapes**, que le ticket demande explicitement de contraindre :

- `UNIQUE (trip_day_id, sequence)` interdit deux étapes au même rang ;
- `DEFERRABLE` est indispensable : réordonner, c'est écrire des rangs qui se croisent
  temporairement (3→2 alors que 2 existe encore). Vérifiée au `COMMIT`, la contrainte
  laisse passer la transaction entière sans obliger à un passage par des rangs négatifs ;
- Prisma ne sait pas déclarer `DEFERRABLE` : la contrainte est écrite dans une migration
  créée avec `prisma migrate dev --create-only`, comme prévu dans `orm.md` ;
- rangs **contigus à partir de 1**, renumérotés dans la transaction qui supprime
  (`DELETE /trips/:id/steps/:stepId`) ou déplace une étape. Un intervalle de 10 éviterait
  la renumérotation, mais l'API expose `sequence` et le front affiche « étape 3 ».
  Contigu n'est pas vérifiable par une contrainte de table : c'est au service de le tenir.

`ON DELETE SET NULL` sur `activity_id` : si une fiche disparaît du catalogue, l'étape du
voyage subsiste (avec ses horaires et ses notes) au lieu d'être effacée.
`trip_steps_activity_required_chk` traduit l'autre sens : une étape de type `activity`
sans fiche n'a pas de sens, alors qu'un `meal` ou un `transport` peut très bien ne pointer
vers rien.

#### `travel.trip_transports`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `trip_id` | `uuid` | `NOT NULL`, **FK** → `trips(id)` `ON DELETE CASCADE` |
| `trip_step_id` | `uuid` | `NULL`, **FK** → `trip_steps(id)` `ON DELETE SET NULL` |
| `leg` | `text` | `NOT NULL`, `CHECK (leg IN ('outbound','return','intra'))` |
| `mode` | `text` | `NOT NULL`, `CHECK (mode IN ('plane','train','car','bus','boat','bike','walk'))` |
| `from_city_id` | `uuid` | `NULL`, **FK** → `cities(id)` `ON DELETE RESTRICT` |
| `to_city_id` | `uuid` | `NULL`, **FK** → `cities(id)` `ON DELETE RESTRICT` |
| `departs_at` | `timestamptz` | `NULL` |
| `arrives_at` | `timestamptz` | `NULL` |
| `distance_km` | `numeric(8,2)` | `NULL` — renvoyé par Google Maps |
| `duration_min` | `integer` | `NULL` — idem |
| `created_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

```sql
ALTER TABLE travel.trip_transports
  ADD CONSTRAINT trip_transports_times_chk
    CHECK (departs_at IS NULL OR arrives_at IS NULL OR arrives_at >= departs_at);

CREATE INDEX trip_transports_trip_idx ON travel.trip_transports (trip_id);
```

Rattachée au voyage, comme dans `GET /trips/:id` où `transport` est au même niveau que
`days`. `trip_step_id` relie le trajet à l'étape correspondante quand le déplacement
occupe un créneau du planning (`leg = 'intra'`) ; les allers-retours n'ont pas d'étape.
`distance_km` et `duration_min` sont stockées pour ne pas rappeler Google Maps à chaque
affichage.

#### `travel.bookings`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `trip_id` | `uuid` | `NOT NULL`, **FK** → `trips(id)` `ON DELETE CASCADE` |
| `trip_step_id` | `uuid` | `NULL`, **FK** → `trip_steps(id)` `ON DELETE SET NULL` |
| `category` | `text` | `NOT NULL`, `CHECK (category IN ('flight','train','accommodation','activity'))` |
| `provider` | `text` | `NULL` |
| `reference_code` | `text` | `NULL` |
| `booking_url` | `text` | `NULL` |
| `status` | `text` | `NOT NULL DEFAULT 'pending'`, `CHECK (status IN ('pending','confirmed','cancelled'))` |
| `reminder_at` | `timestamptz` | `NULL` |
| `created_at` | `timestamptz` | `NOT NULL DEFAULT now()` |
| `updated_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

```sql
CREATE UNIQUE INDEX bookings_trip_reference_key
  ON travel.bookings (trip_id, category, reference_code)
  WHERE reference_code IS NOT NULL;

CREATE INDEX bookings_reminder_idx
  ON travel.bookings (reminder_at)
  WHERE status <> 'cancelled' AND reminder_at IS NOT NULL;
```

Index unique **partiel** : une référence de réservation ne doit pas être saisie deux fois
pour le même voyage, mais plusieurs réservations sans référence (`NULL`) doivent rester
possibles — un `UNIQUE` ordinaire l'autoriserait aussi (les `NULL` ne s'y comparent pas),
l'index partiel dit juste explicitement ce qu'on veut.

Le second index sert le job qui balaie les rappels à envoyer et émet l'événement vers
`Notification` (`Travel ┄┄▶ Identity` dans `services/microservices.md`) : il ne parcourt
que les lignes concernées, pas toute la table.

### Historique et carnet de voyage

Pas de table « historique » : un voyage terminé est un `trips` en `status = 'completed'`.
Le service `Travel_history` lit les mêmes tables et possède en propre le carnet.

#### `travel.journal_entries`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `trip_id` | `uuid` | `NOT NULL`, **FK** → `trips(id)` `ON DELETE CASCADE` |
| `trip_day_id` | `uuid` | `NULL`, **FK** → `trip_days(id)` `ON DELETE SET NULL` |
| `trip_step_id` | `uuid` | `NULL`, **FK** → `trip_steps(id)` `ON DELETE SET NULL` |
| `user_id` | `uuid` | `NOT NULL` — identifiant Identity (auteur) |
| `text` | `text` | `NULL` |
| `summary_word` | `text` | `NULL`, `CHECK (char_length(summary_word) <= 30)` |
| `created_at` | `timestamptz` | `NOT NULL DEFAULT now()` |
| `updated_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

```sql
CREATE INDEX journal_entries_trip_idx ON travel.journal_entries (trip_id, created_at);
```

`POST /trips/:id/journal` accepte `dayIndex` **ou** `stepId` : l'API résout `dayIndex` en
`trip_day_id` avant d'écrire, et la réponse refait la conversion inverse par jointure.

Deux règles que la base ne porte pas et que le service doit tenir : l'étape ou la journée
citée doit appartenir au voyage, et une entrée doit avoir au moins un contenu (texte, mot
résumé ou photo). La première est vérifiable en base au prix d'une clé étrangère
composite (dupliquer `trip_id` sur `trip_steps` et `trip_days`, les rendre uniques avec
`id`, puis référencer le couple) ; la seconde ne l'est pas, les photos étant dans une
autre table. Les deux sont donc validées au même endroit, dans le service.

#### `travel.journal_photos`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `journal_entry_id` | `uuid` | `NOT NULL`, **FK** → `journal_entries(id)` `ON DELETE CASCADE` |
| `url` | `text` | `NOT NULL` |
| `position` | `smallint` | `NOT NULL DEFAULT 0` |
| `created_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

```sql
ALTER TABLE travel.journal_photos
  ADD CONSTRAINT journal_photos_entry_position_key UNIQUE (journal_entry_id, position)
  DEFERRABLE INITIALLY IMMEDIATE;
```

Même motif que `trip_steps.sequence` : un ordre d'affichage réordonnable, donc une
unicité différée. **Seule l'URL est en base** ; le fichier est dans un stockage objet (voir
« Ce qui n'est pas en PostgreSQL »).

#### `travel.journal_exports`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `trip_id` | `uuid` | `NOT NULL`, **FK** → `trips(id)` `ON DELETE CASCADE` |
| `user_id` | `uuid` | `NOT NULL` — identifiant Identity (demandeur) |
| `status` | `text` | `NOT NULL DEFAULT 'pending'`, `CHECK (status IN ('pending','processing','done','failed'))` |
| `pdf_url` | `text` | `NULL` |
| `job_id` | `text` | `NULL` — identifiant BullMQ |
| `requested_at` | `timestamptz` | `NOT NULL DEFAULT now()` |
| `completed_at` | `timestamptz` | `NULL` |

```sql
ALTER TABLE travel.journal_exports
  ADD CONSTRAINT journal_exports_done_url_chk
  CHECK (status <> 'done' OR pdf_url IS NOT NULL);
```

`GET /trips/:id/journal/export` est une génération **asynchrone** (`Queue`) :
sans cette table, l'API n'aurait pas d'état à renvoyer entre la demande et le PDF prêt.
La contrainte interdit l'incohérence « terminé mais sans fichier ».

### Favoris et avis

#### `travel.favorites`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `user_id` | `uuid` | `NOT NULL` — identifiant Identity |
| `target_type` | `text` | `NOT NULL`, `CHECK (target_type IN ('destination','activity','city'))` |
| `target_id` | `uuid` | `NOT NULL` — cible polymorphe, **pas de FK** |
| `status` | `text` | `NOT NULL DEFAULT 'favorite'`, `CHECK (status IN ('favorite','considered'))` |
| `created_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

```sql
ALTER TABLE travel.favorites
  ADD CONSTRAINT favorites_user_target_key UNIQUE (user_id, target_type, target_id);

CREATE INDEX favorites_user_created_idx ON travel.favorites (user_id, created_at DESC);
CREATE INDEX favorites_target_idx       ON travel.favorites (target_type, target_id);
```

L'unicité empêche le même favori deux fois et fait de `POST /favorites` un upsert naturel
(passer de `considered` à `favorite` est une mise à jour, pas une seconde ligne).

`target_id` **sans clé étrangère** : la cible est l'une de trois tables, et PostgreSQL ne
sait pas référencer une table variable. Trois colonnes nullables avec un `CHECK`
« exactement une renseignée » seraient vérifiables en base, mais obligeraient à trois
jointures `LEFT JOIN` à chaque lecture de la liste et à changer le schéma pour toute
nouvelle cible. Choix retenu : couple (type, id), validé par le service à l'écriture, et
le second index permet la purge quand une fiche du catalogue disparaît.

#### `travel.reviews`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | **PK**, `DEFAULT gen_random_uuid()` |
| `activity_id` | `uuid` | `NOT NULL`, **FK** → `activities(id)` `ON DELETE CASCADE` |
| `user_id` | `uuid` | `NOT NULL` — identifiant Identity (auteur) |
| `rating` | `smallint` | `NOT NULL`, `CHECK (rating BETWEEN 1 AND 5)` |
| `comment` | `text` | `NULL` |
| `status` | `text` | `NOT NULL DEFAULT 'published'`, `CHECK (status IN ('published','hidden','reported'))` |
| `created_at` | `timestamptz` | `NOT NULL DEFAULT now()` |
| `updated_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

```sql
ALTER TABLE travel.reviews
  ADD CONSTRAINT reviews_activity_user_key UNIQUE (activity_id, user_id);

CREATE INDEX reviews_activity_published_idx
  ON travel.reviews (activity_id) WHERE status = 'published';
```

Un avis par utilisateur et par activité : `POST /activities/:id/reviews` deux fois met à
jour le premier au lieu d'en créer un second. `status` couvre la « modération basique »
de `service.md` : un avis masqué sort des listes et de la moyenne sans être détruit, et
`DELETE /reviews/:id` (son propre avis) est un vrai `DELETE`.

L'index partiel sert les deux usages les plus fréquents : la liste des avis publiés d'une
activité et le `AVG(rating)` qui alimente `averageRating`.

---

## Le vecteur des destinations

Le ticket demande de « prévoir le vecteur des destinations ». La décision est déjà prise
et documentée dans `doc/postgres/orm.md` (#97, sur `develop`) ; ce document ne fait que
s'y conformer :

- **la conception actuelle n'a pas de recherche vectorielle** : `services/schema.md` et le
  `README.md` indiquent que `Itinerary_generation` transmet les candidats du catalogue
  directement au LLM, qui choisit et organise lui-même. Pas de scoring par similarité,
  pas de base vectorielle ;
- **aucune colonne `vector` n'est donc créée** par ce MLD, et l'image `postgres:16` suffit ;
- **l'emplacement est réservé** : si le chatbot RAG en a besoin, la colonne va sur
  `travel.destinations` (et le cas échéant sur `travel.activities`), en `pgvector`, pas en
  `real[]` — un `real[]` n'offre ni opérateur de distance ni index, la similarité se
  calculerait en mémoire côté service.

La forme que prendrait la migration, pour mémoire :

```sql
CREATE EXTENSION IF NOT EXISTS vector;

ALTER TABLE travel.destinations ADD COLUMN embedding vector(768);

CREATE INDEX destinations_embedding_idx
  ON travel.destinations USING hnsw (embedding vector_cosine_ops);
```

La dimension dépend du modèle d'embedding Ollama retenu (ticket du microservice IA, #85) :
`768` n'est qu'un exemple. Côté Prisma 7, la colonne se déclare
`Unsupported("vector(768)")?` pour que la migration suivante ne la supprime pas, et se lit
en `$queryRaw` avec un cast `::vector`.

Deux conséquences si le besoin arrive : l'image PostgreSQL devient
`pgvector/pgvector:pg16`, et le vecteur reste **dans le schéma `travel`** — c'est Catalog
qui possède les fiches, donc c'est Travel qui expose une route de recherche par
similarité ; le microservice IA l'appelle, il ne lit pas la colonne.

## Ce qui n'est pas en PostgreSQL

| Donnée | Où | Pourquoi |
|---|---|---|
| Sessions, révocation des JWT, `refresh_token` | Redis (`Session`, ticket #99) | Durée de vie courte, expiration native, aucune table de tokens à purger. `services/service.md` : Authentification « s'appuie sur `Session` (Redis) pour la révocation » |
| Proposition d'itinéraire non validée (`proposalId`) | Redis (`Cache`) | Rien n'est écrit en base avant `/trips/generate/:proposalId/confirm` (`flux/principal.md`). Seule trace après validation : `trips.proposal_id` |
| Conversations du chatbot, logs d'interaction | MongoDB (microservice IA, tickets #95, #98) | Volumineux et à schéma souple |
| Fichiers : photos du carnet, médias des activités, PDF d'export | Stockage objet, URL en base | Une base relationnelle n'est pas un serveur de fichiers. Le choix du stockage (S3, MinIO) est un sujet d'infrastructure, pas de ce ticket |
| `averageRating`, `scores` agrégés | Calculés à la lecture | Dénormalisation seulement si la mesure la justifie |

## Couverture des routes de `doc/postgres/endpoints.md`

38 routes, vérifiées une par une. `ø` = aucune table (Redis ou calcul).

| Route | Tables |
|---|---|
| `POST /auth/register` | `users` (insert), `settings` (insert, défauts) |
| `POST /auth/login` | `users` (lecture) · session en Redis `ø` |
| `POST /auth/refresh` | `ø` (Redis) |
| `POST /auth/logout` | `ø` (Redis) |
| `GET /users/me` | `users` |
| `PATCH /users/me` | `users` |
| `DELETE /users/me` | `users` (`status`, `deleted_at`, anonymisation) + événement `user.deleted` |
| `GET /users/me/questionnaire` | `questionnaire_questions` + `profile_axes` (`axis`) |
| `POST /users/me/questionnaire` | `questionnaire_answers` (upsert), `traveler_profiles`, `traveler_profile_scores`, `traveler_types` |
| `GET /users/me/type` | `traveler_profiles` + `traveler_profile_scores` + `traveler_types` |
| `GET /users/me/settings` | `settings` |
| `PATCH /users/me/settings` | `settings` |
| `GET /notifications` | `notifications` |
| `PATCH /notifications/:id/read` | `notifications` (`read_at`) |
| `GET /destinations` | `destinations` + `cities` + `countries` (`?city=`, `?country=`, `?search=`) |
| `GET /destinations/:id` | `destinations` + `cities` (objet `city` avec `countryId`) |
| `GET /destinations/:id/activities` | `activities` + `activity_categories` + `activity_recommended_profiles` (`?category=`, `?recommended=`) |
| `GET /activities/:id` | `activities` + `activity_media` + `reviews` (`AVG` pour `averageRating`) |
| `POST /trips/generate` | lecture `destinations`, `activities`, `cities` ; proposition en Redis `ø` |
| `POST /trips/generate/:proposalId/regenerate` | `ø` (Redis) + mêmes lectures de catalogue |
| `POST /trips/generate/:proposalId/confirm` | `trips`, `trip_travelers`, `trip_days`, `trip_steps`, `trip_transports` (insert) |
| `GET /trips` | `trips` (`?status=`) |
| `GET /trips/:id` | `trips`, `trip_days`, `trip_steps`, `trip_transports`, `bookings` |
| `PATCH /trips/:id` | `trips` |
| `DELETE /trips/:id` | `trips` (cascade sur jours, étapes, trajets, réservations, carnet) |
| `PATCH /trips/:id/steps/:stepId` | `trip_steps` (`activity_id`, horaires, `status`) |
| `DELETE /trips/:id/steps/:stepId` | `trip_steps` (+ renumérotation de `sequence`) |
| `POST /trips/:id/bookings` | `bookings` |
| `GET /trips/history` | `trips` (`status IN ('completed','archived')`) |
| `GET /trips/:id/journal` | `journal_entries` + `journal_photos` + `trip_days` (`dayIndex`) |
| `POST /trips/:id/journal` | `journal_entries`, `journal_photos` |
| `GET /trips/:id/journal/export` | `journal_exports` |
| `GET /favorites` | `favorites` |
| `POST /favorites` | `favorites` (upsert) |
| `DELETE /favorites/:id` | `favorites` |
| `GET /activities/:id/reviews` | `reviews` (+ `AVG` pour `averageRating`) |
| `POST /activities/:id/reviews` | `reviews` (upsert) |
| `DELETE /reviews/:id` | `reviews` |

Tables sans route aujourd'hui : `partners` (périmètre de `Catalog` dans `service.md`, pas
encore exposé) et `countries` / `cities` / `activity_categories` / `profile_axes` /
`traveler_types`, qui sont des référentiels servis par le seed et lus en jointure.

Champs de `schemas.md` qui ne sont pas des colonnes : `read` (dérivé de
`notifications.read_at`), `averageRating` (agrégat), `dayIndex` dans le carnet (jointure
sur `trip_days`), `proposalId` et les propositions (Redis).

## Ce qui reste à trancher

- **La soumission du questionnaire garde-t-elle un historique ?** Le modèle actuel ne
  conserve que la réponse courante (`UNIQUE (user_id, question_id)`). Si on veut suivre
  l'évolution d'un profil, il faut une table de soumissions datées et `traveler_profiles`
  devient une série au lieu d'une ligne.
- **La barème du calcul de profil** (poids, questions inversées, formule de la dominante)
  dépend du ticket `User_type` : le MLD prévoit `weight` et `reverse_scored`, mais la
  formule n'est pas arrêtée ici.
- **Le vecteur est-il dans le périmètre ?** Non pour le MVP (`orm.md`, #97). À arbitrer
  avec #92 et le ticket du microservice IA (#85), avec la dimension de l'embedding.
- **Dénormaliser `averageRating` et `popularity_score` ?** `popularity_score` est déjà
  stockée (tri de liste), `averageRating` non. À revoir avec une mesure, pas avant.
- **Stockage des fichiers** (photos, PDF) : à trancher dans un ticket d'infrastructure ;
  ce MLD ne stocke que des URL.
- **Purge sur `user.deleted`** : ce document dit *quelles* tables sont concernées
  (`trips`, `trip_travelers`, `favorites`, `reviews`, `journal_entries`, `activity_media`,
  `journal_exports`), pas le délai ni le niveau d'anonymisation — c'est le ticket RGPD.
- **Les référentiels sont-ils des tables ou du seed en dur ?** Ici : des tables, remplies
  par `prisma db seed`. À confirmer avec l'équipe front, qui doit afficher les libellés.
