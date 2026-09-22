  ┌─────────────────┐
                    │    Frontend     │
                    │     Triply      │
                    └────────┬────────┘
                             │
                             │ Requête utilisateur
                             ▼
                    ┌─────────────────┐
                    │     Backend     │
                    │      API        │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │      Redis      │
                    │     Cache IA    │
                    └────────┬────────┘
                             │
                       Cache trouvé ?
                       /          \
                     Oui           Non
                      │             │
                      │             ▼
                      │       ┌─────────────┐
                      │       │     LLM     │
                      │       │ Génération  │
                      │       │  du besoin  │
                      │       └──────┬──────┘
                      │              │
                      │              ▼
                      │       ┌─────────────┐
                      │       │   Backend   │
                      │       │ Traitement  │
                      │       │  requête    │
                      │       └──────┬──────┘
                      │              │
                      │              ▼
                      │       ┌─────────────┐
                      │       │ Google Maps │
                      │       │     API     │
                      │       └──────┬──────┘
                      │              │
                      │              ▼
                      │       ┌─────────────┐
                      │       │   Backend   │
                      │       │ Traitement  │
                      │       │   données   │
                      │       └──────┬──────┘
                      │              │
                      │              ▼
                      │       ┌─────────────┐
                      │       │     LLM     │
                      │       │ Organisation│
                      │       │  itinéraire │
                      │       └──────┬──────┘
                      │              │
                      │              ▼
                      │       ┌──────────────────┐
                      │       │ Proposition      │
                      │       │     voyage       │
                      │       └────────┬─────────┘
                      │                │
                      │                ▼
                      │       ┌──────────────────┐
                      │       │    Frontend      │
                      │       │     Triply       │
                      │       └────────┬─────────┘
                      │                │
                      │        Utilisateur valide ?
                      │                │
                      │           ┌────┴────┐
                      │           │         │
                      │          Oui       Non
                      │           │         │
                      │           ▼         │
                      │     ┌───────────┐   │
                      │     │PostgreSQL │   │
                      │     │  Business │   │
                      │     └─────┬─────┘   │
                      │           │         │
                      │           ▼         │
                      │          Fin        │
                      │                     │
                      │                     │
                      │                     └──────────────┐
                      │                                    │
                      │                                    ▼
                      │                              ┌─────────────┐
                      │                              │   Backend   │
                      │                              │ Nouvelle    │
                      │                              │ proposition │
                      │                              └──────┬──────┘
                      │                                     │
                      │                                     ▼
                      │                                    LLM
                      │                                     │
                      │                                     ▼
                      │                              Nouvel itinéraire
                      │                                     │
                      │                                     └───────────┐
                      │                                                 │
                      ▼                                                 │
                Résultat du cache                                       │
                      │                                                 │
                      ▼                                                 │
               ┌─────────────────┐                                      │
               │    Frontend     │◄─────────────────────────────────────┘
               │     Triply      │
               └─────────────────┘





