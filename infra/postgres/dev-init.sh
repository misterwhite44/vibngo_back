#!/bin/sh
# Lancé une seule fois par l'image postgres, au premier démarrage (volume vide).
# Pour le rejouer : docker compose down -v puis docker compose up -d.
set -e

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v identity_password="$PG_IDENTITY_PASSWORD" \
  -v travel_password="$PG_TRAVEL_PASSWORD" \
  -f /triply/bootstrap.sql

# Dev uniquement : `prisma migrate dev` crée une base fantôme (shadow database) et a
# besoin de CREATEDB. En prod, seul `prisma migrate deploy` tourne : pas de CREATEDB.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
ALTER ROLE triply_identity CREATEDB;
ALTER ROLE triply_travel   CREATEDB;
SQL
