# ORM et migrations PostgreSQL

Sous-ticket #97 de #92. Ce document tranche l'outil d'accès à PostgreSQL pour tous les
microservices qui en possèdent un schéma (`identity`, `travel` — voir
`doc/services/microservices.md`), la façon de lancer les migrations et la façon d'écrire une
requête brute quand l'ORM ne suffit pas.

L'outil doit être **le même partout** : un seul outil à apprendre, une seule façon de
migrer, des conventions identiques d'un service à l'autre.

## Décision

**Prisma**, en version 7 épinglée, avec :

- **un `schema.prisma` et un dossier `migrations/` par microservice**, jamais partagés ;
- **un schéma PostgreSQL par microservice** (`identity`, `travel`), choisi par la chaîne de
  connexion (`?schema=travel`), avec un rôle SQL distinct par service ;
- **`prisma migrate deploy`** lancé par un conteneur à part dans `docker compose`, avant le
  démarrage du service ;
- **`$queryRaw` / TypedSQL** comme porte de sortie pour le SQL que l'ORM ne sait pas écrire,
  y compris la recherche par vecteur.

C'est la recommandation de départ du ticket, confirmée après comparaison. Les paragraphes
suivants donnent la justification, ce qu'on perd, et pourquoi Drizzle et TypeORM sont
écartés.

## Ce que l'outil doit savoir faire

| # | Besoin | Pourquoi chez nous |
|---|---|---|
| 1 | Intégration NestJS | Le backend est NestJS (voir `documentation/Triply - Choix des technologies.pdf`) : il faut injecter le client comme un provider |
| 2 | Migrations versionnées | Les schémas évoluent à chaque sprint ; il faut un historique rejouable et un fichier SQL relisible en revue |
| 3 | Types générés | Les contrats de `doc/api/postgres/schemas.md` doivent être tenus par le compilateur, pas par la relecture |
| 4 | Un schéma par microservice | Règle d'architecture : chaque service est seul propriétaire de ses tables (`doc/services/microservices.md`) |
| 5 | Requête brute lisible | Jointures avis/fiche, agrégats (`averageRating`), recherche par vecteur |
| 6 | Colonne de vecteur | Les destinations/activités porteront peut-être un embedding (`pgvector` ou `real[]`) pour le chatbot RAG — voir la section dédiée |

## Comparaison

État des versions vérifié sur le registre npm le **9 octobre 2026**.

| Critère | Prisma | TypeORM | Drizzle |
|---|---|---|---|
| Version stable | `prisma`/`@prisma/client` **7.10.0** (la 8 est en RC) | **1.1.2** (première majeure, mai 2026) | **0.45.4** — la 1.0 est encore en RC |
| Intégration NestJS | Pas de module officiel : un `PrismaService` d'une vingtaine de lignes | Module officiel `@nestjs/typeorm` (12.0.2) | Pas de module officiel : un provider maison |
| Migrations | `migrate dev` génère le SQL depuis le schéma, `migrate deploy` l'applique ; historique dans `_prisma_migrations` | Fichiers de migration en TypeScript, `migration:generate` / `migration:run` ; `synchronize` interdit hors dev | `drizzle-kit generate` produit le SQL + un snapshot, `migrate` l'applique |
| Typage | Le meilleur des trois : types générés depuis le schéma, retours exacts selon le `select` | Le plus faible : entités à décorateurs, `find` peu contraint, pas de type dérivé de la projection | Très bon : types inférés depuis le schéma TypeScript, sans génération |
| Un schéma par service | `?schema=travel` dans l'URL ; chaque service a son `_prisma_migrations` dans son schéma | `schema: 'travel'` sur la `DataSource` / les entités | `pgSchema('travel')` dans la définition des tables |
| Vecteur | Déclaré `Unsupported("vector(768)")` en 7, lu/écrit en SQL brut ; première classe en 8 via `@prisma/orm-extension-pgvector` | Pas de support : type `real[]` ou colonne déclarée en SQL brut | Première classe : type `vector`, helpers `cosineDistance`, index HNSW |
| SQL brut | `$queryRaw` (template paramétré) et **TypedSQL** : du `.sql` dans le dépôt, typé à la génération | `query()` / `QueryBuilder`, résultats non typés | `sql` template, typage à déclarer soi-même |

## Pourquoi Prisma

1. **Le schéma devient la source de vérité et il se relit.** Un `schema.prisma` par service
   est un fichier que l'équipe peut lire en revue, à côté de `doc/api/postgres/schemas.md`,
   sans lire du TypeScript ni des décorateurs. `migrate dev` en déduit le SQL ; la migration
   générée reste un `.sql` qu'on relit et qu'on corrige à la main si besoin.
2. **Le typage protège les contrats d'API.** Les réponses décrites dans `schemas.md` sont
   tenues par les types générés : un champ renommé en base casse la compilation, pas la
   production.
3. **Le découpage par schéma tombe juste.** Un service = un `schema.prisma` = un schéma
   PostgreSQL = sa propre table d'historique de migrations. Il n'existe aucun moyen, pour
   `Travel`, de lire le schéma `identity` : son client ne connaît même pas ces modèles.
   C'est exactement la règle posée dans `doc/services/microservices.md`.
4. **La porte de sortie est propre.** TypedSQL met les requêtes compliquées dans
   `prisma/sql/*.sql`, typées à la génération : on garde du vrai SQL pour les agrégats et la
   recherche vectorielle, sans perdre les types.
5. **La courbe d'apprentissage.** Équipe petite et qui démarre : la documentation, les
   messages d'erreur et `prisma studio` font gagner du temps face à un `QueryBuilder` ou à
   du SQL écrit à la main.

### Ce qu'on perd, et comment on s'en arrange

| Risque | Mesure |
|---|---|
| **La 8 est en RC et le tag npm `latest` de `prisma` pointe dessus** : un `npm i prisma` attrape une RC | On épingle `prisma@7` et `@prisma/client@7` (versions exactes dans `package.json`, jamais `@latest`). Montée en 8 traitée comme un ticket à part : la 8 change la syntaxe du schéma et supprime les attributs `@db.*` |
| Pas de module NestJS officiel | Un `PrismaService extends PrismaClient` avec `onModuleInit` / `onModuleDestroy`, exposé par un `PrismaModule` global. Une vingtaine de lignes, écrites une fois par service |
| Le vecteur n'est pas de première classe en 7 | Colonne créée dans une migration maison, lue en `$queryRaw` (voir section vecteur). Et ce n'est pas dans le MVP |
| Pas de jointure possible entre schémas | C'est voulu : `trips.user_id` est un identifiant, pas une clé étrangère. On passe par l'API du service propriétaire |

## Alternatives écartées

**Drizzle** — le meilleur candidat techniquement sur notre point le plus exotique : le type
`vector`, les helpers `cosineDistance`, les index HNSW sont de première classe, là où Prisma 7
oblige au SQL brut. Écarté pour une raison de calendrier, pas de qualité : au 9 octobre 2026
la version stable reste la **0.45.4** et la 1.0 est en *release candidate* avec un moteur de
migration réécrit. Démarrer dessus veut dire soit partir sur une RC, soit partir sur la 0.45
et prévoir une migration de l'outil pendant le projet. Pour un backend qui doit livrer son
MVP, c'est un risque qu'on ne prend pas. À réexaminer si la 1.0 sort stable avant le début du
code, ou si la recherche vectorielle devient centrale.

**TypeORM** — le seul à avoir un module NestJS officiel (`@nestjs/typeorm`), et sa 1.1.2 est
stable. Écarté sur le typage et les migrations : les entités à décorateurs ne donnent pas de
type dérivé de la projection (un `find` renvoie l'entité entière, pas ce qu'on a demandé), la
génération de migrations est historiquement moins fiable, et `synchronize: true` est un piège
qu'il faut interdire explicitement. Comme on écrit des contrats d'API stricts, c'est
exactement le confort qu'on cherche à ne pas perdre.

## Un schéma par microservice, concrètement

Un seul serveur PostgreSQL, un schéma et un rôle par microservice.

```
PostgreSQL (un serveur)
├── schéma identity   ← rôle triply_identity   ← service Identity (son schema.prisma)
└── schéma travel     ← rôle triply_travel     ← service Travel   (son schema.prisma)
```

Côté service, tout tient dans la chaîne de connexion :

```
# service Identity
DATABASE_URL=postgresql://triply_identity:***@postgres:5432/triply?schema=identity

# service Travel
DATABASE_URL=postgresql://triply_travel:***@postgres:5432/triply?schema=travel
```

Ce que ça donne :

- chaque service crée ses tables **et** sa table `_prisma_migrations` dans son propre
  schéma : les deux historiques de migrations ne se croisent jamais ;
- les droits SQL font le reste : `triply_travel` n'a aucun `USAGE` sur le schéma `identity`,
  donc la règle de propriété des données n'est pas qu'une convention ;
- le `multiSchema` de Prisma (un client qui voit plusieurs schémas) n'est **pas** utilisé :
  on ne veut justement pas qu'un service voie le schéma d'un autre.

Côté schéma Prisma, pas de clé étrangère vers un autre service :

```prisma
model Trip {
  id     String @id @default(uuid())
  userId String                       // identifiant chez Identity, pas une relation
  // ...
}
```

## Lancer les migrations au démarrage (docker compose)

Les migrations ne sont **pas** lancées par le service applicatif : un conteneur à part les
applique et sort, puis le service démarre. Ça évite deux répliques qui migrent en même temps
et ça rend l'échec visible (le service ne démarre pas du tout).

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: triply
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d triply"]
      interval: 5s
      retries: 10

  travel-migrate:
    build: ./services/travel
    command: npx prisma migrate deploy
    environment:
      DATABASE_URL: postgresql://triply_travel:***@postgres:5432/triply?schema=travel
    depends_on:
      postgres:
        condition: service_healthy

  travel:
    build: ./services/travel
    depends_on:
      travel-migrate:
        condition: service_completed_successfully
```

Un couple `<service>-migrate` / `<service>` par microservice ayant un schéma PostgreSQL.

Les commandes, et qui les lance :

| Commande | Qui | Quand |
|---|---|---|
| `prisma migrate dev --name <nom>` | le développeur, en local | écrire une migration après avoir modifié `schema.prisma` ; le `.sql` généré est commité |
| `prisma migrate deploy` | le conteneur `*-migrate` | à chaque démarrage, en local comme en déploiement : applique ce qui manque, ne génère rien |
| `prisma generate` | le build de l'image | produire le client typé |
| `prisma db seed` | manuellement, ou un conteneur dédié | jeu de données de démo (catalogue, questionnaire) |

Interdits : `prisma db push` et `prisma migrate dev` ailleurs qu'en local — le premier
modifie la base sans laisser de migration, le second peut réinitialiser la base.
`migrate deploy` est la seule commande qui tourne dans un conteneur.

## Écrire une requête brute

Quand l'ORM ne suffit pas (agrégats, `ORDER BY` calculé, fonction PostgreSQL, vecteur), deux
niveaux.

**1. `$queryRaw`**, en *template* balisé : les valeurs passent en paramètres, pas en
concaténation.

```ts
const rows = await this.prisma.$queryRaw<{ activityId: string; avg: number }[]>`
  SELECT activity_id AS "activityId", AVG(rating)::float AS avg
  FROM reviews
  WHERE activity_id = ${activityId}
  GROUP BY activity_id
`;
```

Pour une écriture : `$executeRaw`. **`$queryRawUnsafe` et `$executeRawUnsafe` sont
interdits** — ils prennent une chaîne construite à la main, donc une injection SQL
possible ; si une requête semble en avoir besoin, elle passe par TypedSQL.

**2. TypedSQL**, pour tout ce qui est réutilisé ou long : la requête vit dans
`prisma/sql/<nom>.sql`, et `prisma generate --sql` en produit une fonction typée.

```sql
-- prisma/sql/activityRatings.sql
SELECT activity_id, AVG(rating)::float AS avg_rating
FROM reviews
WHERE activity_id = $1
GROUP BY activity_id;
```

```ts
import { activityRatings } from '@prisma/client/sql';
const rows = await this.prisma.$queryRawTyped(activityRatings(activityId));
```

Règle d'équipe : SQL brut seulement quand l'ORM ne sait pas l'écrire ou l'écrit mal, et
toujours avec une mesure à l'appui pour l'argument de performance.

## La colonne de vecteur

À l'état actuel de la conception, **il n'y a pas de recherche vectorielle dans le MVP** :
`doc/services/schema.md` et `doc/README.md` indiquent que `Itinerary_generation` transmet les
candidats du catalogue directement au LLM, et que le profil voyageur est un score par axe,
sans similarité. Le ticket demande malgré tout que l'outil retenu ne bloque pas une colonne
de vecteur sur les destinations, pour le chatbot RAG.

Ce qui est tranché ici, c'est donc la **façon de faire si le besoin arrive**, pas l'ajout de
la colonne.

Choix : **`pgvector`**, pas `real[]`. Un `real[]` stocke bien un embedding mais ne donne ni
opérateur de distance ni index : la similarité se calcule alors en mémoire côté service, ce
qui ne tient pas sur un catalogue qui grossit. `pgvector` apporte les opérateurs (`<=>` pour
le cosinus) et les index HNSW/IVFFlat.

Avec Prisma 7, en trois temps :

1. L'extension et la colonne dans une migration écrite à la main
   (`prisma migrate dev --create-only`, puis on édite le `.sql`) :

```sql
CREATE EXTENSION IF NOT EXISTS vector;
ALTER TABLE destinations ADD COLUMN embedding vector(768);
CREATE INDEX destinations_embedding_idx
  ON destinations USING hnsw (embedding vector_cosine_ops);
```

La dimension dépend du modèle d'embedding Ollama retenu — à fixer avec le ticket du
microservice IA (#85), `768` n'est ici qu'un exemple.

2. La colonne déclarée dans `schema.prisma` comme type non géré, pour que Prisma ne la
   supprime pas à la prochaine migration :

```prisma
model Destination {
  id        String                      @id @default(uuid())
  name      String
  embedding Unsupported("vector(768)")?
}
```

3. La lecture et l'écriture en SQL brut, avec un cast : Prisma ne sait pas désérialiser le
   type `vector`, il faut le ramener en texte en sortie et le caster en entrée.

```ts
const similar = await this.prisma.$queryRaw<{ id: string; distance: number }[]>`
  SELECT id, embedding <=> ${vector}::vector AS distance
  FROM destinations
  ORDER BY distance
  LIMIT 10
`;
```

À noter : `prisma studio` n'affiche pas les tables qui portent une colonne `vector`. Prisma 8
règle le sujet avec le pack `@prisma/orm-extension-pgvector` (type `vector` déclaré dans le
schéma) : c'est un argument de plus pour planifier la montée en version, pas pour démarrer
sur une RC.

Conséquence côté infrastructure : l'image PostgreSQL devra embarquer `pgvector`
(`pgvector/pgvector:pg16` plutôt que `postgres:16`) le jour où la colonne arrive.

## Ce qui reste à trancher

- **Le vecteur est-il dans le périmètre ?** La conception dit non pour le MVP, le ticket
  demande que ce soit possible. À arbitrer avec #92 et le ticket du microservice IA (#85) ;
  tant que c'est non, aucune colonne `vector` n'est créée et l'image `postgres:16` suffit.
- **La dimension de l'embedding**, liée au modèle Ollama retenu.
- **Un dépôt par microservice ou un monodépôt ?** Ça ne change pas le choix de l'outil, mais
  ça change où vivent les `schema.prisma` et comment le conteneur `*-migrate` est construit.
- **Mongo (#98) et Redis (#99)** sont tranchés dans leurs propres tickets : ce document ne
  couvre que PostgreSQL.
- **Montée en Prisma 8** : à ouvrir comme ticket quand la 8.0.0 sortira stable (syntaxe du
  schéma modifiée, `@db.*` supprimés, pack pgvector).
