-- Création des rôles et schémas PostgreSQL de Triply (doc/api/postgres/orm.md).
--
-- Un schéma et un rôle par microservice ayant des données PostgreSQL :
--   schéma identity <- rôle triply_identity
--   schéma travel   <- rôle triply_travel
--
-- Le même fichier sert en dev (lancé par infra/postgres/dev-init.sh au premier démarrage
-- du conteneur) et en prod (lancé une fois sur Neon par docker-compose.prod-tools.yml).
-- Il est rejouable : relancé, il ne recrée rien et remet seulement les mots de passe à jour.
--
-- Variables psql obligatoires : identity_password, travel_password.

\set ON_ERROR_STOP on

\if :{?identity_password}
\else
  \echo 'Variable identity_password manquante (psql -v identity_password=...)'
  \quit 1
\endif
\if :{?travel_password}
\else
  \echo 'Variable travel_password manquante (psql -v travel_password=...)'
  \quit 1
\endif

-- Rôles applicatifs (connexion seulement, aucun privilège global)
SELECT 'CREATE ROLE triply_identity LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'triply_identity') \gexec
SELECT 'CREATE ROLE triply_travel LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'triply_travel') \gexec

ALTER ROLE triply_identity WITH LOGIN PASSWORD :'identity_password';
ALTER ROLE triply_travel   WITH LOGIN PASSWORD :'travel_password';

-- Personne ne crée d'objet dans public
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- Un schéma par microservice. Le schéma appartient au rôle qui lance ce script ; le rôle
-- du service reçoit USAGE + CREATE, ce qui suffit à Prisma (tables et _prisma_migrations
-- créées dans son schéma, dont il devient propriétaire). Pas de membre de rôle à gérer :
-- fonctionne aussi bien avec le superuser local qu'avec le rôle propriétaire de Neon.
CREATE SCHEMA IF NOT EXISTS identity;
CREATE SCHEMA IF NOT EXISTS travel;

REVOKE ALL ON SCHEMA identity FROM PUBLIC;
REVOKE ALL ON SCHEMA travel   FROM PUBLIC;

GRANT USAGE, CREATE ON SCHEMA identity TO triply_identity;
GRANT USAGE, CREATE ON SCHEMA travel   TO triply_travel;

-- Chaque service ne voit que son schéma par défaut. Aucun GRANT croisé :
-- triply_travel n'a aucun USAGE sur identity, et inversement.
ALTER ROLE triply_identity SET search_path = identity;
ALTER ROLE triply_travel   SET search_path = travel;

\echo 'Rôles et schémas identity / travel prêts.'
