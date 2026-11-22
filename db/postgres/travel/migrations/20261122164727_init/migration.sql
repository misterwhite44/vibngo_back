-- CreateTable
CREATE TABLE "countries" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "code" CHAR(2) NOT NULL,
    "name" TEXT NOT NULL,

    CONSTRAINT "countries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cities" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "country_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "latitude" DECIMAL(9,6),
    "longitude" DECIMAL(9,6),
    "timezone" TEXT,

    CONSTRAINT "cities_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "destinations" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "city_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "cover_image_url" TEXT,
    "popularity_score" DECIMAL(5,2) NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "destinations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "activity_categories" (
    "code" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "is_accommodation" BOOLEAN NOT NULL DEFAULT false,
    "is_active" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "activity_categories_pkey" PRIMARY KEY ("code")
);

-- CreateTable
CREATE TABLE "partners" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" TEXT NOT NULL,
    "contact_email" TEXT,
    "contact_phone" TEXT,
    "website" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "partners_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "activities" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "destination_id" UUID NOT NULL,
    "category_code" TEXT NOT NULL,
    "partner_id" UUID,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "address" TEXT,
    "latitude" DECIMAL(9,6),
    "longitude" DECIMAL(9,6),
    "price_range" TEXT,
    "opening_hours" JSONB,
    "contact_phone" TEXT,
    "contact_website" TEXT,
    "booking_url" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "activities_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "activity_media" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "activity_id" UUID NOT NULL,
    "url" TEXT NOT NULL,
    "origin" TEXT NOT NULL,
    "user_id" UUID,
    "position" SMALLINT NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "activity_media_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "activity_recommended_profiles" (
    "activity_id" UUID NOT NULL,
    "traveler_type_code" TEXT NOT NULL,

    CONSTRAINT "activity_recommended_profiles_pkey" PRIMARY KEY ("activity_id","traveler_type_code")
);

-- CreateTable
CREATE TABLE "trips" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "title" TEXT,
    "status" TEXT NOT NULL DEFAULT 'generated',
    "start_date" DATE NOT NULL,
    "end_date" DATE NOT NULL,
    "budget" DECIMAL(10,2),
    "transport_mode" TEXT,
    "origin_city_id" UUID,
    "destination_city_id" UUID NOT NULL,
    "proposal_id" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trips_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_travelers" (
    "trip_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'guest',
    "joined_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_travelers_pkey" PRIMARY KEY ("trip_id","user_id")
);

-- CreateTable
CREATE TABLE "trip_days" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "trip_id" UUID NOT NULL,
    "day_index" SMALLINT NOT NULL,
    "date" DATE NOT NULL,

    CONSTRAINT "trip_days_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_steps" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "trip_day_id" UUID NOT NULL,
    "sequence" SMALLINT NOT NULL,
    "type" TEXT NOT NULL,
    "activity_id" UUID,
    "start_time" TIMESTAMPTZ(6),
    "end_time" TIMESTAMPTZ(6),
    "status" TEXT NOT NULL DEFAULT 'planned',
    "notes" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_steps_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_transports" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "trip_id" UUID NOT NULL,
    "trip_step_id" UUID,
    "leg" TEXT NOT NULL,
    "mode" TEXT NOT NULL,
    "from_city_id" UUID,
    "to_city_id" UUID,
    "departs_at" TIMESTAMPTZ(6),
    "arrives_at" TIMESTAMPTZ(6),
    "distance_km" DECIMAL(8,2),
    "duration_min" INTEGER,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_transports_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "bookings" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "trip_id" UUID NOT NULL,
    "trip_step_id" UUID,
    "category" TEXT NOT NULL,
    "provider" TEXT,
    "reference_code" TEXT,
    "booking_url" TEXT,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "reminder_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "bookings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "journal_entries" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "trip_id" UUID NOT NULL,
    "trip_day_id" UUID,
    "trip_step_id" UUID,
    "user_id" UUID NOT NULL,
    "text" TEXT,
    "summary_word" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "journal_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "journal_photos" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "journal_entry_id" UUID NOT NULL,
    "url" TEXT NOT NULL,
    "position" SMALLINT NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "journal_photos_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "journal_exports" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "trip_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "pdf_url" TEXT,
    "job_id" TEXT,
    "requested_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completed_at" TIMESTAMPTZ(6),

    CONSTRAINT "journal_exports_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "favorites" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "target_type" TEXT NOT NULL,
    "target_id" UUID NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'favorite',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "favorites_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "reviews" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "activity_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "rating" SMALLINT NOT NULL,
    "comment" TEXT,
    "status" TEXT NOT NULL DEFAULT 'published',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "reviews_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "countries_code_key" ON "countries"("code");

-- CreateIndex
CREATE UNIQUE INDEX "cities_country_name_key" ON "cities"("country_id", "name");

-- CreateIndex
CREATE INDEX "destinations_city_idx" ON "destinations"("city_id");

-- CreateIndex
CREATE UNIQUE INDEX "destinations_city_name_key" ON "destinations"("city_id", "name");

-- CreateIndex
CREATE INDEX "activities_destination_idx" ON "activities"("destination_id");

-- CreateIndex
CREATE INDEX "activities_category_idx" ON "activities"("category_code");

-- CreateIndex
CREATE INDEX "trips_user_status_idx" ON "trips"("user_id", "status");

-- CreateIndex
CREATE INDEX "trips_user_start_idx" ON "trips"("user_id", "start_date" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "trip_days_trip_index_key" ON "trip_days"("trip_id", "day_index");

-- CreateIndex
CREATE UNIQUE INDEX "trip_days_trip_date_key" ON "trip_days"("trip_id", "date");

-- CreateIndex
CREATE INDEX "trip_steps_day_idx" ON "trip_steps"("trip_day_id", "sequence");

-- CreateIndex
CREATE INDEX "trip_steps_activity_idx" ON "trip_steps"("activity_id");

-- CreateIndex
CREATE INDEX "trip_transports_trip_idx" ON "trip_transports"("trip_id");

-- CreateIndex
CREATE INDEX "journal_entries_trip_idx" ON "journal_entries"("trip_id", "created_at");

-- CreateIndex
CREATE INDEX "favorites_user_created_idx" ON "favorites"("user_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "favorites_target_idx" ON "favorites"("target_type", "target_id");

-- CreateIndex
CREATE UNIQUE INDEX "favorites_user_target_key" ON "favorites"("user_id", "target_type", "target_id");

-- CreateIndex
CREATE UNIQUE INDEX "reviews_activity_user_key" ON "reviews"("activity_id", "user_id");

-- AddForeignKey
ALTER TABLE "cities" ADD CONSTRAINT "cities_country_id_fkey" FOREIGN KEY ("country_id") REFERENCES "countries"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "destinations" ADD CONSTRAINT "destinations_city_id_fkey" FOREIGN KEY ("city_id") REFERENCES "cities"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "activities" ADD CONSTRAINT "activities_destination_id_fkey" FOREIGN KEY ("destination_id") REFERENCES "destinations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "activities" ADD CONSTRAINT "activities_category_code_fkey" FOREIGN KEY ("category_code") REFERENCES "activity_categories"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "activities" ADD CONSTRAINT "activities_partner_id_fkey" FOREIGN KEY ("partner_id") REFERENCES "partners"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "activity_media" ADD CONSTRAINT "activity_media_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "activities"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "activity_recommended_profiles" ADD CONSTRAINT "activity_recommended_profiles_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "activities"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trips" ADD CONSTRAINT "trips_origin_city_id_fkey" FOREIGN KEY ("origin_city_id") REFERENCES "cities"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trips" ADD CONSTRAINT "trips_destination_city_id_fkey" FOREIGN KEY ("destination_city_id") REFERENCES "cities"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_travelers" ADD CONSTRAINT "trip_travelers_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_days" ADD CONSTRAINT "trip_days_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_steps" ADD CONSTRAINT "trip_steps_trip_day_id_fkey" FOREIGN KEY ("trip_day_id") REFERENCES "trip_days"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_steps" ADD CONSTRAINT "trip_steps_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "activities"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_transports" ADD CONSTRAINT "trip_transports_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_transports" ADD CONSTRAINT "trip_transports_trip_step_id_fkey" FOREIGN KEY ("trip_step_id") REFERENCES "trip_steps"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_transports" ADD CONSTRAINT "trip_transports_from_city_id_fkey" FOREIGN KEY ("from_city_id") REFERENCES "cities"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_transports" ADD CONSTRAINT "trip_transports_to_city_id_fkey" FOREIGN KEY ("to_city_id") REFERENCES "cities"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bookings" ADD CONSTRAINT "bookings_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bookings" ADD CONSTRAINT "bookings_trip_step_id_fkey" FOREIGN KEY ("trip_step_id") REFERENCES "trip_steps"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "journal_entries" ADD CONSTRAINT "journal_entries_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "journal_entries" ADD CONSTRAINT "journal_entries_trip_day_id_fkey" FOREIGN KEY ("trip_day_id") REFERENCES "trip_days"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "journal_entries" ADD CONSTRAINT "journal_entries_trip_step_id_fkey" FOREIGN KEY ("trip_step_id") REFERENCES "trip_steps"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "journal_photos" ADD CONSTRAINT "journal_photos_journal_entry_id_fkey" FOREIGN KEY ("journal_entry_id") REFERENCES "journal_entries"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "journal_exports" ADD CONSTRAINT "journal_exports_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reviews" ADD CONSTRAINT "reviews_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "activities"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- ===========================================================================
-- Écrit à la main : ce que Prisma ne sait pas déclarer (doc/api/postgres/mcd-mld.md)
-- ===========================================================================

-- Recherche partielle sur le nom des destinations (?search=). pg_trgm est une extension
-- « trusted » : déjà créée par infra/postgres/bootstrap.sql dans la base principale, créée
-- ici dans la base fantôme de `prisma migrate dev`.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX "destinations_name_trgm_idx" ON "destinations" USING gin ("name" gin_trgm_ops);

-- Catalogue
ALTER TABLE "cities"
  ADD CONSTRAINT "cities_latitude_chk"  CHECK ("latitude"  BETWEEN -90 AND 90),
  ADD CONSTRAINT "cities_longitude_chk" CHECK ("longitude" BETWEEN -180 AND 180);

ALTER TABLE "destinations"
  ADD CONSTRAINT "destinations_popularity_chk" CHECK ("popularity_score" >= 0);

ALTER TABLE "activities"
  ADD CONSTRAINT "activities_latitude_chk"    CHECK ("latitude"  BETWEEN -90 AND 90),
  ADD CONSTRAINT "activities_longitude_chk"   CHECK ("longitude" BETWEEN -180 AND 180),
  ADD CONSTRAINT "activities_price_range_chk" CHECK ("price_range" IN ('€', '€€', '€€€', '€€€€'));

ALTER TABLE "activity_media"
  ADD CONSTRAINT "activity_media_origin_chk" CHECK ("origin" IN ('official', 'community')),
  ADD CONSTRAINT "activity_media_origin_author_chk" CHECK (("origin" = 'official') = ("user_id" IS NULL));

-- Itinéraires
ALTER TABLE "trips"
  ADD CONSTRAINT "trips_status_chk" CHECK ("status" IN ('draft', 'generated', 'active', 'completed', 'archived')),
  ADD CONSTRAINT "trips_dates_chk" CHECK ("end_date" >= "start_date"),
  ADD CONSTRAINT "trips_budget_chk" CHECK ("budget" >= 0),
  ADD CONSTRAINT "trips_transport_mode_chk" CHECK ("transport_mode" IN ('plane', 'train', 'car', 'bus', 'boat', 'bike', 'walk'));

ALTER TABLE "trip_travelers"
  ADD CONSTRAINT "trip_travelers_role_chk" CHECK ("role" IN ('owner', 'guest'));
-- Un seul propriétaire par voyage
CREATE UNIQUE INDEX "trip_travelers_one_owner_idx" ON "trip_travelers" ("trip_id") WHERE "role" = 'owner';

ALTER TABLE "trip_days"
  ADD CONSTRAINT "trip_days_day_index_chk" CHECK ("day_index" >= 1);

-- Ordre des étapes : unicité vérifiée au COMMIT, pour pouvoir réordonner dans une transaction
ALTER TABLE "trip_steps"
  ADD CONSTRAINT "trip_steps_day_sequence_key" UNIQUE ("trip_day_id", "sequence") DEFERRABLE INITIALLY IMMEDIATE,
  ADD CONSTRAINT "trip_steps_sequence_chk" CHECK ("sequence" >= 1),
  ADD CONSTRAINT "trip_steps_type_chk" CHECK ("type" IN ('activity', 'transport', 'accommodation', 'meal')),
  ADD CONSTRAINT "trip_steps_status_chk" CHECK ("status" IN ('planned', 'confirmed', 'modified', 'skipped')),
  ADD CONSTRAINT "trip_steps_times_chk" CHECK ("start_time" IS NULL OR "end_time" IS NULL OR "end_time" >= "start_time"),
  ADD CONSTRAINT "trip_steps_activity_required_chk" CHECK ("type" <> 'activity' OR "activity_id" IS NOT NULL);

ALTER TABLE "trip_transports"
  ADD CONSTRAINT "trip_transports_leg_chk" CHECK ("leg" IN ('outbound', 'return', 'intra')),
  ADD CONSTRAINT "trip_transports_mode_chk" CHECK ("mode" IN ('plane', 'train', 'car', 'bus', 'boat', 'bike', 'walk')),
  ADD CONSTRAINT "trip_transports_times_chk" CHECK ("departs_at" IS NULL OR "arrives_at" IS NULL OR "arrives_at" >= "departs_at");

ALTER TABLE "bookings"
  ADD CONSTRAINT "bookings_category_chk" CHECK ("category" IN ('flight', 'train', 'accommodation', 'activity')),
  ADD CONSTRAINT "bookings_status_chk" CHECK ("status" IN ('pending', 'confirmed', 'cancelled'));
CREATE UNIQUE INDEX "bookings_trip_reference_key"
  ON "bookings" ("trip_id", "category", "reference_code") WHERE "reference_code" IS NOT NULL;
CREATE INDEX "bookings_reminder_idx"
  ON "bookings" ("reminder_at") WHERE "status" <> 'cancelled' AND "reminder_at" IS NOT NULL;

-- Carnet de voyage
ALTER TABLE "journal_entries"
  ADD CONSTRAINT "journal_entries_summary_word_chk" CHECK (char_length("summary_word") <= 30);

ALTER TABLE "journal_photos"
  ADD CONSTRAINT "journal_photos_entry_position_key" UNIQUE ("journal_entry_id", "position") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "journal_exports"
  ADD CONSTRAINT "journal_exports_status_chk" CHECK ("status" IN ('pending', 'processing', 'done', 'failed')),
  ADD CONSTRAINT "journal_exports_done_url_chk" CHECK ("status" <> 'done' OR "pdf_url" IS NOT NULL);

-- Favoris et avis
ALTER TABLE "favorites"
  ADD CONSTRAINT "favorites_target_type_chk" CHECK ("target_type" IN ('destination', 'activity', 'city')),
  ADD CONSTRAINT "favorites_status_chk" CHECK ("status" IN ('favorite', 'considered'));

ALTER TABLE "reviews"
  ADD CONSTRAINT "reviews_rating_chk" CHECK ("rating" BETWEEN 1 AND 5),
  ADD CONSTRAINT "reviews_status_chk" CHECK ("status" IN ('published', 'hidden', 'reported'));
CREATE INDEX "reviews_activity_published_idx" ON "reviews" ("activity_id") WHERE "status" = 'published';
