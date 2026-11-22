-- Test des contraintes du schéma identity. Tout est annulé (ROLLBACK) : aucune trace en base.
-- psql "<url triply_identity>" -v ON_ERROR_STOP=1 -f db/postgres/tests/identity.sql
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path = identity;

CREATE PROCEDURE pg_temp.expect_error(stmt text, label text) AS $$
BEGIN
  BEGIN
    EXECUTE stmt;
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'ok  : %', label;
    RETURN;
  END;
  RAISE EXCEPTION 'ÉCHEC : % (accepté alors qu''il devait être refusé)', label;
END $$ LANGUAGE plpgsql;

INSERT INTO profile_axes (code, label, position) VALUES ('urbanite', 'Urbanité', 1);
INSERT INTO traveler_types (code, label) VALUES ('explorateur', 'Explorateur');
INSERT INTO users (id, email, password_hash) VALUES ('11111111-1111-4111-8111-111111111111', 'Jean@triply.fr', 'x');
INSERT INTO settings (user_id) VALUES ('11111111-1111-4111-8111-111111111111');
INSERT INTO questionnaire_questions (id, code, label, axis_code, position)
  VALUES ('22222222-2222-4222-8222-222222222222', 'q1', 'Ville ou nature ?', 'urbanite', 1);
INSERT INTO questionnaire_answers (user_id, question_id, value)
  VALUES ('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 4);
INSERT INTO traveler_profiles (user_id, dominant_type_code) VALUES ('11111111-1111-4111-8111-111111111111', 'explorateur');
INSERT INTO traveler_profile_scores (user_id, axis_code, score) VALUES ('11111111-1111-4111-8111-111111111111', 'urbanite', 72.5);

CALL pg_temp.expect_error($$INSERT INTO users (email, password_hash) VALUES ('jean@TRIPLY.fr', 'x')$$, 'email unique sans tenir compte de la casse');
CALL pg_temp.expect_error($$INSERT INTO users (email, password_hash, status) VALUES ('a@b.c', 'x', 'banned')$$, 'statut utilisateur hors liste');
CALL pg_temp.expect_error($$INSERT INTO questionnaire_answers (user_id, question_id, value) VALUES ('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 3)$$, 'une seule réponse par question');
CALL pg_temp.expect_error($$UPDATE questionnaire_answers SET value = 6$$, 'réponse entre 1 et 5');
CALL pg_temp.expect_error($$UPDATE traveler_profile_scores SET score = 101$$, 'score entre 0 et 100');
CALL pg_temp.expect_error($$UPDATE settings SET privacy_level = 'open'$$, 'niveau de confidentialité hors liste');
CALL pg_temp.expect_error($$DELETE FROM traveler_types WHERE code = 'explorateur'$$, 'type voyageur utilisé : suppression refusée');
CALL pg_temp.expect_error($$INSERT INTO traveler_profiles (user_id, dominant_type_code) VALUES ('11111111-1111-4111-8111-111111111111', 'explorateur')$$, 'un profil au plus par utilisateur');

DELETE FROM users WHERE id = '11111111-1111-4111-8111-111111111111';
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM settings) OR EXISTS (SELECT 1 FROM questionnaire_answers)
     OR EXISTS (SELECT 1 FROM traveler_profile_scores) THEN
    RAISE EXCEPTION 'ÉCHEC : la suppression du compte ne supprime pas ses données';
  END IF;
  RAISE NOTICE 'ok  : suppression du compte en cascade';
END $$;

ROLLBACK;
\echo 'identity : toutes les contraintes testées sont respectées.'
