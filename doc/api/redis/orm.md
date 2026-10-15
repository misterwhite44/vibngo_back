# Client Redis et files de travaux

Ce document propose l'accès à Redis pour les microservices NestJS. Redis est une
infrastructure partagée : il n'y a pas de schéma de base relationnelle ni de migrations
Prisma à exécuter. Les règles de propriété des données restent celles de
`doc/services/microservices.md`.

## Décision proposée

Utiliser **`redis` (node-redis)** pour les opérations Redis applicatives, avec un module
NestJS dédié qui expose des connexions nommées séparément :

- `redis-core` pour les sessions/révocations, l'idempotence, les propositions et les
  files ;
- `redis-cache` pour les caches et, si le Bonus est activé, les compteurs de limitation.

Utiliser **BullMQ** pour les traitements asynchrones, avec sa propre configuration de
connexion à `redis-core`. Les services publient et consomment des tâches via BullMQ ; ils
n'écrivent pas eux-mêmes dans les clés internes de BullMQ.

Les versions exactes des dépendances restent à épingler au moment de l'implémentation.

## Ce que le client doit permettre

| Besoin | Usage dans le projet |
|---|---|
| Connexions configurables et typées | Clients séparés selon les rôles `core` et `cache`, paramètres injectés par configuration |
| Expiration explicite des clés | Sessions révoquées, propositions, idempotence et caches ont des durées de vie distinctes |
| Opérations atomiques | Création/incrémentation avec TTL, réservation d'une clé d'idempotence et transitions d'état |
| Opérations groupées | Chargement de plusieurs fiches ou suppression de clés appartenant à un utilisateur |
| Files et reprise des travaux | BullMQ gère les jobs persistants, tentatives et états d'exécution |
| Arrêt propre | Les connexions et workers sont fermés au cycle de vie NestJS |

## Pourquoi séparer `core` et `cache`

Les caches peuvent être évincés et reconstruits depuis leur source. Les marqueurs de
révocation, les files BullMQ, les propositions et les clés d'idempotence ne doivent pas
disparaître prématurément. Les deux rôles doivent donc avoir des politiques de mémoire,
d'éviction et de persistance distinctes ; ils peuvent être déployés sur deux instances ou
deux configurations isolées si les garanties équivalentes sont assurées.

Un cache miss ou une éviction ne change jamais la source de vérité. A contrario, si
`redis-core` est indisponible, le service ne doit pas annoncer une révocation ou un travail
asynchrone qu'il n'a pas pu enregistrer.

## Intégration NestJS proposée

Un module d'infrastructure par service fournit des providers nommés et ferme les
connexions à l'arrêt. Les URL, secrets et options sont injectés par variables
d'environnement ; aucun service métier ne construit une URL Redis ni ne dépend d'un
singleton global non typé.

```ts
// Forme indicative : les noms et l'API exacte dépendront du module d'intégration retenu.
export const REDIS_CORE = Symbol('REDIS_CORE');
export const REDIS_CACHE = Symbol('REDIS_CACHE');
```

Les services métier dépendent d'interfaces (`SessionStore`, `CacheStore`,
`IdempotencyStore`) plutôt que d'appels Redis dispersés dans les contrôleurs. Les
composants qui utilisent BullMQ dépendent d'une queue dédiée par type de travail.

## Fiabilité et sécurité

- `redis-core` n'utilise pas de politique d'éviction ; la persistance et la haute
  disponibilité sont configurées au niveau de l'infrastructure.
- `redis-cache` peut évincer les clés ; les TTL rendent la durée de vie fonctionnelle
  explicite.
- Les opérations composées dont la correction dépend de l'atomicité utilisent une
  transaction Redis ou un script atomique, pas une séquence de commandes concurrentes.
- Les noms de clés applicatives commencent par le propriétaire (`identity:`, `travel:`,
  `assistant:`). Les identifiants utilisateurs et paramètres inclus dans les clés sont
  normalisés et ne contiennent pas de données personnelles inutiles.
- Les clés et messages de queue ne contiennent pas de secrets ni de contenu personnel
  complet lorsqu'une référence vers les données détenues par le service suffit.
- Les connexions sont protégées par authentification réseau, chiffrement en transit et
  isolation réseau ; les accès de chaque microservice sont limités à ses besoins.
- Le client n'est jamais exposé au front ni à un endpoint générique de commandes Redis.

## À confirmer avant implémentation

- Le choix du client Redis et du module d'intégration NestJS, ainsi que leurs versions.
- La topologie (instances séparées, service managé ou déploiement isolé) et les garanties
  de persistance/haute disponibilité de `redis-core`.
- Les stratégies de connexion, timeout, reconnexion et fermeture propre.
- Les tailles maximales des valeurs en cache et les limites mémoire.
- La politique de journalisation et de métriques (latence, erreurs, saturation, jobs en
  attente et échecs définitifs).
