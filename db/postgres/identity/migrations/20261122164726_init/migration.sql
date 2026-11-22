-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "email" TEXT NOT NULL,
    "password_hash" TEXT NOT NULL,
    "phone" TEXT,
    "status" TEXT NOT NULL DEFAULT 'active',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(6),

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "traveler_types" (
    "code" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "description" TEXT,
    "is_active" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "traveler_types_pkey" PRIMARY KEY ("code")
);

-- CreateTable
CREATE TABLE "profile_axes" (
    "code" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "position" SMALLINT NOT NULL,

    CONSTRAINT "profile_axes_pkey" PRIMARY KEY ("code")
);

-- CreateTable
CREATE TABLE "questionnaire_questions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "code" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "axis_code" TEXT NOT NULL,
    "position" SMALLINT NOT NULL,
    "weight" DECIMAL(4,2) NOT NULL DEFAULT 1,
    "reverse_scored" BOOLEAN NOT NULL DEFAULT false,
    "is_active" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "questionnaire_questions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "questionnaire_answers" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "question_id" UUID NOT NULL,
    "value" SMALLINT NOT NULL,
    "answered_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "questionnaire_answers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "traveler_profiles" (
    "user_id" UUID NOT NULL,
    "dominant_type_code" TEXT NOT NULL,
    "computed_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "traveler_profiles_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "traveler_profile_scores" (
    "user_id" UUID NOT NULL,
    "axis_code" TEXT NOT NULL,
    "score" DECIMAL(5,2) NOT NULL,

    CONSTRAINT "traveler_profile_scores_pkey" PRIMARY KEY ("user_id","axis_code")
);

-- CreateTable
CREATE TABLE "settings" (
    "user_id" UUID NOT NULL,
    "notifications_enabled" BOOLEAN NOT NULL DEFAULT true,
    "geolocation_enabled" BOOLEAN NOT NULL DEFAULT false,
    "community_visible" BOOLEAN NOT NULL DEFAULT true,
    "privacy_level" TEXT NOT NULL DEFAULT 'standard',
    "offline_mode_enabled" BOOLEAN NOT NULL DEFAULT false,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "settings_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "notifications" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "payload" JSONB,
    "scheduled_at" TIMESTAMPTZ(6),
    "sent_at" TIMESTAMPTZ(6),
    "read_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notifications_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "profile_axes_position_key" ON "profile_axes"("position");

-- CreateIndex
CREATE UNIQUE INDEX "questionnaire_questions_code_key" ON "questionnaire_questions"("code");

-- CreateIndex
CREATE UNIQUE INDEX "questionnaire_questions_position_key" ON "questionnaire_questions"("position");

-- CreateIndex
CREATE UNIQUE INDEX "questionnaire_answers_user_question_key" ON "questionnaire_answers"("user_id", "question_id");

-- CreateIndex
CREATE INDEX "notifications_user_created_idx" ON "notifications"("user_id", "created_at" DESC);

-- AddForeignKey
ALTER TABLE "questionnaire_questions" ADD CONSTRAINT "questionnaire_questions_axis_code_fkey" FOREIGN KEY ("axis_code") REFERENCES "profile_axes"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "questionnaire_answers" ADD CONSTRAINT "questionnaire_answers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "questionnaire_answers" ADD CONSTRAINT "questionnaire_answers_question_id_fkey" FOREIGN KEY ("question_id") REFERENCES "questionnaire_questions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "traveler_profiles" ADD CONSTRAINT "traveler_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "traveler_profiles" ADD CONSTRAINT "traveler_profiles_dominant_type_code_fkey" FOREIGN KEY ("dominant_type_code") REFERENCES "traveler_types"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "traveler_profile_scores" ADD CONSTRAINT "traveler_profile_scores_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "traveler_profiles"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "traveler_profile_scores" ADD CONSTRAINT "traveler_profile_scores_axis_code_fkey" FOREIGN KEY ("axis_code") REFERENCES "profile_axes"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "settings" ADD CONSTRAINT "settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- ===========================================================================
-- Écrit à la main : ce que Prisma ne sait pas déclarer (doc/api/postgres/mcd-mld.md)
-- ===========================================================================

-- Unicité de l'email insensible à la casse
CREATE UNIQUE INDEX "users_email_key" ON "users" (lower("email"));

ALTER TABLE "users"
  ADD CONSTRAINT "users_status_chk" CHECK ("status" IN ('active', 'suspended', 'deleted'));

ALTER TABLE "questionnaire_answers"
  ADD CONSTRAINT "questionnaire_answers_value_chk" CHECK ("value" BETWEEN 1 AND 5);

ALTER TABLE "traveler_profile_scores"
  ADD CONSTRAINT "traveler_profile_scores_score_chk" CHECK ("score" BETWEEN 0 AND 100);

ALTER TABLE "settings"
  ADD CONSTRAINT "settings_privacy_level_chk" CHECK ("privacy_level" IN ('standard', 'strict'));
