// Configuration Prisma 7 du schéma identity.
// DATABASE_URL : URL du rôle triply_identity (directe, sans -pooler) avec ?schema=identity.
// En dev elle vient de IDENTITY_DATABASE_URL_DIRECT dans .env (voir doc/infra/bases-de-donnees.md).
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
