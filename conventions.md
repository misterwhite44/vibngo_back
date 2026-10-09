# API — conventions communes

Valables pour les endpoints de `identity/`, `travel/` et `assistant/`.

- **Base** : `/api/v1`. Toutes les routes sont relatives à cette base
  (ex : `POST /trips/generate` = `POST /api/v1/trips/generate`).
- **Auth** : header `Authorization: Bearer <access_token>` sur toutes les routes sauf
  `POST /auth/register`, `/auth/login`, `/auth/refresh`, `/auth/oauth/:provider`,
  `/auth/password/forgot` et `/auth/password/reset`. La gateway vérifie le JWT et transmet
  l'identité aux microservices.
- **Routes internes** : les routes `/internal/...` sont réservées aux appels entre
  microservices (réseau privé, jeton de service). La gateway ne les expose jamais.
- **Format** : JSON. Dates en ISO 8601. Les listes sont enveloppées dans un objet nommé
  (`{ trips: [...] }`), jamais un tableau nu.
- **Erreurs** : format `application/problem+json`
  `{ type, title, status, detail, code, retryable, correlationId }`.
  - `401` non authentifié · `403` non autorisé · `404` introuvable (aussi pour la ressource
    d'un autre utilisateur, pour ne pas révéler son existence) · `422` validation
  - `429` limite de requêtes · `503` dépendance indisponible · `504` délai dépassé
- **Pagination** : `?limit=` (défaut 20, max 100) et `?cursor=` ; la réponse contient
  `nextCursor` s'il y a une suite.
- **Idempotence** : les `POST` rejouables (questionnaire, confirmation, message du chatbot,
  génération) acceptent `Idempotency-Key`. Un réessai avec la même clé ne crée pas de doublon.
- **Corrélation** : chaque requête porte un `correlationId` (header `X-Correlation-Id`),
  renvoyé dans les erreurs.
- **Pattern proposition/validation** (voir `../flux/principal.md`) : `/trips/generate` et le
  chatbot renvoient des *propositions* non persistées. Rien n'est écrit tant qu'un endpoint
  `.../confirm` n'a pas été appelé par l'utilisateur.
- **Légende des phases** : MVP, V1.1, V1.2, V2.0 (roadmap), B = Bonus, ? = à confirmer.
  Les endpoints hors MVP sont documentés pour figer le contrat, mais non livrés au MVP.