# API MongoDB (microservice Assistant) — collections et corps des requêtes/réponses

Complète `endpoints.md`. Conventions : `../conventions.md`. `champ?` = optionnel. Types
indicatifs (`string`, `number`, `boolean`, `date` = ISO 8601, `enum(a|b|c)`). Les listes
paginées ajoutent `nextCursor: string?`.

**Origine** : `Doc` = repris des documents ; `Décidé` = tranché ensemble ; `Proposé` =
proposition à valider.

---

## Collections MongoDB

Principe *(Proposé)* : une conversation et ses messages sont dans **deux collections
distinctes** (limite de 16 Mo par document, et une conversation peut grossir sans limite).

### `conversations`
```
{
  _id: ObjectId,
  userId: string,              // identifiant interne (UUID), jamais email ni nom
  title: string?,              // Décidé : premiers mots du premier message, 50 caractères max
  tripId: string?,             // Décidé : itinéraire en discussion (identifiant Travel)
  status: enum(active|archived),   // Décidé
  summary: string?,            // Doc : résumé après 10 échanges (interne, non exposé)
  summarizedUpTo: number,      // Proposé : nombre de messages déjà résumés (0 = aucun)
  messageCount: number,        // Proposé : évite de compter à chaque affichage de la liste
  lastMessageAt: date,         // Proposé : tri de la liste
  createdAt: date,
  updatedAt: date
}
```
Index : `{ userId: 1, lastMessageAt: -1 }`.

### `messages`
```
{
  _id: ObjectId,
  conversationId: ObjectId,
  userId: string,              // Proposé : copié pour filtrer et purger sans jointure
  role: enum(user|assistant),
  content: string,
  modelVersion: string?,       // Décidé : réponses de l'assistant uniquement
  createdAt: date
}
```
Index : `{ conversationId: 1, createdAt: -1, _id: -1 }` (pagination) et `{ userId: 1 }`
(purge RGPD). Le champ `proposalId` sera ajouté en V1.2, sans migration.

### `analytics_events`  (B)
```
{
  _id: ObjectId,
  userId: string,              // identifiant interne
  type: enum(recommendation_viewed|recommendation_clicked|funnel_step),   // Décidé
  targetType: enum(destination|activity)?,
  targetId: string?,
  properties: object?,         // Proposé : { position } pour viewed/clicked, { step } pour funnel_step
  occurredAt: date,            // heure côté client (ou serveur pour funnel_step)
  receivedAt: date             // heure côté serveur
}
```
Index : `{ type: 1, occurredAt: -1 }` et `{ userId: 1 }`, plus un index TTL sur
`receivedAt` de **90 jours** *(Proposé : aligné sur les 90 jours du document technologique
pour l'historique de navigation)*.

---

## Chatbot

**POST /chatbot/conversations**
```
→ { tripId?: string }
← 201 { id: string, title: string?, tripId: string?, status: enum(active|archived), createdAt: date }
← 404   // tripId inconnu ou n'appartenant pas à l'utilisateur
```
`title` est vide à la création ; il est renseigné à l'envoi du premier message.

**POST /chatbot/conversations/:id/messages**   header `Idempotency-Key`
```
→ { content: string }                 // 1 à 2000 caractères (limite proposée)
← 201 {
    userMessageId: string,
    reply: { id: string, role: "assistant", content: string, createdAt: date },
    proposal?: <voir ci-dessous — V1.2 uniquement>
  }
← 404   // conversation inconnue ou d'un autre utilisateur
← 422   // contenu vide ou trop long
← 429   // limite de requêtes
← 503 { code: "llm_unavailable", retryable: true }   // le message de l'utilisateur est enregistré
```

**POST /chatbot/proposals/:proposalId/confirm**  *(V1.2)*
```
→ (rien)
← 200 { trip: <même forme que GET /trips/:id, voir ../travel/schemas.md> }
```

**POST /chatbot/proposals/:proposalId/reject**  *(V1.2)*
```
→ (rien)
← 204
```

Forme de `proposal` *(V1.2)* :
```
{
  proposalId: string, tripId: string,
  changes: [{ action: enum(add|replace|remove), stepId?: string, activityId?: string,
              startTime?: date, endTime?: date }]
}
```

## Historique des conversations

**GET /chatbot/conversations**  `?limit=&cursor=&status=`
```
← 200 {
    conversations: [{ id: string, title: string?, tripId: string?, status: enum(active|archived),
                      messageCount: number, lastMessageAt: date }],
    nextCursor: string?
  }
```

**GET /chatbot/conversations/:id**
```
← 200 { id, title, tripId, status, messageCount, lastMessageAt, createdAt }
```

**GET /chatbot/conversations/:id/messages**  `?limit=&cursor=`
```
← 200 { messages: [{ id: string, role: enum(user|assistant), content: string, createdAt: date }],
        nextCursor: string? }
```
Tri : du plus récent au plus ancien ; `nextCursor` mène aux messages plus anciens.

**DELETE /chatbot/conversations/:id**
```
← 204    // supprime la conversation et tous ses messages
```

## Analytics (B)

**POST /analytics/events**
```
→ { events: [{
      type: enum(recommendation_viewed|recommendation_clicked),
      targetType: enum(destination|activity),
      targetId: string,
      properties?: { position?: number },
      occurredAt: date
    }] }                                                          // 1 à 50 événements
← 202 { accepted: number }
← 422   // type non autorisé (par exemple funnel_step), lot trop grand
```
Le `userId` vient du jeton, jamais du corps. Les événements `funnel_step` ne passent pas par
cette route : le backend les enregistre lui-même.

---

## Construction du contexte et résumé  *(Proposé, sauf le seuil de 10 échanges : Doc)*

Pour chaque réponse, le contexte envoyé au modèle est : le `summary` s'il existe, puis les
messages après `summarizedUpTo` (au plus les 10 derniers échanges), le code de profil de
l'utilisateur (jamais le vecteur brut, *Doc*) et l'itinéraire lié. Quand plus de 10 échanges
ne sont pas résumés, une tâche en arrière-plan produit un nouveau `summary` et fait avancer
`summarizedUpTo`. Les messages d'origine restent stockés.

## Règles de stockage  *(Proposé)*

- Le message de l'utilisateur est écrit avant l'appel au modèle, la réponse après. La mise à
  jour de `messageCount` et `lastMessageAt` accompagne l'ajout du message.
- Suppression réelle (pas de suppression logique) par `conversationId` ou `userId`.
- Chiffrement au repos pour `content` et `summary`.

---

## Points résolus et points encore ouverts

| Sujet | Position | Statut |
|---|---|---|
| Titre d'une conversation | Premiers mots du premier message | Décidé |
| Échec du modèle | Garder le message, répondre `503` | Décidé |
| Émetteur des analytics | Mixte : front pour vu/cliqué, backend pour les étapes | Décidé |
| Types d'événements | `recommendation_viewed`, `recommendation_clicked`, `funnel_step` | Décidé |
| Streaming de la réponse | Hors MVP ; réponse complète en une fois | Proposé |
| Préférences extraites des conversations | Hors MVP (on ne sait pas qui les extrait) | Proposé |
| Intentions des messages (`intent`) | Hors MVP (seulement si le modèle les fournit) | Proposé |
| Conservation des événements analytics | 90 jours (index TTL) | Proposé |
| Conservation des conversations | Jusqu'à suppression par l'utilisateur ou du compte ; durée maximale d'inactivité **à fixer avec la personne en charge du RGPD** | **Ouvert** |
| Limites chiffrées | 2000 caractères par message, 2 Ko de `properties`, 50 événements par lot | Proposé |
| Limite de requêtes du chatbot | Valeurs à décider | **Ouvert** |