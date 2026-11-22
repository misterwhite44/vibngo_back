# Bases de données : environnements de dev et de prod

Deux environnements, **0 € l'un comme l'autre** :

| Base | Développement (local) | Production (offres gratuites) |
|---|---|---|
| PostgreSQL (Identity, Travel) | Conteneur `pgvector/pgvector:pg18` | [Neon](https://neon.com) Free, PostgreSQL 18, région Frankfurt |
| MongoDB (Assistant) | Conteneur `mongo:8.0`, replica set à un nœud | [MongoDB Atlas](https://www.mongodb.com/atlas) cluster Free (8.0), région Paris ou Frankfurt |
| `redis-core` (sessions, BullMQ, propositions) | Conteneur `redis:7.4`, AOF, `noeviction` | [Upstash](https://upstash.com) Free, éviction désactivée |
| `redis-cache` (fiches, classements) | Conteneur `redis:7.4`, sans persistance, `allkeys-lru` | [Redis Cloud](https://redis.io/cloud/) Free 30 Mo, éviction `allkeys-lru` |

Les deux environnements utilisent **les mêmes scripts** pour créer la structure :

| Fichier | Rôle |
|---|---|
| `infra/postgres/bootstrap.sql` | Rôles `triply_identity` / `triply_travel`, schémas `identity` / `travel`, droits (`doc/api/postgres/orm.md`) |
| `infra/postgres/dev-init.sh` | Lance `bootstrap.sql` au premier démarrage du conteneur de dev, et donne `CREATEDB` aux rôles (base fantôme de `prisma migrate dev`) |
| `infra/mongo/init.js` | Collections, validateurs et index de la base `assistant`, dont le TTL de 90 jours sur `analytics_events` (`doc/api/mongo/choix-odm-mongodb.md`) |
| `docker-compose.yml` | Bases de **dev** |
| `docker-compose.prod-tools.yml` | Jobs ponctuels pour la **prod** : `pg-bootstrap`, `mongo-init`, `check` |
| `.env.example` / `.env.production.example` | Modèles de variables, sans secret. Les vrais fichiers `.env` et `.env.production` sont ignorés par git |

Les deux scripts sont rejouables : relancés, ils ne cassent rien et ne suppriment rien.

---

## Développement

Prérequis : Docker Desktop (ou Docker Engine + Compose v2). Rien d'autre à installer.

```bash
cp .env.example .env        # Windows PowerShell : Copy-Item .env.example .env
docker compose up -d
docker compose ps           # tout doit être "healthy", mongo-init "Exited (0)"
```

Au premier démarrage :

- PostgreSQL crée la base `triply`, puis les rôles et les schémas ;
- `mongo-init` initialise le replica set, crée les collections, validateurs et index, puis s'arrête.

Les microservices lancés sur la machine utilisent les URLs déjà prêtes dans `.env`
(`IDENTITY_DATABASE_URL`, `TRAVEL_DATABASE_URL`, `MONGO_URL`, `REDIS_CORE_URL`,
`REDIS_CACHE_URL`). Depuis un conteneur du même compose, remplacer `localhost` par le nom du
service (`postgres`, `mongo`, `redis-core`, `redis-cache`) et retirer `directConnection=true`.

| Besoin | Commande |
|---|---|
| Arrêter (données gardées) | `docker compose stop` |
| Tout effacer et repartir de zéro | `docker compose down -v` puis `docker compose up -d` |
| Rejouer l'init MongoDB | `docker compose run --rm mongo-init` |
| Console SQL (rôle Identity) | `docker compose exec postgres psql -U triply_identity -d triply` |
| Console MongoDB | `docker compose exec mongo mongosh assistant` |
| Console Redis | `docker compose exec redis-core redis-cli -a core_dev` |

Prisma en dev, par service : `prisma migrate dev --name <nom>` avec l'URL du service. Le
rôle ne voit que son schéma : `triply_travel` n'a aucun droit sur `identity`, et personne ne
peut créer de table dans `public`.

Dev et prod tournent en **PostgreSQL 18** (version par défaut de Neon). Un volume créé avec
une version plus ancienne ne démarre pas en 18 : `docker compose down -v` puis `up -d`.

Les ports ne sont ouverts que sur `127.0.0.1`. S'ils sont déjà pris, les changer dans `.env`
(`PG_PORT`, `MONGO_PORT`, `REDIS_CORE_PORT`, `REDIS_CACHE_PORT`) et dans les URLs.

---

## Production

À faire une fois. Toutes les régions sont en Europe (RGPD, voir
`documentation/Triply_officiel/Normes et conformité.pdf`). Aucune carte bancaire n'est demandée
par Neon, Upstash ni Atlas pour leur offre gratuite.

**Attention Upstash** : ajouter un moyen de paiement fait passer toutes les bases gratuites du
compte en offre payante. Ne pas en ajouter tant qu'on reste en gratuit.

### 1. Créer les services

1. **Neon** : nouveau projet, PostgreSQL 18 (version par défaut de Neon), région *AWS Europe Central 1 (Frankfurt)* (non
   modifiable ensuite). Créer une base `triply`. Récupérer la chaîne de connexion **directe**
   (hôte sans `-pooler`) du rôle propriétaire `neondb_owner` → `PG_ADMIN_URL`.
2. **MongoDB Atlas** : nouveau projet, cluster *Free*, région Europe (Paris ou Frankfurt).
   - *Database Access* : deux utilisateurs.
     `triply_assistant_admin` avec `readWrite` + `dbAdmin` sur la base `assistant` (job
     d'initialisation), et `triply_assistant` avec `readWrite` sur `assistant` (application).
   - *Network Access* : autoriser l'IP de l'hébergeur des services (et la sienne le temps
     de lancer le job). `0.0.0.0/0` seulement si l'hébergeur n'a pas d'IP fixe.
   - Récupérer les chaînes `mongodb+srv://` → `MONGO_ADMIN_URL` et `MONGO_URL`.
3. **Upstash** (`redis-core`) : base Redis, région Europe (Frankfurt), TLS activé.
   **Laisser l'éviction désactivée** (réglage par défaut) : une révocation de JWT ou un job
   BullMQ ne doit jamais être évincé. URL `rediss://...` → `REDIS_CORE_URL`.
4. **Redis Cloud** (`redis-cache`) : base *Free 30 Mo*, région Europe. Régler la politique
   d'éviction sur `allkeys-lru`. URL → `REDIS_CACHE_URL`.

### 2. Remplir `.env.production`

```bash
cp .env.production.example .env.production
```

Remplacer chaque `CHANGE_ME` et chaque `xxxx`. Pour `PG_IDENTITY_PASSWORD` et
`PG_TRAVEL_PASSWORD`, choisir des mots de passe longs et aléatoires : ce sont les mots de
passe que le script va donner aux rôles, à reporter ensuite dans les URLs des services.

### 3. Créer la structure

```bash
docker compose -f docker-compose.prod-tools.yml --env-file .env.production run --rm pg-bootstrap
docker compose -f docker-compose.prod-tools.yml --env-file .env.production run --rm mongo-init
docker compose -f docker-compose.prod-tools.yml --env-file .env.production run --rm check
```

`check` se connecte avec les identifiants **des services** (pas les admins) et doit finir sur
`OK`.

### 4. Brancher les services

| Variable | Utilisée par |
|---|---|
| `IDENTITY_DATABASE_URL` / `TRAVEL_DATABASE_URL` (hôte `-pooler`) | Le service, à l'exécution |
| `IDENTITY_DATABASE_URL_DIRECT` / `TRAVEL_DATABASE_URL_DIRECT` (hôte direct) | Le conteneur `<service>-migrate` : `prisma migrate deploy` |
| `MONGO_URL`, `MONGO_DB` | Assistant, avec `autoIndex: false` et `autoCreate: false` |
| `REDIS_CORE_URL`, `REDIS_CACHE_URL` | Tous les services, via leurs clients `core` / `cache` |

En prod, seule `prisma migrate deploy` tourne (jamais `migrate dev` ni `db push`, voir
`doc/api/postgres/orm.md`). Les URL `PG_ADMIN_URL` et `MONGO_ADMIN_URL` ne doivent jamais
être données aux services. Sur l'hébergeur ou dans la CI, ces valeurs vont dans les secrets,
pas dans un fichier.

### Limites des offres gratuites (relevées le 22 novembre 2026)

| Service | Limites | Conséquence pour nous |
|---|---|---|
| Neon Free | 1 Go par projet, 100 CU-heures/mois, mise en veille après 5 min d'inactivité (non désactivable), 6 h d'historique de restauration | Première requête après une pause un peu plus lente. Un projet inactif 90 jours peut être supprimé |
| Atlas Free | 0,5 Go (données + index), 100 opérations/s, 500 connexions, pas de sauvegarde (aperçu privé seulement), pause après 30 jours sans connexion | Largement suffisant au MVP. Sauvegarde : `mongodump` à la main si besoin |
| Upstash Free | 1 base par compte, 250 Mo, **500 000 commandes/mois** | Voir ci-dessous |
| Redis Cloud Free | 30 Mo, une base | Suffisant pour un cache qui peut être vidé |

**Point d'attention BullMQ.** Les workers BullMQ envoient des commandes à Redis même quand la
file est vide. Sur Upstash, cela consomme le quota de 500 000 commandes/mois. Pour tenir dans
le gratuit : peu de workers, `drainDelay` élevé, et surveiller la consommation dans la console
Upstash. Si le quota ne tient pas, `redis-core` est la première base à rapatrier sur le VPS
prévu (`docker-compose.yml` contient déjà sa configuration).

### Passer plus tard sur le VPS

Le budget prévoit à terme un VPS avec les bases en conteneurs (`documentation/Triply_officiel/Triply - besoins matériels et budget.pdf`).
Ce jour-là, rien ne change côté code : mêmes scripts d'init, seules les URLs changent.

### À vérifier lors de la première mise en place

- Les scripts ont été testés en local, y compris `pg-bootstrap` avec un rôle propriétaire non
  superutilisateur (comme `neondb_owner` sur Neon). Ils n'ont pas encore été lancés sur Neon ni
  sur Atlas.
- La documentation Atlas ne liste pas `collMod`, les validateurs ni les index TTL parmi les
  commandes limitées sur un cluster Free, mais un premier lancement de `mongo-init` le confirmera.
- Région Europe et réglage de l'éviction sur l'offre gratuite de Redis Cloud : à confirmer à la
  création de la base.
