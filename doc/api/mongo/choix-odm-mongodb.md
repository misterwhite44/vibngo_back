# Choix de l'ODM pour MongoDB — vibngo (microservice Assistant)


## Résumé

Nous proposons **Mongoose 9 avec `@nestjs/mongoose`** pour les trois collections MongoDB du microservice Assistant. C'est la seule option qui couvre tous nos besoins sans contournement : intégration NestJS officielle, index TTL déclarés dans le schéma, installation locale sans contrainte. Prisma est écarté pour MongoDB : sa version 7 ne gère pas MongoDB et sa version 6 ne reçoit plus que des correctifs de sécurité jusqu'au 19 novembre 2026.

| Rubrique | Valeur |
| --- | --- |
| Projet | vibngo (anciennement Triply) |
| Microservice concerné | Assistant |
| Collections | `conversations`, `messages`, `analytics_events` |
| Statut | Proposé, à confirmer par l'équipe backend |
| Décision de référence | MONGO-01 (section 7) |
| Document jumeau | Choix de l'ORM pour PostgreSQL (`choix-orm.md`) |

## Contexte et besoins

Le microservice Assistant stocke dans MongoDB l'historique du chatbot et les événements d'analyse, et il a besoin d'un outil d'accès aux données (un ODM) qui s'intègre à NestJS, valide les documents et gère les index. Le choix s'inscrit dans l'architecture décidée : microservices NestJS, chaque service propriétaire de ses données, ODM isolé derrière une interface de dépôt (Clean Architecture).

| Besoin | Pourquoi |
| --- | --- |
| Intégration NestJS (injection de dépendances) | Stack décidée : React Native et NestJS |
| Validation des documents (types, champs obligatoires, valeurs permises) | Données de conversation et d'analyse à fiabiliser |
| Index TTL sur `analytics_events` (suppression après 90 jours) | Conservation limitée des données (RGPD) |
| Index composés et index de purge par `userId` | Listes paginées et suppression du compte |
| Installation locale simple | Toute l'équipe travaille avec Docker Compose |
| ODM caché derrière une interface de dépôt | Possibilité de le remplacer sans toucher au métier |

**Définitions utiles**

- **ODM** : bibliothèque qui relie le code (objets TypeScript) aux documents MongoDB, l'équivalent d'un ORM pour une base relationnelle.
- **Index TTL** : index MongoDB qui supprime automatiquement les documents plus anciens qu'une durée donnée. La suppression n'est pas instantanée.
- **Validateur** : règle `$jsonSchema` appliquée par MongoDB lui-même à chaque écriture, même si elle ne passe pas par notre application.
- **Replica set** : groupe de serveurs MongoDB qui se répliquent. Il est indispensable pour les transactions et il est la norme en production.

## Options étudiées

Trois solutions ont été comparées, toutes utilisables avec Node.js et TypeScript.

**1. Mongoose avec `@nestjs/mongoose`.** Mongoose est l'ODM le plus répandu pour MongoDB. [Mongoose 9](https://mongoosejs.com/docs/version-support.html) est la version courante depuis novembre 2025. Le module `@nestjs/mongoose` apporte les décorateurs `@Schema` et `@Prop`, la fabrique `SchemaFactory` et l'injection `@InjectModel`.

**2. Driver MongoDB natif (`mongodb`).** C'est le driver officiel de MongoDB, sur lequel Mongoose s'appuie. Il offre un contrôle total mais ne fournit ni validation côté application, ni intégration NestJS : tout est à écrire.

**3. Prisma pour MongoDB.** Prisma est un ORM déjà envisagé pour PostgreSQL. Pour MongoDB, [Prisma 7 ne le gère pas encore](https://www.prisma.io/docs/orm/v7/core-concepts/supported-databases/mongodb) et renvoie vers Prisma 6.19. La version 8 propose une bibliothèque MongoDB, mais elle est encore en [release candidate](https://www.prisma.io/docs/orm/release-status).

## Comparaison par critère

Mongoose est la seule option sans point bloquant : le driver natif exige beaucoup de code à écrire, et Prisma échoue sur la version stable, le TTL et l'installation locale.

| Critère | Mongoose 9 + `@nestjs/mongoose` | Driver MongoDB natif | Prisma pour MongoDB |
| --- | --- | --- | --- |
| État de la version | Version 9 courante | Driver officiel | Prisma 7 sans MongoDB ; Prisma 6.19 : correctifs de sécurité seulement jusqu'au 19 nov. 2026 ; Prisma 8 en release candidate |
| Intégration NestJS | Module officiel (`@Schema`, `@Prop`, `@InjectModel`) | Pas de module officiel ; fournisseur à écrire | Pas de module officiel ; service à écrire |
| Validation de schéma | Côté application : types, `required`, `enum`, validateurs personnalisés. Ne protège pas des écritures faites hors de l'application | Aucune côté application ; validateur `$jsonSchema` possible côté base | Typage à la compilation ; pas de validateur côté base |
| Index TTL | Déclaré dans le schéma avec `expireAfterSeconds` | `createIndex` avec `expireAfterSeconds` | Non déclarable dans le schéma ; [demande ouverte](https://github.com/prisma/prisma/issues/5430) ; commandes brutes nécessaires |
| Index et collections au démarrage | `autoIndex` et `autoCreate`, à désactiver en production | Entièrement manuel | `prisma db push` ; pas de migrations pour MongoDB |
| Installation locale | Un `mongod` simple suffit | Un `mongod` simple suffit | Replica set exigé en versions 6 et 7 ; un seul `mongod` suffit en version 8 hors transactions |
| Typage | Types inférés du schéma ou de la classe | `Collection<T>` sans contrôle à l'exécution | Types générés |
| Requêtes complexes | `aggregate()` ; driver natif accessible via la connexion | Tout est possible | Limité ; commandes brutes pour le reste |

## Évaluation pondérée

Mongoose obtient 4,70 sur 5, loin devant le driver natif (3,75) et Prisma (2,00). Les notes (de 0 à 5) et les poids (total 100) sont une appréciation de l'auteur, destinée à structurer la discussion et non à la remplacer.

| Critère | Poids | Mongoose | Driver natif | Prisma |
| --- | --- | --- | --- | --- |
| Intégration NestJS | 20 | 5 | 2 | 3 |
| Index TTL et gestion des index | 20 | 5 | 5 | 1 |
| Maturité et stabilité de la version | 20 | 5 | 5 | 1 |
| Validation de schéma | 15 | 4 | 2 | 2 |
| Installation locale | 10 | 5 | 5 | 2 |
| Typage et confort de développement | 10 | 4 | 3 | 4 |
| Contrôle et requêtes complexes | 5 | 4 | 5 | 2 |
| **Score pondéré (sur 5)** | **100** | **4,70** | **3,75** | **2,00** |

Le score se calcule en multipliant chaque note par son poids, en additionnant, puis en divisant par 100. Le classement ne change pas si l'on modifie les poids de quelques points : l'écart tient aux critères bloquants pour Prisma (version stable, TTL) et à l'effort d'intégration pour le driver natif.

## Recommandation

Adopter **Mongoose 9 avec `@nestjs/mongoose`**, derrière des interfaces de dépôt, pour les trois collections de l'Assistant.

1. Elle répond à tous les critères, sans contournement.
2. L'intégration NestJS est officielle et bien établie.
3. Les index TTL et composés se déclarent dans le schéma, au même endroit que les champs.
4. L'installation locale ne demande aucune configuration particulière.
5. Elle évite de dépendre d'une version de Prisma arrivant en fin de vie ou pas encore stable.

**Point d'attention : la version de `@nestjs/mongoose`.** La série [11.x](https://app.unpkg.com/@nestjs/mongoose@11.0.4/files/package.json) est compatible avec Nest 10 et 11 et avec Mongoose 7 à 9. La série [12.x](https://github.com/nestjs/mongoose/releases/tag/12.0.0), alignée sur Nest 12, est publiée en module ES pur ; elle fonctionne depuis une application CommonJS avec Node.js 20.19+ ou 22.12+. La version à retenir dépend donc de la version de NestJS du projet.

**Quand revoir ce choix**

- Si Prisma 8 devient stable avec un support MongoDB complet (index TTL compris) et que l'équipe veut un seul outil pour les deux bases.
- Si une collection demande des opérations très fines : on utilise alors le driver natif dans un dépôt, via la connexion Mongoose (`connection.db`), sans changer d'outil.

## Note de décision MONGO-01

La décision MONGO-01 retient Mongoose 9 pour MongoDB, sous réserve de confirmation par l'équipe backend.

| Rubrique | Contenu |
| --- | --- |
| Numéro | MONGO-01 |
| Date | 9 octobre 2026 |
| Statut | Proposé, à confirmer par l'équipe backend |
| Contexte | Microservice Assistant, trois collections MongoDB, ODM caché derrière une interface de dépôt |
| Décision | Mongoose 9 avec `@nestjs/mongoose` (série majeure alignée sur la version de NestJS). Index et validateurs créés par un job d'initialisation, pas par l'application |
| Alternatives écartées | Driver natif : contrôle total mais beaucoup de code répétitif. Prisma : pas de support MongoDB en version 7, version 6 en fin de vie, pas d'index TTL, replica set exigé en local |
| Conséquences | `autoIndex` et `autoCreate` désactivés en production. Script d'initialisation idempotent, versionné dans git. `syncIndexes` interdit en production, car il supprime des index |
| Révision | À la sortie stable de Prisma 8 avec un support MongoDB complet |

## Index et validateurs au démarrage

En production, un job d'initialisation à usage unique crée les collections, les validateurs et les index avant le démarrage de l'application, qui ne les crée plus elle-même. Mongoose sait tout créer au démarrage, mais cela relance la construction des index à chaque démarrage de chaque réplica, avec un coût possible ; sa documentation recommande de désactiver ce comportement en production. De plus, `syncIndexes` supprime les index absents du schéma : trop risqué pour tourner automatiquement.

| Environnement | Réglage de l'application | Structure créée par |
| --- | --- | --- |
| Développement et tests | `autoIndex` et `autoCreate` activés, par commodité | L'application ou le job |
| Staging et production | `autoIndex: false`, `autoCreate: false` | Le job d'initialisation |

**Déroulement à chaque déploiement**

1. Le job d'initialisation démarre une fois, après que MongoDB est prêt.
2. Il crée chaque collection avec son validateur, ou met à jour le validateur d'une collection existante.
3. Il crée les index. Recréer un index identique ne fait rien, donc le script est rejouable sans dégât.
4. L'application démarre seulement si le job a réussi.

**Déclaration dans le schéma (application)**

Les index restent déclarés dans le schéma, source de vérité lisible, mais l'application ne les crée pas en production.

```ts
@Schema({ collection: 'analytics_events', autoIndex: false, autoCreate: false })
export class AnalyticsEvent {
  @Prop({ required: true }) userId: string;
  @Prop({ required: true, enum: ['recommendation_viewed', 'recommendation_clicked', 'funnel_step'] })
  type: string;
  @Prop({ required: true }) occurredAt: Date;
  @Prop({ required: true }) receivedAt: Date;
}

export const AnalyticsEventSchema = SchemaFactory.createForClass(AnalyticsEvent);
AnalyticsEventSchema.index({ type: 1, occurredAt: -1 });
AnalyticsEventSchema.index({ userId: 1 });
AnalyticsEventSchema.index({ receivedAt: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 90 }); // 90 jours
```

**Script d'initialisation (job)**

Il utilise le driver natif. Un index TTL existant ne se recrée pas avec une autre durée : la fonction `ensureTtl` bascule alors sur la commande `collMod`.

```ts
const MESSAGES_VALIDATOR = { $jsonSchema: {
  bsonType: 'object',
  required: ['conversationId', 'userId', 'role', 'content', 'createdAt'],
  properties: {
    role: { enum: ['user', 'assistant'] },
    content: { bsonType: 'string', minLength: 1 },
    createdAt: { bsonType: 'date' },
  },
} };

async function ensureCollection(db: Db, name: string, validator: object) {
  const options = { validator, validationLevel: 'strict', validationAction: 'error' };
  const exists = await db.listCollections({ name }).hasNext();
  if (exists) await db.command({ collMod: name, ...options });
  else await db.createCollection(name, options);
}

async function ensureTtl(db: Db, coll: string, name: string, field: string, seconds: number) {
  try {
    await db.collection(coll).createIndex({ [field]: 1 }, { name, expireAfterSeconds: seconds });
  } catch (e: any) {
    if (e.codeName !== 'IndexOptionsConflict') throw e;
    await db.command({ collMod: coll, index: { name, expireAfterSeconds: seconds } });
  }
}

// Appels du job
await ensureCollection(db, 'messages', MESSAGES_VALIDATOR);
await db.collection('messages').createIndex({ conversationId: 1, createdAt: -1, _id: -1 });
await db.collection('messages').createIndex({ userId: 1 });
await db.collection('conversations').createIndex({ userId: 1, lastMessageAt: -1 });
await ensureTtl(db, 'analytics_events', 'ttl_received_at', 'receivedAt', 60 * 60 * 24 * 90);
```

**Règles**

- Un validateur par collection, en `validationLevel: strict` et `validationAction: error`. Pour une première mise en place, passer d'abord en `warn` en staging repère les documents non conformes sans rien bloquer.
- Un test doit vérifier que le validateur et le schéma Mongoose restent d'accord, car ils décrivent les mêmes champs à deux endroits.
- Ne jamais lancer `syncIndexes` automatiquement en production. Pour retirer un index, écrire une étape explicite dans le script.
- Créer un index sur une grosse collection peut ralentir la base le temps de sa construction : prévoir la mise en place hors des heures de pointe.
- Un TTL isolé sur `messages` supprimerait des messages sans toucher à leur conversation et fausserait `messageCount`. La durée de conservation des conversations reste à fixer avec la personne chargée du RGPD.

## Environnement local

Nous recommandons de développer avec un replica set à un seul nœud, même si Mongoose n'en a pas besoin. Il reproduit la production, où MongoDB est toujours un replica set, il permet les transactions et il évite les écarts entre environnements. Son seul coût est la configuration d'un contrôle de santé (`healthcheck`).

| Solution | Replica set en local |
| --- | --- |
| Mongoose | Non obligatoire ; utile seulement pour les transactions |
| Driver natif | Non obligatoire ; utile seulement pour les transactions |
| Prisma 6 et 7 | [Obligatoire](https://www.prisma.io/docs/orm/v7/core-concepts/supported-databases/mongodb), car le connecteur utilise des transactions en interne |
| Prisma 8 (release candidate) | Un seul `mongod` suffit, hors transactions et flux de modifications |

Cette décision a un effet sur le schéma : ajouter un message et incrémenter `messageCount` dans `conversations` ne sont atomiques que dans une transaction. Sans transaction, on insère le message puis on incrémente le compteur ; en cas d'échec entre les deux, le compteur peut dériver et un recomptage le corrige.

**Exemple Docker Compose** (schéma courant, à tester lors de la mise en place)

```yaml
services:
  mongo:
    image: mongo:8                       # version à confirmer
    command: ["--replSet", "rs0", "--bind_ip_all"]
    healthcheck:
      test:
        - CMD
        - mongosh
        - --quiet
        - --eval
        - "try { rs.status().ok } catch (e) { rs.initiate({_id:'rs0',members:[{_id:0,host:'mongo:27017'}]}).ok }"
      interval: 5s
      retries: 20

  assistant-mongo-init:                  # job unique : collections, validateurs, index
    build: ./assistant
    command: ["node", "dist/mongo-init/init.js"]
    environment:
      MONGO_URL: mongodb://mongo:27017/?replicaSet=rs0
      MONGO_DB: assistant
    depends_on:
      mongo: { condition: service_healthy }

  assistant:
    build: ./assistant
    depends_on:
      assistant-mongo-init: { condition: service_completed_successfully }
```

Depuis la machine hôte (hors Docker), la connexion peut demander l'option `directConnection=true`.

## Risques et points de vigilance

Aucun risque n'est bloquant ; les trois premiers demandent une action avant la première mise en production.

| Risque | Conséquence | Mesure |
| --- | --- | --- |
| Mauvaise série de `@nestjs/mongoose` pour la version de NestJS | Erreurs au démarrage ou à l'import | Vérifier la version de NestJS du projet et choisir 11.x ou 12.x en conséquence |
| Validateur et schéma Mongoose qui divergent | Écritures acceptées par l'un et refusées par l'autre | Test automatique qui compare les deux ; validateur d'abord en mode `warn` en staging |
| Compteur `messageCount` qui dérive sans transaction | Nombre de messages affiché faux | Tâche de recomptage, ou transaction si le replica set est utilisé en local et en production |
| Index créé sur une grosse collection en pleine charge | Ralentissement temporaire de la base | Déployer hors des heures de pointe |
| Appel automatique de `syncIndexes` en production | Suppression d'index utiles | Interdit par la décision MONGO-01 |
| Durée de conservation des conversations non fixée | Données conservées plus longtemps que nécessaire (RGPD) | Valider la durée avec la personne chargée du RGPD avant la mise en production |
| Évolution de Prisma 8 vers un support MongoDB complet | Choix à reconsidérer à terme | Interfaces de dépôt : le remplacement reste possible sans toucher au métier |

## Prochaines étapes

Six actions permettent de passer de la proposition à la mise en place.

- [ ] Confirmer la décision MONGO-01 avec l'équipe backend
- [ ] Vérifier la version de NestJS du projet et en déduire la série de `@nestjs/mongoose` (11.x ou 12.x)
- [ ] Valider avec la personne chargée du RGPD la durée de conservation des conversations
- [ ] Réaliser un premier essai technique : un modèle, un index TTL et le job d'initialisation sous Docker Compose
- [ ] Décider si le replica set à un seul nœud devient la norme en local (et donc les transactions)
- [ ] Reporter la décision dans `decisions.md` (ligne « ORM / ODM »)

## Sources et limites

Les informations sur les versions ont été vérifiées le 9 octobre 2026 et doivent être revérifiées sur npm avant d'épingler une version. Seule la page d'état des versions de Prisma a été lue en entier ; les autres pages ont été consultées par extraits de recherche.

**Sources**

- Prisma, état des versions : [Prisma 8 en release candidate, correctifs de sécurité de Prisma 6 jusqu'au 19 novembre 2026](https://www.prisma.io/docs/orm/release-status)
- Prisma, connecteur MongoDB : [Prisma 7 sans MongoDB, replica set exigé](https://www.prisma.io/docs/orm/v7/core-concepts/supported-databases/mongodb)
- Prisma 8, MongoDB : [un seul `mongod` suffit hors transactions](https://docs.prisma.io/docs/prisma-orm/add-to-existing-project/mongodb)
- Prisma, index TTL : [demande ouverte dans l'extrait consulté](https://github.com/prisma/prisma/issues/5430)
- Mongoose, [versions supportées](https://mongoosejs.com/docs/version-support.html) et [discussion sur `autoIndex` et `syncIndexes`](https://github.com/automattic/mongoose/issues/14602)
- `@nestjs/mongoose`, [version 12.0.0 (module ES)](https://github.com/nestjs/mongoose/releases/tag/12.0.0) et [version 11.0.4 (compatibilité)](https://app.unpkg.com/@nestjs/mongoose@11.0.4/files/package.json)
- MongoDB, [index TTL et `collMod`](https://www.mongodb.com/docs/v8.3/core/index-ttl/)

**Limites**

- Les options `autoIndex`, `autoCreate` et le comportement de `syncIndexes` n'ont pas été relus dans la documentation de Mongoose 9 ; la recommandation de désactiver la création automatique en production vient d'anciennes versions de la documentation et d'une discussion sur le dépôt de Mongoose.
- Le schéma Docker Compose du replica set et les extraits de code n'ont pas été exécutés : ils sont à valider lors du premier essai technique.
- Mongoose sait exporter un schéma JSON, mais ses termes diffèrent de `$jsonSchema` de MongoDB (`type` contre `bsonType`) : à vérifier avant de s'en servir pour générer le validateur.
- Les notes et les poids de l'évaluation pondérée sont une appréciation de l'auteur.
