# Guide de démarrage — bases de données

Pour tout membre de l'équipe qui arrive sur le back de Triply : installer, lancer les bases de
dev, s'y connecter, modifier un schéma, et ce qu'il faut savoir sur la prod.

Le détail technique (choix des hébergeurs, limites des offres gratuites, création des comptes)
est dans [`bases-de-donnees.md`](bases-de-donnees.md). Ce guide-ci est la version pratique.

## En bref

| | Dev | Prod |
|---|---|---|
| Où | Sur ta machine, dans Docker | Offres gratuites dans le cloud (Europe) |
| PostgreSQL 18 | Conteneur `postgres` | Neon (Frankfurt) |
| MongoDB 8.0 | Conteneur `mongo` | MongoDB Atlas (cluster `vibngo`) |
| Redis | Conteneurs `redis-core` et `redis-cache` | Upstash (une base pour les deux rôles) |
| Identifiants | `.env`, copié de `.env.example` (valeurs de dev publiques) | `.env.production`, **secret**, jamais dans git |
| Qui | Tout le monde | Seulement les personnes qui déploient |
| Coût | 0 € | 0 € |

## 1. Installer (une seule fois)

| Outil | Pourquoi | Obligatoire |
|---|---|---|
| [Git](https://git-scm.com/) | Récupérer le code | Oui |
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | Faire tourner les bases | Oui |
| [VS Code](https://code.visualstudio.com/) | Éditeur, et voir les données | Conseillé |
| [Node.js](https://nodejs.org/) 20 ou plus | Seulement pour **modifier** le schéma PostgreSQL | Non |

Extensions VS Code conseillées : **PostgreSQL** (Microsoft), **MongoDB for VS Code**, **Redis for VS Code**, **PlantUML** (pour voir les diagrammes).

**Windows** : avant de cloner, une fois pour toutes, pour garder les fins de ligne Linux des
scripts montés dans les conteneurs :

```powershell
git config --global core.autocrlf input
```

## 2. Récupérer le projet

```bash
git clone https://github.com/misterwhite44/vibngo_back.git
cd vibngo_back
git checkout develop
```

On travaille toujours depuis `develop`, sur une branche à soi (voir
`documentation/Triply_officiel/Git convention-Triply.pdf`).

## 3. Lancer les bases de dev

Docker Desktop doit être **démarré** (« Engine running ») avant toute commande `docker`.

```bash
cp .env.example .env          # PowerShell : Copy-Item .env.example .env
docker compose up -d
docker compose ps
```

Ce qu'on doit voir après une trentaine de secondes (la première fois, quelques minutes pour
télécharger les images) :

| Conteneur | État attendu | Rôle |
|---|---|---|
| `postgres` | `Up (healthy)` | PostgreSQL, rôles et schémas `identity` / `travel` |
| `identity-migrate`, `travel-migrate` | `Exited (0)` | Créent les tables (migrations Prisma), puis s'arrêtent |
| `mongo` | `Up (healthy)` | MongoDB en replica set |
| `mongo-init` | `Exited (0)` | Crée les collections et les index, puis s'arrête |
| `redis-core`, `redis-cache` | `Up (healthy)` | Les deux rôles Redis |

Un `Exited (1)` veut dire que quelque chose a échoué : `docker compose logs <conteneur>`, puis
voir « Dépannage ».

C'est tout : les bases sont prêtes, vides, avec toute la structure.

## 4. Se connecter aux bases de dev

| Base | Connexion | Utilisateur / mot de passe |
|---|---|---|
| PostgreSQL, schéma `identity` | `localhost:5432`, base `triply` | `triply_identity` / `identity_dev` |
| PostgreSQL, schéma `travel` | `localhost:5432`, base `triply` | `triply_travel` / `travel_dev` |
| PostgreSQL, admin | `localhost:5432`, base `triply` | `postgres` / `postgres_dev` |
| MongoDB | `mongodb://localhost:27017/?replicaSet=rs0&directConnection=true` | aucun |
| redis-core | `localhost:6379` | mot de passe `core_dev` |
| redis-cache | `localhost:6380` | mot de passe `cache_dev` |

Ces valeurs viennent de `.env`. Chaque rôle PostgreSQL ne voit **que son schéma** : c'est
voulu (un microservice, un schéma). Pour tout voir, utiliser l'admin `postgres`.

Sans extension, en ligne de commande :

```bash
docker compose exec postgres psql -U triply_travel -d triply      # \dt pour lister les tables
docker compose exec mongo mongosh assistant                        # db.getCollectionNames()
docker compose exec redis-core redis-cli -a core_dev
```

## 5. Commandes du quotidien

| Besoin | Commande |
|---|---|
| Démarrer / relancer | `docker compose up -d` |
| Arrêter (les données restent) | `docker compose stop` |
| Voir l'état | `docker compose ps` |
| Voir les logs d'un conteneur | `docker compose logs postgres` |
| Tout effacer et repartir de zéro | `docker compose down -v` puis `docker compose up -d` |
| Appliquer de nouvelles migrations (après un `git pull`) | `docker compose run --rm identity-migrate` et `docker compose run --rm travel-migrate` |
| Rejouer l'init MongoDB | `docker compose run --rm mongo-init` |
| Tester les contraintes PostgreSQL (rien n'est gardé) | `docker compose exec -T postgres psql -U triply_travel -d triply -f - < db/postgres/tests/travel.sql` (idem avec `identity`) |

`docker compose down -v` efface les données de dev, jamais celles de prod.

## 6. Modifier un schéma

### PostgreSQL (Prisma)

Le modèle de référence est [`doc/api/postgres/mcd-mld.md`](../api/postgres/mcd-mld.md), le code
dans `db/postgres/<schéma>/schema.prisma`. Une modification = le MLD **et** le `schema.prisma`
**et** une nouvelle migration, dans la même PR.

```bash
cd db/postgres
npm install                                            # une fois
# PowerShell : $env:DATABASE_URL="postgresql://triply_travel:travel_dev@localhost:5432/triply?schema=travel"
export DATABASE_URL="postgresql://triply_travel:travel_dev@localhost:5432/triply?schema=travel"
npm run travel -- migrate dev --name ajout_colonne_x   # écrit la migration et l'applique en dev
```

(Remplacer `travel` par `identity`, et l'URL par celle du rôle `triply_identity`, pour l'autre schéma.)

Règles :
- une migration commitée **ne se modifie plus** : on en écrit une nouvelle ;
- `CHECK`, index partiel, `DEFERRABLE` : Prisma ne sait pas les écrire. Ajouter
  `--create-only`, compléter le `.sql` généré, puis relancer la commande sans `--create-only` ;
- jamais de `prisma db push`, jamais de `migrate dev` ailleurs qu'en local.

### MongoDB

Structure dans [`infra/mongo/init.js`](../../infra/mongo/init.js) (validateurs et index), décrite
dans [`doc/api/mongo/mongo-schemas.md`](../api/mongo/mongo-schemas.md). Modifier les deux, puis
`docker compose run --rm mongo-init`. Le script est rejouable et ne supprime jamais d'index.

## 7. La prod

**Accès réservé.** Les identifiants de prod sont dans `.env.production`, qui n'est **pas** dans
git. Pour l'obtenir, le demander à Louis, qui le transmet par un canal privé (gestionnaire de
mots de passe partagé de préférence). Jamais par Discord, mail ou dans un commit.

Une fois le fichier à la racine du projet, toutes les opérations passent par des jobs Docker
ponctuels, sans rien installer :

```bash
# Vérifier que tout répond (lecture seule) : doit finir sur OK
docker compose -f docker-compose.prod-tools.yml --env-file .env.production run --rm check

# Après la fusion d'une PR qui ajoute une migration PostgreSQL
docker compose -f docker-compose.prod-tools.yml --env-file .env.production run --rm identity-migrate
docker compose -f docker-compose.prod-tools.yml --env-file .env.production run --rm travel-migrate

# Après une modification de infra/mongo/init.js
docker compose -f docker-compose.prod-tools.yml --env-file .env.production run --rm mongo-init

# Après une modification de infra/postgres/bootstrap.sql (rôles, schémas, extensions)
docker compose -f docker-compose.prod-tools.yml --env-file .env.production run --rm pg-bootstrap
```

Règles pour la prod :
- on n'y applique que ce qui est **fusionné dans `develop`** ;
- jamais `docker compose up` / `down -v`, ni les scripts de test, avec `.env.production` ;
- les jobs sont rejouables : en cas de doute, relancer `check` ;
- consoles web pour regarder les données : Neon (onglet *Tables*), Atlas (*Data Explorer*),
  Upstash (*Data Browser*). Les accès se demandent aussi à Louis.

## 8. Dépannage

| Symptôme | Cause | Solution |
|---|---|---|
| `Cannot connect to the Docker daemon` / `error during connect` | Docker Desktop n'est pas lancé | Le démarrer, attendre « Engine running » |
| `port is already allocated` / `address already in use` | Un autre programme utilise le port (souvent un MongoDB ou PostgreSQL installé sur la machine) | Dans `.env`, changer `MONGO_PORT` (ex. `27018`), `PG_PORT`, etc., et le port dans les URLs du même fichier, puis `docker compose up -d` |
| `identity-migrate` en `Exited (1)`, erreur `role "triply_identity" does not exist` ou `\r` dans les logs | Scripts récupérés avec des fins de ligne Windows | `git config --global core.autocrlf input`, puis `git rm --cached -r . -q` et `git reset --hard`, puis `docker compose down -v` et `up -d` (attention : `reset --hard` efface les modifications non commitées) |
| `postgres` redémarre en boucle, message sur `pg_upgrade` ou `/var/lib/postgresql` | Volume créé avec une ancienne version de PostgreSQL | `docker compose down -v` puis `up -d` (données de dev perdues) |
| `npm error` dans `*-migrate` | Pas d'accès à Internet pour télécharger Prisma | Vérifier la connexion (proxy d'école ?), relancer `docker compose run --rm travel-migrate` |
| Prod : `mongo-init` ou `check` bloque puis `timed out` | Ton adresse IP n'est pas autorisée sur Atlas | Demander l'ajout de ton IP dans Atlas, *Network Access* |
| Prod : première requête lente | Neon met la base en veille après 5 min d'inactivité | Normal, la suivante est rapide |

## Pour aller plus loin

- [`bases-de-donnees.md`](bases-de-donnees.md) : architecture des environnements, offres gratuites et leurs limites, création des comptes de prod.
- [`doc/api/postgres/mcd-mld.md`](../api/postgres/mcd-mld.md) : le modèle PostgreSQL (28 tables) et son implémentation.
- [`doc/api/postgres/orm.md`](../api/postgres/orm.md) : pourquoi Prisma, et les règles de migration.
- [`doc/api/mongo/choix-odm-mongodb.md`](../api/mongo/choix-odm-mongodb.md) et [`doc/api/redis/orm.md`](../api/redis/orm.md) : MongoDB et Redis.
