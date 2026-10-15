# Structures Redis — clés et contrats

Complète `endpoints.md` avec les corps de requête/réponse et les structures conservées
dans Redis. Les contrats ci-dessous sont des propositions à relire. Redis ne remplace pas
les bases métier : les données persistantes restent détenues par Identity, Travel ou
Assistant.

**Convention** : `champ?` = optionnel ; `date` = ISO 8601 ; les durées de vie indiquées
« à fixer » sont des décisions ouvertes. Les réponses de liste sont enveloppées dans un
objet nommé.

## Authentification et sessions

**POST /auth/logout**
```
→ (rien — session identifiée par le jeton)
← 204
```

**GET /auth/sessions**
```
← 200 { sessions: [{ id: string, createdAt: date, lastSeenAt: date?, current: boolean }] }
```

**DELETE /auth/sessions/:sessionId**
```
← 204
```

**DELETE /auth/sessions**
```
← 204
```

Le JWT contient un `jti` unique. Un marqueur de révocation est associé à l'identifiant de
session ; la Gateway vérifie ce marqueur après la signature et l'expiration du jeton.
L'expiration du marqueur ne dépasse pas la durée de validité restante du jeton.

Clé proposée :
```
identity:session:revoked:<jti> → { revokedAt: date }
TTL : jusqu'à l'expiration du JWT concerné
```

La durée de vie et la révocation des refresh tokens sont à harmoniser avec le contrat
d'authentification.

## Génération et propositions d'itinéraire

**POST /trips/generate**
```
→ {
    originCityId: string, destinationCityId: string,
    startDate: date, endDate: date,
    budget?: number, transportMode?: string,
    travelersUserIds?: string[]
  }
← 202 {
    taskId: string,
    status: enum(queued|processing),
    statusUrl: string
  }
```

**GET /trips/generations/:taskId**
```
← 202 { taskId: string, status: enum(queued|processing) }
← 200 {
    taskId: string, status: "completed", proposalId: string,
    days: [{ dayIndex: number, date: date, steps: [
      { sequence: number, type: enum(activity|transport|accommodation|meal),
        activityId: string?, startTime: date?, endTime: date? }
    ]}]
  }
← 200 { taskId: string, status: "failed", error: { code: string, message: string } }
```

**POST /trips/generations/:taskId/regenerate**
```
→ { feedback?: string }
← 202 { taskId: string, status: enum(queued|processing), statusUrl: string }
```

**POST /trips/proposals/:proposalId/confirm**
```
→ (rien ; accepte l'en-tête Idempotency-Key)
← 201 { trip: { id: string, status: string } }
```

**DELETE /trips/proposals/:proposalId**
```
← 204
```

Structure de proposition proposée :
```
assistant:itinerary:proposal:<proposalId> → {
  ownerId: string,
  status: enum(ready|confirmed|discarded),
  requestHash: string,
  createdAt: date,
  itinerary: object
}
TTL : durée de conservation de la proposition, à fixer
```

Une proposition est temporaire, liée à son propriétaire et non persistée comme itinéraire
avant confirmation. L'identifiant de proposition sert de clé d'idempotence côté Travel
afin que les confirmations répétées ne créent pas plusieurs voyages.

## Travaux asynchrones

**POST /trips/:tripId/journal/exports**
```
→ (rien)
← 202 { jobId: string, status: "queued", statusUrl: string }
```

**GET /jobs/:jobId**
```
← 202 { jobId: string, type: string, status: enum(queued|processing) }
← 200 { jobId: string, type: string, status: "completed", result: { pdfUrl: string } }
← 200 { jobId: string, type: string, status: "failed", error: { code: string, message: string } }
```

**DELETE /jobs/:jobId**
```
← 204
```

Les payloads BullMQ sont internes et contiennent une référence au travail métier, son
propriétaire si nécessaire et un identifiant de corrélation. La route `GET /jobs/:jobId`
vérifie que l'utilisateur est autorisé à consulter ce travail. Noms de files, identifiants
internes Redis et payloads bruts ne sont jamais renvoyés.

## Clés d'idempotence

Pour les opérations rejouables, l'en-tête `Idempotency-Key` est mémorisé avec le principal,
l'opération et l'empreinte du corps :
```
<service>:idempotency:<principalId>:<operation>:<key> → {
  requestHash: string,
  status: enum(processing|completed),
  response?: object,
  createdAt: date
}
TTL : durée de rétention des répétitions client, à fixer
```

Même clé et même empreinte : retourner le résultat existant ou l'état du traitement.
Même clé avec un corps différent : rejeter la requête (`422`). Une contrainte d'unicité
dans la base métier reste nécessaire pour éviter les doublons en cas de panne entre Redis
et la persistance.

## Cache

Le cache n'a pas d'endpoint public propre : les routes de catalogue et de génération
renvoient la même réponse qu'en cas de lecture ou calcul sans cache.

| Donnée | Clé proposée | Valeur |
|---|---|---|
| Fiche destination | `travel:cache:destination:<id>` | Fiche lue depuis le catalogue |
| Fiche activité | `travel:cache:activity:<id>` | Fiche lue depuis le catalogue |
| Classement | `assistant:cache:recommendations:<profileHash>:<filtersHash>:<modelVersion>` | Résultat du classement |
| Génération | `assistant:cache:itinerary:<requestHash>:<modelVersion>` | Résultat réutilisable de génération |

Les empreintes reposent sur des paramètres canoniques. La clé de génération couvre toutes
les contraintes qui influencent le résultat ; les versions de modèle et de données sont
incluses ou intégrées à l'empreinte. TTL et règles d'invalidation sont à fixer. Une
éviction ou un défaut de cache entraîne une relecture de la source ou un recalcul, jamais
une réponse positive par défaut.

## Limitation de débit (Bonus)

Une requête dépassant la limite reçoit :
```
← 429 {
    statusCode: 429,
    message: "Too Many Requests",
    retryAfterSeconds: number
  }
```

En-tête proposé : `Retry-After: <secondes>`.

Clé proposée :
```
gateway:rate-limit:<subject>:<route>:<window> → compteur entier
TTL : fin de fenêtre
```

L'incrément et la définition du TTL initial doivent être atomiques. Les seuils et la
stratégie de fenêtre sont à définir.

## Pannes et erreurs

| Situation | Réponse / comportement proposé |
|---|---|
| Cache indisponible | Continuer sans cache si la source ou le calcul est disponible. |
| Redis de session indisponible | `503 Service Unavailable` ; ne pas accepter un JWT dont la révocation n'a pas pu être vérifiée. |
| Échec de mise en file | `503 Service Unavailable` ; ne pas répondre `202`. |
| Tâche ou proposition inconnue/expirée | `404 Not Found`. |
| Clé d'idempotence réutilisée avec un autre corps | `422 Unprocessable Entity`. |
| Dépassement de limite | `429 Too Many Requests`, avec `Retry-After` si disponible. |

## Points à valider

- TTL des propositions, caches et clés d'idempotence.
- Contrat JWT (`jti`, refresh tokens, durée d'accès) et format de l'identifiant de session.
- États définitifs des tâches, erreurs exposées et durée de rétention des jobs terminés.
- Format/version des valeurs sérialisées, tailles maximales et migration des formats.
- Persistance, éviction, sauvegardes et haute disponibilité des deux rôles Redis.
- Seuils et fenêtre de `Rate_limit`, si le Bonus est retenu.
