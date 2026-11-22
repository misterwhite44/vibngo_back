-- Test des contraintes du schéma travel. Tout est annulé (ROLLBACK) : aucune trace en base.
-- psql "<url triply_travel>" -v ON_ERROR_STOP=1 -f db/postgres/tests/travel.sql
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path = travel;

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

-- Jeu minimal
INSERT INTO countries (id, code, name) VALUES ('a0000000-0000-4000-8000-000000000001', 'PT', 'Portugal');
INSERT INTO cities (id, country_id, name, latitude, longitude, timezone)
  VALUES ('a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001', 'Lisbonne', 38.7223, -9.1393, 'Europe/Lisbon');
INSERT INTO destinations (id, city_id, name) VALUES ('a0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000002', 'Belém');
INSERT INTO activity_categories (code, label) VALUES ('musee', 'Musée');
INSERT INTO activities (id, destination_id, category_code, name, price_range)
  VALUES ('a0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000003', 'musee', 'Musée des Carrosses', '€€');
INSERT INTO trips (id, user_id, start_date, end_date, destination_city_id)
  VALUES ('b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', '2027-05-01', '2027-05-02', 'a0000000-0000-4000-8000-000000000002');
INSERT INTO trip_travelers (trip_id, user_id, role) VALUES ('b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', 'owner');
INSERT INTO trip_days (id, trip_id, day_index, date) VALUES ('b0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000001', 1, '2027-05-01');
INSERT INTO trip_steps (id, trip_day_id, sequence, type, activity_id) VALUES
  ('b0000000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000002', 1, 'activity', 'a0000000-0000-4000-8000-000000000004'),
  ('b0000000-0000-4000-8000-000000000004', 'b0000000-0000-4000-8000-000000000002', 2, 'meal', NULL);

-- Recherche trigramme
DO $$ BEGIN
  PERFORM 1 FROM destinations WHERE name ILIKE '%lém%';
  IF NOT FOUND THEN RAISE EXCEPTION 'ÉCHEC : recherche partielle'; END IF;
  RAISE NOTICE 'ok  : recherche partielle sur le nom (pg_trgm)';
END $$;

-- Réordonner deux étapes dans une transaction : permis grâce à DEFERRABLE
SET CONSTRAINTS trip_steps_day_sequence_key DEFERRED;
UPDATE trip_steps SET sequence = 2 WHERE id = 'b0000000-0000-4000-8000-000000000003';
UPDATE trip_steps SET sequence = 1 WHERE id = 'b0000000-0000-4000-8000-000000000004';
SET CONSTRAINTS trip_steps_day_sequence_key IMMEDIATE;
DO $$ BEGIN RAISE NOTICE 'ok  : réordonner les étapes (contrainte différée)'; END $$;

CALL pg_temp.expect_error($$INSERT INTO trip_steps (trip_day_id, sequence, type) VALUES ('b0000000-0000-4000-8000-000000000002', 1, 'meal')$$, 'deux étapes au même rang');
CALL pg_temp.expect_error($$INSERT INTO trip_steps (trip_day_id, sequence, type) VALUES ('b0000000-0000-4000-8000-000000000002', 3, 'activity')$$, 'étape activity sans activité');
CALL pg_temp.expect_error($$INSERT INTO trip_steps (trip_day_id, sequence, type) VALUES ('b0000000-0000-4000-8000-000000000002', 0, 'meal')$$, 'rang >= 1');
CALL pg_temp.expect_error($$INSERT INTO trip_travelers (trip_id, user_id, role) VALUES ('b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000002', 'owner')$$, 'un seul propriétaire par voyage');
CALL pg_temp.expect_error($$INSERT INTO trips (user_id, start_date, end_date, destination_city_id) VALUES ('c0000000-0000-4000-8000-000000000001', '2027-05-02', '2027-05-01', 'a0000000-0000-4000-8000-000000000002')$$, 'fin avant début');
CALL pg_temp.expect_error($$INSERT INTO trip_days (trip_id, day_index, date) VALUES ('b0000000-0000-4000-8000-000000000001', 2, '2027-05-01')$$, 'deux journées à la même date');
CALL pg_temp.expect_error($$INSERT INTO cities (country_id, name, latitude) VALUES ('a0000000-0000-4000-8000-000000000001', 'Nulle part', 95)$$, 'latitude hors bornes');
CALL pg_temp.expect_error($$UPDATE activities SET price_range = 'cher'$$, 'fourchette de prix hors liste');
CALL pg_temp.expect_error($$INSERT INTO activity_media (activity_id, url, origin) VALUES ('a0000000-0000-4000-8000-000000000004', 'u', 'community')$$, 'média communautaire sans auteur');
CALL pg_temp.expect_error($$INSERT INTO journal_exports (trip_id, user_id, status) VALUES ('b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', 'done')$$, 'export terminé sans PDF');
CALL pg_temp.expect_error($$INSERT INTO reviews (activity_id, user_id, rating) VALUES ('a0000000-0000-4000-8000-000000000004', 'c0000000-0000-4000-8000-000000000001', 6)$$, 'note entre 1 et 5');
CALL pg_temp.expect_error($$INSERT INTO favorites (user_id, target_type, target_id) VALUES ('c0000000-0000-4000-8000-000000000001', 'country', 'a0000000-0000-4000-8000-000000000001')$$, 'type de favori hors liste');
CALL pg_temp.expect_error($$DELETE FROM cities WHERE id = 'a0000000-0000-4000-8000-000000000002'$$, 'ville utilisée : suppression refusée');

-- Réservations : référence unique, plusieurs sans référence possibles
INSERT INTO bookings (trip_id, category, reference_code) VALUES ('b0000000-0000-4000-8000-000000000001', 'train', 'ABC123');
INSERT INTO bookings (trip_id, category) VALUES ('b0000000-0000-4000-8000-000000000001', 'train'), ('b0000000-0000-4000-8000-000000000001', 'train');
CALL pg_temp.expect_error($$INSERT INTO bookings (trip_id, category, reference_code) VALUES ('b0000000-0000-4000-8000-000000000001', 'train', 'ABC123')$$, 'même référence de réservation deux fois');

-- Fiche supprimée : l'étape reste (activity_id à NULL) si ce n'est pas une étape activity
UPDATE trip_steps SET type = 'accommodation' WHERE id = 'b0000000-0000-4000-8000-000000000003';
DELETE FROM activities WHERE id = 'a0000000-0000-4000-8000-000000000004';
DO $$ BEGIN
  PERFORM 1 FROM trip_steps WHERE id = 'b0000000-0000-4000-8000-000000000003' AND activity_id IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'ÉCHEC : ON DELETE SET NULL sur trip_steps.activity_id'; END IF;
  RAISE NOTICE 'ok  : fiche supprimée, étape conservée';
END $$;

-- Supprimer le voyage supprime jours, étapes, voyageurs, réservations
DELETE FROM trips WHERE id = 'b0000000-0000-4000-8000-000000000001';
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM trip_days) OR EXISTS (SELECT 1 FROM trip_steps)
     OR EXISTS (SELECT 1 FROM trip_travelers) OR EXISTS (SELECT 1 FROM bookings) THEN
    RAISE EXCEPTION 'ÉCHEC : suppression du voyage en cascade';
  END IF;
  RAISE NOTICE 'ok  : suppression du voyage en cascade';
END $$;

ROLLBACK;
\echo 'travel : toutes les contraintes testées sont respectées.'
