# Flux principal : génération d'un itinéraire

Flux de génération d'un itinéraire, de la demande à la validation. Microservice concerné :
**Assistant**, avec Travel et Identity en appui et le service IA de l'équipe IA en externe.
La requête est asynchrone : `POST /trips/generate` répond `202` avec un identifiant de
tâche, le front lit ensuite le résultat.

```
┌──────────────────────┐
│ Front vibngo         │  POST /trips/generate (formulaire de besoins)
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ API Gateway          │  JWT vérifié · rate limit
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ Assistant            │  répond 202 { jobId } · traitement en tâche de fond
│ Itinerary_generation │
└──────────┬───────────┘
           ▼
     ┌───────────┐   Oui   ┌──────────────────────────┐
     │ Cache ?   │────────▶│ Proposition du cache     │──────────┐
     └─────┬─────┘         │ (nouveau proposalId      │          │
           │ Non           │  pour cet utilisateur)   │          │
           ▼               └──────────────────────────┘          │
┌──────────────────────┐                                         │
│ Identity             │  profil voyageur (scores + code)        │
└──────────┬───────────┘                                         │
           ▼                                                     │
┌──────────────────────┐                                         │
│ Recommendation       │──▶ Service IA : classement destinations │
│                      │──▶ Travel/Catalog : fiches et activités │
└──────────┬───────────┘                                         │
           ▼                                                     │
┌──────────────────────┐                                         │
│ LLM (Ollama)         │  choisit les activités (JSON structuré) │
└──────────┬───────────┘                                         │
           ▼                                                     │
┌──────────────────────┐                                         │
│ Google Maps          │  distances et trajets                   │
└──────────┬───────────┘                                         │
           ▼                                                     │
┌──────────────────────┐                                         │
│ LLM (Ollama)         │  organise le planning                   │
└──────────┬───────────┘                                         │
           ▼                                                     │
┌──────────────────────┐                                         │
│ Validation par code  │  pas de chevauchement, horaires,        │
│                      │  trajets réalistes, budget              │
└──────────┬───────────┘                                         │
           ▼                                                     │
┌──────────────────────┐                                         │
│ Proposition          │  stockée dans Redis (durée limitée)     │
│ (proposalId)         │◀────────────────────────────────────────┘
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ Front vibngo         │  GET /trips/generate/:jobId → proposition prête
└──────────┬───────────┘
           ▼
   Utilisateur valide ?
      ┌────┴─────┐
     Oui         Non
      │           │
      ▼           ▼
┌───────────┐  POST .../regenerate (feedback optionnel)
│ Travel    │  → nouvelle tâche, retour à « Cache ? »
│ trip créé │
│ (confirm) │
└───────────┘
```

## Règles de ce flux

- **Rien n'est écrit dans Travel avant `confirm`.** La proposition vit dans Redis, avec une
  durée de vie limitée.
- **Clé de cache** : profil + contraintes + `modelVersion`. Même sur un cache trouvé, chaque
  utilisateur reçoit **son propre `proposalId`**, sinon `confirm` ne peut pas fonctionner.
- **Appels externes protégés** : timeout, réessais limités, circuit breaker (`AiClient`,
  `LlmClient`, `RoutingProvider`).
- **Si le service IA est indisponible** : classement en cache, sinon destinations populaires.
- **Si la validation par code échoue** : une nouvelle tentative est lancée un nombre limité
  de fois ; sinon la tâche passe en `failed` avec une erreur explicite.
- **Confirmation idempotente** (`Idempotency-Key`) : un réessai ne crée pas deux itinéraires.
- **RGPD** : le LLM ne reçoit qu'un code de profil et les contraintes, jamais nom, email ni
  vecteur brut ; Google Maps ne reçoit que des lieux, jamais d'identifiant d'utilisateur.