// Configuration Prisma 7 du schéma travel.
// DATABASE_URL : URL du rôle triply_travel (directe, sans -pooler) avec ?schema=travel.
// En dev elle vient de TRAVEL_DATABASE_URL_DIRECT dans .env (voir doc/infra/bases-de-donnees.md).
import { defineConfig, env } from 'prisma/config';

export default defineConfig({
  schema: './schema.prisma',
  migrations: {
    path: './migrations',
  },
  datasource: {
    url: env('DATABASE_URL'),
  },
});
