-- Evaluates the deployed predicates against synthetic CTE rows, not user data.
-- This checks outer object-path correlation, including a deceptive group name.
BEGIN;
CREATE TEMP TABLE avatar_policy_results (policy text, scenario text, passed boolean) ON COMMIT DROP;
DO $test$
DECLARE
  p record;
  s record;
  predicate text;
  actual boolean;
  owner_uid constant text := '10000000-0000-0000-0000-000000000001';
  member_uid constant text := '10000000-0000-0000-0000-000000000002';
  outsider_uid constant text := '10000000-0000-0000-0000-000000000003';
  group_id constant text := '20000000-0000-0000-0000-000000000001';
BEGIN
  FOR p IN SELECT policyname, cmd, qual, with_check FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname LIKE 'group_avatar%' LOOP
    predicate := coalesce(p.qual, p.with_check);
    predicate := replace(predicate, 'public.whisper_group_threads', 'fixture_groups');
    predicate := replace(predicate, 'whisper_group_threads', 'fixture_groups');
    predicate := replace(predicate, 'storage.objects.name', 'objects.name');
    predicate := replace(predicate, 'auth.uid()', '(SELECT uid FROM actor)');
    FOR s IN SELECT * FROM (VALUES
      ('owner-current', owner_uid, group_id || '/current.jpg', 'Friends', true, true),
      ('owner-new', owner_uid, group_id || '/new.jpg', 'Friends', true, true),
      ('member-current', member_uid, group_id || '/current.jpg', 'Friends', true, false),
      ('member-old', member_uid, group_id || '/old.jpg', 'Friends', false, false),
      ('outsider', outsider_uid, group_id || '/current.jpg', 'Friends', false, false),
      ('wrong-folder', owner_uid, '20000000-0000-0000-0000-000000000099/current.jpg', 'Friends', false, false),
      ('deceptive-name-wrong-folder', owner_uid, '20000000-0000-0000-0000-000000000099/current.jpg', group_id || '/spoof', false, false),
      ('deceptive-name-member', member_uid, '20000000-0000-0000-0000-000000000099/current.jpg', group_id || '/spoof', false, false)
    ) AS scenarios(label, uid, object_name, group_name, can_read, can_write) LOOP
      EXECUTE format('WITH actor AS (SELECT %L::uuid uid), fixture_groups AS (SELECT %L::uuid id, %L::text name, %L::uuid owner_id, ARRAY[%L::uuid] member_ids, %L::text avatar_path) SELECT coalesce((%s), false) FROM (SELECT %L::text name, %L::text bucket_id) objects', s.uid, group_id, s.group_name, owner_uid, member_uid, group_id || '/current.jpg', predicate, s.object_name, 'whisper-group-avatars') INTO actual;
      INSERT INTO avatar_policy_results VALUES (p.policyname, s.label, actual = CASE WHEN p.cmd = 'SELECT' THEN s.can_read WHEN p.cmd = 'UPDATE' THEN false ELSE s.can_write END);
    END LOOP;
  END LOOP;
  IF (SELECT count(*) FROM avatar_policy_results) <> 56 OR EXISTS (SELECT FROM avatar_policy_results WHERE NOT passed) THEN
    RAISE EXCEPTION 'Group avatar predicate regression failed';
  END IF;
END $test$;
SELECT count(*) AS checks, bool_and(passed) AS all_passed FROM avatar_policy_results;
COMMIT;
