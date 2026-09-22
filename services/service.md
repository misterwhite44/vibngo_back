# Services — documentation

Ce que fait chaque service listé dans `pg-liste.md`, `redis-liste.md`, `mongo-liste.md`
et `redis-liste.md`. Un service = une classe injectable NestJS portant une responsabilité
métier précise.

## PostgreSQL (`pg-liste.md`)

**Authentification**
Inscription, connexion, hash du mot de passe, émission/vérification des JWT (access +
refresh). S'appuie sur `Session` (Redis) pour la révocation.

**User**
Compte utilisateur, profil voyageur et questionnaire de personnalité : lecture/mise à
jour du compte, réponses au questionnaire, calcul du profil dominant. Déclenche la mise
à jour du vecteur profil (`Profile_vector`, Qdrant) à chaque changement.

**Settings**
Paramètres de confidentialité et de notifications (géolocalisation, visibilité
communautaire, mode hors-ligne).

**Notification (Bonus)**
Envoi des notifications push (rappels, alertes). Empile les envois différés dans `Queue`
(Redis) plutôt que d'envoyer en synchrone.

**Catalog**
Contenu consultable : destinations, activités, hébergements, partenaires, fiches et
photos. Sert les pages Destination/Activité du front et fournit les candidats à
`Itinerary_generation`. N'a jamais de logique de génération — uniquement de la lecture/
gestion de contenu.

**Itinerary_generation**
Orchestre la génération d'un itinéraire à partir du formulaire de besoins : vérifie
`Cache` (Redis), sinon lit les candidats via `Catalog`, appelle `Recommendation` (Qdrant),
le LLM local (Ollama) pour interpréter le besoin et organiser le planning, et l'API
Google Maps pour les distances/trajets (voir `flux/principal.md`). Produit une
*proposition* — ne persiste rien lui-même. Ne transmet le résultat à `Travel` que si
l'utilisateur valide.

**Travel**
Persistance et édition d'un itinéraire une fois confirmé : jours, étapes, transport,
réservations. Reçoit sa première version d'`Itinerary_generation` après validation ;
gère ensuite les modifications manuelles (remplacer/supprimer une étape) et celles
proposées par `Chatbot`.

**Travel_history**
Itinéraires terminés et carnet de voyage associé (photos, notes, export).

**Favorites**
Sauvegarde de destinations, activités ou villes en favori ("favori" ou "envisagée"),
consultable depuis le profil utilisateur.

**Commentary**
Avis et commentaires sur les activités/destinations (notes, texte, modération basique).

## MongoDB (`mongo-liste.md`)
**Chatbot**
Gère un échange en cours avec l'utilisateur : construit le contexte (RAG), appelle le LLM
local, retourne la réponse et, si demandé, une proposition de modification d'itinéraire.
Si l'utilisateur valide la modification, transmet la mise à jour à `Travel` (jamais
d'écriture directe sans validation — même principe que `Itinerary_generation`).

**Chatbot_history**
Stocke et relit l'historique des conversations ; compresse en résumé au-delà de 10
échanges pour garder un contexte léger.

**Analytics (Bonus)**
Journalise les événements d'interaction (clics sur une recommandation, étapes du
parcours) de façon asynchrone, pour mesurer le taux de clic et la pertinence du moteur de
reco sans jamais ralentir la réponse à l'utilisateur.

## Redis (`redis-liste.md`)

**Cache**
Cache du résultat d'une génération IA et des fiches destination/activité, pour éviter de
recalculer/relire à chaque requête identique.

**Session**
Sessions actives et révocation immédiate des JWT (déconnexion, compte compromis).

**Queue**
Files d'attente (BullMQ) pour les traitements asynchrones : notifications, export du
carnet de voyage, ingestion de données externes.

**Rate_limit (Bonus)**
Limite le nombre de requêtes par utilisateur et par route, pour éviter les abus.
