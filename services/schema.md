# Schéma des services

Vue d'ensemble des services listés dans `pg-liste.md`, `mongo-liste.md` et
`redis-liste.md`, dans le même style que `flux/principal.md` (détail de chaque service
dans `service.md`).

```
                            ┌─────────────┐
                            │ Backend API │
                            └─────────────┘
                                   │
            ┬──────────────────────┴──────────────────────┬
            │                      │                      │
            ▼                      ▼                      ▼
┌──────────────────────┬──────────────────────┬──────────────────────┐
│      PostgreSQL      │       MongoDB        │        Redis         │
├──────────────────────┼──────────────────────┼──────────────────────┤
│Authentification      │Chatbot               │Cache                 │
│User                  │Chatbot_history       │Session               │
│User_type             │Analytics (B)         │Queue                 │
│Settings              │                      │Rate_limit (B)        │
│Notification (B)      │                      │                      │
│Catalog               │                      │                      │
│Itinerary_generation  │                      │                      │
│Travel                │                      │                      │
│Travel_history        │                      │                      │
│Favorites             │                      │                      │
│Commentary            │                      │                      │
└──────────────────────┴──────────────────────┴──────────────────────┘

Appels clés entre services :

Auth                  ──▶  Session           révocation JWT (déconnexion, compte compromis)
User                  ──▶  User_type         calcule le profil dominant à partir des réponses au questionnaire
Itinerary_generation  ──▶  Cache             vérifie le résultat en cache avant tout calcul
Itinerary_generation  ──▶  Catalog           lit les destinations/activités candidates
Itinerary_generation  ──▶  Travel            persiste la proposition SI l'utilisateur valide
Notification (B)      ──▶  Queue             envoi différé via BullMQ
Chatbot               ──▶  Chatbot_history   lecture / écriture de l'historique de conversation
Chatbot               ──▶  Cache             réponse déjà générée ?
Chatbot               ──▶  Travel            met à jour une étape SI l'utilisateur valide
Chatbot               ──▶  Analytics (B)     log asynchrone, sans bloquer la réponse
```

Pas de base vectorielle : `Itinerary_generation` transmet directement les candidats lus
via `Catalog` au LLM local (Ollama), qui choisit et organise l'itinéraire lui-même — pas
de scoring par similarité, pas de service dédié à la recommandation.
