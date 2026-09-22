# Triply — Back

Backend de Triply, planificateur de voyage intelligent. Ce dépôt est actuellement au
stade conception/architecture (liste des services, schéma, flux) — le code applicatif
(NestJS) reste à démarrer.

## Où trouver quoi

| Dossier | Contenu |
|---|---|
| [`documentation/`](documentation/) | Docs produit/business d'origine (fonctionnalités, MVP, MoSCoW, choix technos, IA, RGPD...) |
| [`services/`](services/) | Liste des services par base (`pg-liste.md`, `mongo-liste.md`, `redis-liste.md`), leur description (`service.md`) et un schéma d'ensemble (`schema.md`) |
| [`flux/`](flux/) | Flux principal de l'application (`principal.md`) |

## Architecture de persistance

3 bases, chacune avec un rôle précis (détail dans `services/service.md`) :

- **PostgreSQL** — source de vérité métier : comptes, profils, catalogue de contenu,
  itinéraires, favoris, avis.
- **MongoDB** — conversations du chatbot et logs d'interaction, volumineux et
  schéma-flexible.
- **Redis** — cache du résultat IA et des fiches, sessions, files d'attente (BullMQ).

Pas de base vectorielle : la génération d'itinéraire (`Itinerary_generation`) transmet
directement les candidats du catalogue au LLM, qui choisit et organise lui-même — voir
`services/schema.md`.

## Le flux principal

`flux/principal.md` détaille le parcours de bout en bout : la requête utilisateur passe
par le cache Redis avant d'appeler le LLM (génération du besoin, appel Google Maps,
organisation de l'itinéraire) ; la proposition n'est écrite en base que si l'utilisateur
valide, sinon le cycle recommence sur une nouvelle proposition.

## Stack retenue (voir `documentation/` pour le détail des arbitrages)

Backend NestJS (monolithe modulaire), Expo (React Native) côté front, LLM local via Ollama
pour la génération d'itinéraire et le chatbot RAG.
