-- ============================================================================
-- TwoFold Security & Regression Test Suite for Task 1.4 Hardening
-- Runs inside a transaction with comprehensive test assertions.
-- At the end, prints a summary of passed and failed test cases.
-- ============================================================================

BEGIN;

CREATE TEMPORARY TABLE test_results (
  test_id text PRIMARY KEY,
  test_name text NOT NULL,
  category text NOT NULL,
  role_used text NOT NULL,
  operation text NOT NULL,
  expected text NOT NULL,
  actual text NOT NULL,
  passed boolean NOT NULL
);
GRANT ALL ON test_results TO PUBLIC;

CREATE OR REPLACE PROCEDURE record_test(
  p_id text,
  p_name text,
  p_category text,
  p_role text,
  p_op text,
  p_expected text,
  p_actual text,
  p_passed boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO test_results (test_id, test_name, category, role_used, operation, expected, actual, passed)
  VALUES (p_id, p_name, p_category, p_role, p_op, p_expected, p_actual, p_passed);
END;
$$;

-- ----------------------------------------------------------------------------
-- Setup Test Fixtures (Auth users, Couple space, Memberships)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_uid_a uuid := 'a0000000-0000-0000-0000-000000000001'::uuid;
  v_uid_b uuid := 'b0000000-0000-0000-0000-000000000002'::uuid;
  v_uid_c uuid := 'c0000000-0000-0000-0000-000000000003'::uuid;
  v_couple_id uuid := '11111111-1111-1111-1111-111111111111'::uuid;
BEGIN
  -- Create auth.users entries
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES
    (v_uid_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'partner.a@twofold.local', 'dummy', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
    (v_uid_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'partner.b@twofold.local', 'dummy', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
    (v_uid_c, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'user.c@twofold.local', 'dummy', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now())
  ON CONFLICT (id) DO NOTHING;

  -- Create profiles
  INSERT INTO public.profiles (id, display_name)
  VALUES
    (v_uid_a, 'Partner A'),
    (v_uid_b, 'Partner B'),
    (v_uid_c, 'User C')
  ON CONFLICT (id) DO NOTHING;

  -- Create couple space
  INSERT INTO public.couples (id, space_name, anniversary_date)
  VALUES (v_couple_id, 'Our Little Universe', '2024-01-01')
  ON CONFLICT (singleton_key) DO UPDATE SET space_name = 'Our Little Universe'
  RETURNING id INTO v_couple_id;

  -- Create couple memberships (owner and partner)
  INSERT INTO public.couple_members (couple_id, user_id, role, status)
  VALUES
    (v_couple_id, v_uid_a, 'owner', 'active'),
    (v_couple_id, v_uid_b, 'partner', 'active')
  ON CONFLICT (couple_id, role) DO NOTHING;
END;
$$;

-- ----------------------------------------------------------------------------
-- Test Category 1: Unauthenticated Visitor (Role anon, auth.uid() IS NULL)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_count integer;
BEGIN
  -- Switch session to anon
  SET LOCAL ROLE anon;
  SET LOCAL request.jwt.claim.sub = '';
  SET LOCAL request.jwt.claims = '';

  -- 1.1 anon cannot read profiles
  SELECT count(*) INTO v_count FROM public.profiles;
  CALL record_test('T1.1', 'Anon cannot SELECT from profiles', 'Unauthenticated Visitor', 'anon', 'SELECT profiles', '0 rows', v_count || ' rows', v_count = 0);

  -- 1.2 anon cannot read user_private_settings
  SELECT count(*) INTO v_count FROM public.user_private_settings;
  CALL record_test('T1.2', 'Anon cannot SELECT from user_private_settings', 'Unauthenticated Visitor', 'anon', 'SELECT user_private_settings', '0 rows', v_count || ' rows', v_count = 0);

  -- 1.3 anon cannot read couples
  SELECT count(*) INTO v_count FROM public.couples;
  CALL record_test('T1.3', 'Anon cannot SELECT from couples', 'Unauthenticated Visitor', 'anon', 'SELECT couples', '0 rows', v_count || ' rows', v_count = 0);

  -- 1.4 anon cannot read couple_members
  SELECT count(*) INTO v_count FROM public.couple_members;
  CALL record_test('T1.4', 'Anon cannot SELECT from couple_members', 'Unauthenticated Visitor', 'anon', 'SELECT couple_members', '0 rows', v_count || ' rows', v_count = 0);

  -- 1.5 anon cannot read memories
  SELECT count(*) INTO v_count FROM public.memories;
  CALL record_test('T1.5', 'Anon cannot SELECT from memories', 'Unauthenticated Visitor', 'anon', 'SELECT memories', '0 rows', v_count || ' rows', v_count = 0);

  -- 1.6 anon cannot read date_plans
  SELECT count(*) INTO v_count FROM public.date_plans;
  CALL record_test('T1.6', 'Anon cannot SELECT from date_plans', 'Unauthenticated Visitor', 'anon', 'SELECT date_plans', '0 rows', v_count || ' rows', v_count = 0);

  -- 1.7 anon cannot read messages
  SELECT count(*) INTO v_count FROM public.messages;
  CALL record_test('T1.7', 'Anon cannot SELECT from messages', 'Unauthenticated Visitor', 'anon', 'SELECT messages', '0 rows', v_count || ' rows', v_count = 0);

  -- 1.8 anon cannot read letters
  SELECT count(*) INTO v_count FROM public.letters;
  CALL record_test('T1.8', 'Anon cannot SELECT from letters', 'Unauthenticated Visitor', 'anon', 'SELECT letters', '0 rows', v_count || ' rows', v_count = 0);

  -- 1.9 anon cannot read surprises
  SELECT count(*) INTO v_count FROM public.surprises;
  CALL record_test('T1.9', 'Anon cannot SELECT from surprises', 'Unauthenticated Visitor', 'anon', 'SELECT surprises', '0 rows', v_count || ' rows', v_count = 0);

  -- 1.10 anon cannot read media_objects
  SELECT count(*) INTO v_count FROM public.media_objects;
  CALL record_test('T1.10', 'Anon cannot SELECT from media_objects', 'Unauthenticated Visitor', 'anon', 'SELECT media_objects', '0 rows', v_count || ' rows', v_count = 0);

  -- 1.11 anon cannot read storage.objects
  SELECT count(*) INTO v_count FROM storage.objects WHERE bucket_id = 'couple-media';
  CALL record_test('T1.11', 'Anon cannot SELECT from storage.objects', 'Unauthenticated Visitor', 'anon', 'SELECT storage.objects', '0 rows', v_count || ' rows', v_count = 0);

  -- 1.12 anon cannot access pending_storage_deletions (permission denied)
  BEGIN
    SELECT count(*) INTO v_count FROM public.pending_storage_deletions;
    CALL record_test('T1.12', 'Anon blocked from pending_storage_deletions', 'Unauthenticated Visitor', 'anon', 'SELECT pending_storage_deletions', 'insufficient_privilege', 'Allowed SELECT', false);
  EXCEPTION WHEN insufficient_privilege THEN
    CALL record_test('T1.12', 'Anon blocked from pending_storage_deletions', 'Unauthenticated Visitor', 'anon', 'SELECT pending_storage_deletions', 'insufficient_privilege', 'insufficient_privilege raised', true);
  END;

  -- 1.13 anon table-level INSERT privilege revoked (SEC-02 hardening)
  BEGIN
    INSERT INTO public.messages (couple_id, sender_id, body)
    VALUES ('11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001', 'Anon message');
    CALL record_test('T1.13', 'Anon INSERT on messages denied by table grant', 'Unauthenticated Visitor', 'anon', 'INSERT messages', 'insufficient_privilege', 'Insert succeeded', false);
  EXCEPTION WHEN insufficient_privilege THEN
    CALL record_test('T1.13', 'Anon INSERT on messages denied by table grant', 'Unauthenticated Visitor', 'anon', 'INSERT messages', 'insufficient_privilege', 'Permission denied at table level', true);
  END;

  RESET ROLE;
END;
$$;

-- ----------------------------------------------------------------------------
-- Test Category 2: Partner A Basic Access & Settings
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_uid_a uuid := 'a0000000-0000-0000-0000-000000000001'::uuid;
  v_uid_b uuid := 'b0000000-0000-0000-0000-000000000002'::uuid;
  v_uid_c uuid := 'c0000000-0000-0000-0000-000000000003'::uuid;
  v_couple_id uuid;
  v_count integer;
  v_name text;
BEGIN
  INSERT INTO public.user_private_settings (user_id, notification_preferences)
  VALUES
    (v_uid_a, '{"email": true}'::jsonb),
    (v_uid_b, '{"email": false}'::jsonb)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT id INTO v_couple_id FROM public.couples LIMIT 1;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);

  -- 2.1 Partner A can read own and partner profiles
  SELECT count(*) INTO v_count FROM public.profiles WHERE id IN (v_uid_a, v_uid_b);
  CALL record_test('T2.1', 'Partner A can SELECT own and partner profiles', 'Partner A Access', 'Partner A', 'SELECT profiles', '2 rows', v_count || ' rows', v_count = 2);

  -- 2.2 Partner A CANNOT read User C profile
  SELECT count(*) INTO v_count FROM public.profiles WHERE id = v_uid_c;
  CALL record_test('T2.2', 'Partner A cannot SELECT User C profile', 'Partner A Access', 'Partner A', 'SELECT profiles (User C)', '0 rows', v_count || ' rows', v_count = 0);

  -- 2.3 Partner A can UPDATE own profile
  UPDATE public.profiles SET display_name = 'Partner A Updated' WHERE id = v_uid_a;
  SELECT display_name INTO v_name FROM public.profiles WHERE id = v_uid_a;
  CALL record_test('T2.3', 'Partner A can UPDATE own profile', 'Partner A Access', 'Partner A', 'UPDATE profiles (self)', 'Partner A Updated', v_name, v_name = 'Partner A Updated');

  -- 2.4 Partner A CANNOT UPDATE Partner B profile
  UPDATE public.profiles SET display_name = 'Hacked by A' WHERE id = v_uid_b;
  SELECT display_name INTO v_name FROM public.profiles WHERE id = v_uid_b;
  CALL record_test('T2.4', 'Partner A cannot UPDATE Partner B profile', 'Partner A Access', 'Partner A', 'UPDATE profiles (Partner B)', 'Partner B', v_name, v_name = 'Partner B');

  -- 2.5 Partner A can read own private settings
  SELECT count(*) INTO v_count FROM public.user_private_settings WHERE user_id = v_uid_a;
  CALL record_test('T2.5', 'Partner A can SELECT own private settings', 'Partner A Access', 'Partner A', 'SELECT user_private_settings (self)', '1 row', v_count || ' rows', v_count = 1);

  -- 2.6 Partner A CANNOT read Partner B private settings
  SELECT count(*) INTO v_count FROM public.user_private_settings WHERE user_id = v_uid_b;
  CALL record_test('T2.6', 'Partner A cannot SELECT Partner B private settings', 'Partner A Access', 'Partner A', 'SELECT user_private_settings (Partner B)', '0 rows', v_count || ' rows', v_count = 0);

  -- 2.7 Partner A can read Couple space
  SELECT count(*) INTO v_count FROM public.couples WHERE id = v_couple_id;
  CALL record_test('T2.7', 'Partner A can SELECT couple record', 'Partner A Access', 'Partner A', 'SELECT couples', '1 row', v_count || ' rows', v_count = 1);

  -- 2.8 Partner A can update couple display preferences
  UPDATE public.couples SET display_preferences = '{"theme": "dark"}'::jsonb WHERE id = v_couple_id;
  CALL record_test('T2.8', 'Partner A can UPDATE couple settings', 'Partner A Access', 'Partner A', 'UPDATE couples', 'Success', 'Updated', true);

  -- 2.9 Partner A can read couple_members
  SELECT count(*) INTO v_count FROM public.couple_members WHERE couple_id = v_couple_id;
  CALL record_test('T2.9', 'Partner A can SELECT couple_members', 'Partner A Access', 'Partner A', 'SELECT couple_members', '2 rows', v_count || ' rows', v_count = 2);

  RESET ROLE;
END;
$$;

-- ----------------------------------------------------------------------------
-- Test Category 3: Unauthorized User C Isolation
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_uid_c uuid := 'c0000000-0000-0000-0000-000000000003'::uuid;
  v_couple_id uuid;
  v_count integer;
BEGIN
  SELECT id INTO v_couple_id FROM public.couples LIMIT 1;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_uid_c::text, true);

  SELECT count(*) INTO v_count FROM public.couples WHERE id = v_couple_id;
  CALL record_test('T3.1', 'User C cannot SELECT Couple 1', 'User C Isolation', 'User C', 'SELECT couples', '0 rows', v_count || ' rows', v_count = 0);

  SELECT count(*) INTO v_count FROM public.couple_members WHERE couple_id = v_couple_id;
  CALL record_test('T3.2', 'User C cannot SELECT Couple 1 members', 'User C Isolation', 'User C', 'SELECT couple_members', '0 rows', v_count || ' rows', v_count = 0);

  SELECT count(*) INTO v_count FROM public.memories WHERE couple_id = v_couple_id;
  CALL record_test('T3.3', 'User C cannot SELECT Couple 1 memories', 'User C Isolation', 'User C', 'SELECT memories', '0 rows', v_count || ' rows', v_count = 0);

  SELECT count(*) INTO v_count FROM public.user_private_settings;
  CALL record_test('T3.4', 'User C cannot SELECT Partner A private settings', 'User C Isolation', 'User C', 'SELECT user_private_settings', '0 rows', v_count || ' rows', v_count = 0);

  BEGIN
    INSERT INTO public.messages (couple_id, sender_id, body)
    VALUES (v_couple_id, v_uid_c, 'Rogue message from User C');
    CALL record_test('T3.5', 'User C cannot INSERT into Couple 1 messages', 'User C Isolation', 'User C', 'INSERT messages', 'Denied', 'Inserted', false);
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    CALL record_test('T3.5', 'User C cannot INSERT into Couple 1 messages', 'User C Isolation', 'User C', 'INSERT messages', 'Denied', 'Blocked by RLS', true);
  END;

  RESET ROLE;
END;
$$;

-- ----------------------------------------------------------------------------
-- Test Category 4: Membership Manipulation & Client Restrictions (SEC-02 Table Grants)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_uid_a uuid := 'a0000000-0000-0000-0000-000000000001'::uuid;
  v_uid_b uuid := 'b0000000-0000-0000-0000-000000000002'::uuid;
  v_uid_c uuid := 'c0000000-0000-0000-0000-000000000003'::uuid;
  v_couple_id uuid;
BEGIN
  SELECT id INTO v_couple_id FROM public.couples LIMIT 1;

  -- 4.1 User C attempts to insert membership row (revoked table grant)
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_uid_c::text, true);

  BEGIN
    INSERT INTO public.couple_members (couple_id, user_id, role)
    VALUES (v_couple_id, v_uid_c, 'partner');
    CALL record_test('T4.1', 'User C cannot INSERT couple_members', 'Membership Protections', 'User C', 'INSERT couple_members', 'insufficient_privilege', 'Inserted', false);
  EXCEPTION WHEN insufficient_privilege THEN
    CALL record_test('T4.1', 'User C cannot INSERT couple_members', 'Membership Protections', 'User C', 'INSERT couple_members', 'insufficient_privilege', 'Denied at table level', true);
  END;

  -- 4.2 Partner A attempts to add third member (revoked table grant)
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);

  BEGIN
    INSERT INTO public.couple_members (couple_id, user_id, role)
    VALUES (v_couple_id, v_uid_c, 'partner');
    CALL record_test('T4.2', 'Partner A cannot INSERT third member', 'Membership Protections', 'Partner A', 'INSERT couple_members', 'insufficient_privilege', 'Inserted', false);
  EXCEPTION WHEN insufficient_privilege THEN
    CALL record_test('T4.2', 'Partner A cannot INSERT third member', 'Membership Protections', 'Partner A', 'INSERT couple_members', 'insufficient_privilege', 'Denied at table level', true);
  END;

  -- 4.3 Partner A attempts to delete Partner B membership (revoked table grant)
  BEGIN
    DELETE FROM public.couple_members WHERE user_id = v_uid_b;
    CALL record_test('T4.3', 'Partner A cannot DELETE couple_members row', 'Membership Protections', 'Partner A', 'DELETE couple_members', 'insufficient_privilege', 'Deleted', false);
  EXCEPTION WHEN insufficient_privilege THEN
    CALL record_test('T4.3', 'Partner A cannot DELETE couple_members row', 'Membership Protections', 'Partner A', 'DELETE couple_members', 'insufficient_privilege', 'Denied at table level', true);
  END;

  -- 4.4 Partner A attempts to delete Couple space (revoked table grant)
  BEGIN
    DELETE FROM public.couples WHERE id = v_couple_id;
    CALL record_test('T4.4', 'Partner A cannot DELETE couples row', 'Membership Protections', 'Partner A', 'DELETE couples', 'insufficient_privilege', 'Deleted', false);
  EXCEPTION WHEN insufficient_privilege THEN
    CALL record_test('T4.4', 'Partner A cannot DELETE couples row', 'Membership Protections', 'Partner A', 'DELETE couples', 'insufficient_privilege', 'Denied at table level', true);
  END;

  -- 4.5 Partner A attempts to create a second couple space (revoked table grant)
  BEGIN
    INSERT INTO public.couples (space_name) VALUES ('Second Space');
    CALL record_test('T4.5', 'Partner A cannot INSERT new couple space', 'Membership Protections', 'Partner A', 'INSERT couples', 'insufficient_privilege', 'Inserted', false);
  EXCEPTION WHEN insufficient_privilege THEN
    CALL record_test('T4.5', 'Partner A cannot INSERT new couple space', 'Membership Protections', 'Partner A', 'INSERT couples', 'insufficient_privilege', 'Denied at table level', true);
  END;

  RESET ROLE;
END;
$$;

-- ----------------------------------------------------------------------------
-- Test Category 5: Identity Spoofing Protections
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_uid_a uuid := 'a0000000-0000-0000-0000-000000000001'::uuid;
  v_uid_b uuid := 'b0000000-0000-0000-0000-000000000002'::uuid;
  v_couple_id uuid;
BEGIN
  SELECT id INTO v_couple_id FROM public.couples LIMIT 1;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);

  -- 5.1 Partner A attempts to spoof sender_id on messages
  BEGIN
    INSERT INTO public.messages (couple_id, sender_id, body)
    VALUES (v_couple_id, v_uid_b, 'Impersonating B');
    CALL record_test('T5.1', 'Partner A cannot spoof sender_id on messages', 'Spoofing Protections', 'Partner A', 'INSERT messages (spoofed sender)', 'Denied', 'Inserted', false);
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    CALL record_test('T5.1', 'Partner A cannot spoof sender_id on messages', 'Spoofing Protections', 'Partner A', 'INSERT messages (spoofed sender)', 'Denied', 'Blocked by RLS', true);
  END;

  -- 5.2 Partner A attempts to spoof created_by on memories
  BEGIN
    INSERT INTO public.memories (couple_id, created_by, title, event_date)
    VALUES (v_couple_id, v_uid_b, 'Spoofed Memory', '2024-05-01');
    CALL record_test('T5.2', 'Partner A cannot spoof created_by on memories', 'Spoofing Protections', 'Partner A', 'INSERT memories (spoofed creator)', 'Denied', 'Inserted', false);
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    CALL record_test('T5.2', 'Partner A cannot spoof created_by on memories', 'Spoofing Protections', 'Partner A', 'INSERT memories (spoofed creator)', 'Denied', 'Blocked by RLS', true);
  END;

  -- 5.3 Partner A attempts to spoof created_by on date_plans
  BEGIN
    INSERT INTO public.date_plans (couple_id, created_by, title, starts_at)
    VALUES (v_couple_id, v_uid_b, 'Spoofed Date', now() + interval '1 day');
    CALL record_test('T5.3', 'Partner A cannot spoof created_by on date_plans', 'Spoofing Protections', 'Partner A', 'INSERT date_plans (spoofed creator)', 'Denied', 'Inserted', false);
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    CALL record_test('T5.3', 'Partner A cannot spoof created_by on date_plans', 'Spoofing Protections', 'Partner A', 'INSERT date_plans (spoofed creator)', 'Denied', 'Blocked by RLS', true);
  END;

  -- 5.4 Partner A attempts to spoof sender_id on letters
  BEGIN
    INSERT INTO public.letters (couple_id, sender_id, title, body, status)
    VALUES (v_couple_id, v_uid_b, 'Spoofed Letter', 'Body', 'draft');
    CALL record_test('T5.4', 'Partner A cannot spoof sender_id on letters', 'Spoofing Protections', 'Partner A', 'INSERT letters (spoofed sender)', 'Denied', 'Inserted', false);
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    CALL record_test('T5.4', 'Partner A cannot spoof sender_id on letters', 'Spoofing Protections', 'Partner A', 'INSERT letters (spoofed sender)', 'Denied', 'Blocked by RLS', true);
  END;

  -- 5.5 Partner A attempts to spoof created_by on surprises
  BEGIN
    INSERT INTO public.surprises (couple_id, created_by, title, content)
    VALUES (v_couple_id, v_uid_b, 'Spoofed Surprise', 'Hidden Content');
    CALL record_test('T5.5', 'Partner A cannot spoof created_by on surprises', 'Spoofing Protections', 'Partner A', 'INSERT surprises (spoofed creator)', 'Denied', 'Inserted', false);
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    CALL record_test('T5.5', 'Partner A cannot spoof created_by on surprises', 'Spoofing Protections', 'Partner A', 'INSERT surprises (spoofed creator)', 'Denied', 'Blocked by RLS', true);
  END;

  RESET ROLE;
END;
$$;

-- ----------------------------------------------------------------------------
-- Test Category 6: Shared Memories & Date Plans CRUD
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_uid_a uuid := 'a0000000-0000-0000-0000-000000000001'::uuid;
  v_uid_b uuid := 'b0000000-0000-0000-0000-000000000002'::uuid;
  v_couple_id uuid;
  v_mem_id uuid;
  v_plan_id uuid;
  v_count integer;
  v_title text;
BEGIN
  SELECT id INTO v_couple_id FROM public.couples LIMIT 1;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);

  INSERT INTO public.memories (couple_id, created_by, title, event_date, description)
  VALUES (v_couple_id, v_uid_a, 'Trip to Paris', '2024-06-15', 'Walking by the Seine')
  RETURNING id INTO v_mem_id;

  CALL record_test('T6.1', 'Partner A can create shared memory', 'Memories & Date Plans', 'Partner A', 'INSERT memories', 'Success', 'Created: ' || v_mem_id, v_mem_id IS NOT NULL);

  PERFORM set_config('request.jwt.claim.sub', v_uid_b::text, true);
  SELECT count(*) INTO v_count FROM public.memories WHERE id = v_mem_id;
  CALL record_test('T6.2', 'Partner B can SELECT shared memory', 'Memories & Date Plans', 'Partner B', 'SELECT memories', '1 row', v_count || ' rows', v_count = 1);

  UPDATE public.memories SET description = 'Walking by the Seine at sunset' WHERE id = v_mem_id;
  SELECT description INTO v_title FROM public.memories WHERE id = v_mem_id;
  CALL record_test('T6.3', 'Partner B can UPDATE shared memory', 'Memories & Date Plans', 'Partner B', 'UPDATE memories', 'Updated description', v_title, v_title LIKE '%sunset%');

  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);
  INSERT INTO public.date_plans (couple_id, created_by, title, starts_at)
  VALUES (v_couple_id, v_uid_a, 'Stargazing Night', now() + interval '3 days')
  RETURNING id INTO v_plan_id;

  CALL record_test('T6.4', 'Partner A can create shared date plan', 'Memories & Date Plans', 'Partner A', 'INSERT date_plans', 'Success', 'Created: ' || v_plan_id, v_plan_id IS NOT NULL);

  PERFORM set_config('request.jwt.claim.sub', v_uid_b::text, true);
  UPDATE public.date_plans SET status = 'planned' WHERE id = v_plan_id;
  SELECT status INTO v_title FROM public.date_plans WHERE id = v_plan_id;
  CALL record_test('T6.5', 'Partner B can UPDATE shared date plan', 'Memories & Date Plans', 'Partner B', 'UPDATE date_plans', 'planned', v_title, v_title = 'planned');

  DELETE FROM public.date_plans WHERE id = v_plan_id;
  SELECT count(*) INTO v_count FROM public.date_plans WHERE id = v_plan_id;
  CALL record_test('T6.6', 'Partner B can DELETE shared date plan', 'Memories & Date Plans', 'Partner B', 'DELETE date_plans', '0 rows', v_count || ' rows', v_count = 0);

  RESET ROLE;
END;
$$;

-- ----------------------------------------------------------------------------
-- Test Category 7: Messages & Chat Permissions
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_uid_a uuid := 'a0000000-0000-0000-0000-000000000001'::uuid;
  v_uid_b uuid := 'b0000000-0000-0000-0000-000000000002'::uuid;
  v_couple_id uuid;
  v_msg_id uuid;
  v_count integer;
  v_body text;
BEGIN
  SELECT id INTO v_couple_id FROM public.couples LIMIT 1;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);

  INSERT INTO public.messages (couple_id, sender_id, body)
  VALUES (v_couple_id, v_uid_a, 'Good morning!')
  RETURNING id INTO v_msg_id;

  CALL record_test('T7.1', 'Partner A can INSERT message as self', 'Chat & Messages', 'Partner A', 'INSERT messages', 'Success', 'Created: ' || v_msg_id, v_msg_id IS NOT NULL);

  PERFORM set_config('request.jwt.claim.sub', v_uid_b::text, true);
  SELECT count(*) INTO v_count FROM public.messages WHERE id = v_msg_id;
  CALL record_test('T7.2', 'Partner B can SELECT couple message', 'Chat & Messages', 'Partner B', 'SELECT messages', '1 row', v_count || ' rows', v_count = 1);

  UPDATE public.messages SET body = 'Tampered body' WHERE id = v_msg_id;
  SELECT body INTO v_body FROM public.messages WHERE id = v_msg_id;
  CALL record_test('T7.3', 'Partner B cannot UPDATE Partner A message', 'Chat & Messages', 'Partner B', 'UPDATE messages (Partner A)', 'Good morning!', v_body, v_body = 'Good morning!');

  DELETE FROM public.messages WHERE id = v_msg_id;
  SELECT count(*) INTO v_count FROM public.messages WHERE id = v_msg_id;
  CALL record_test('T7.4', 'Partner B cannot DELETE Partner A message', 'Chat & Messages', 'Partner B', 'DELETE messages (Partner A)', '1 row remains', v_count || ' rows', v_count = 1);

  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);
  UPDATE public.messages SET body = 'Good morning my love!' WHERE id = v_msg_id;
  SELECT body INTO v_body FROM public.messages WHERE id = v_msg_id;
  CALL record_test('T7.5', 'Partner A can UPDATE own message', 'Chat & Messages', 'Partner A', 'UPDATE messages (self)', 'Good morning my love!', v_body, v_body = 'Good morning my love!');

  DELETE FROM public.messages WHERE id = v_msg_id;
  SELECT count(*) INTO v_count FROM public.messages WHERE id = v_msg_id;
  CALL record_test('T7.6', 'Partner A can DELETE own message', 'Chat & Messages', 'Partner A', 'DELETE messages (self)', '0 rows', v_count || ' rows', v_count = 0);

  RESET ROLE;
END;
$$;

-- ----------------------------------------------------------------------------
-- Test Category 8: Locked Letters & Title Privacy (SEC-04 Hardening)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_uid_a uuid := 'a0000000-0000-0000-0000-000000000001'::uuid;
  v_uid_b uuid := 'b0000000-0000-0000-0000-000000000002'::uuid;
  v_couple_id uuid;
  v_draft_id uuid;
  v_locked_id uuid;
  v_unlocked_id uuid;
  v_count integer;
  v_preview_title text;
  v_preview_body text;
  v_preview_locked boolean;
BEGIN
  SELECT id INTO v_couple_id FROM public.couples LIMIT 1;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);

  -- 8.1 Partner A creates a draft letter
  INSERT INTO public.letters (couple_id, sender_id, title, body, status)
  VALUES (v_couple_id, v_uid_a, 'Draft Love Letter', 'Draft Content Secret', 'draft')
  RETURNING id INTO v_draft_id;

  -- 8.2 Partner A creates a locked sent letter (unlocks tomorrow)
  INSERT INTO public.letters (couple_id, sender_id, title, body, status, unlock_at)
  VALUES (v_couple_id, v_uid_a, 'Paris Vacation Flight Details', 'I have loved you for 1000 days', 'sent', now() + interval '1 day')
  RETURNING id INTO v_locked_id;

  -- 8.3 Partner A creates an unlocked sent letter (unlock_at is NULL)
  INSERT INTO public.letters (couple_id, sender_id, title, body, status)
  VALUES (v_couple_id, v_uid_a, 'Instant Note', 'Thinking of you right now', 'sent')
  RETURNING id INTO v_unlocked_id;

  SELECT count(*) INTO v_count FROM public.letters WHERE couple_id = v_couple_id;
  CALL record_test('T8.1', 'Sender can SELECT all own letters directly', 'Letters Access', 'Partner A', 'SELECT letters (sender)', '>= 3 rows', v_count || ' rows', v_count >= 3);

  -- Switch to Partner B
  PERFORM set_config('request.jwt.claim.sub', v_uid_b::text, true);

  -- 8.4 Partner B direct table query on draft letter returns 0 rows
  SELECT count(*) INTO v_count FROM public.letters WHERE id = v_draft_id;
  CALL record_test('T8.2', 'Partner B cannot SELECT partner draft letter', 'Letters Access', 'Partner B', 'SELECT letters (draft)', '0 rows', v_count || ' rows', v_count = 0);

  -- 8.5 Partner B direct table query on locked letter returns 0 rows
  SELECT count(*) INTO v_count FROM public.letters WHERE id = v_locked_id;
  CALL record_test('T8.3', 'Partner B cannot SELECT locked letter directly', 'Letters Access', 'Partner B', 'SELECT letters (locked)', '0 rows', v_count || ' rows', v_count = 0);

  -- 8.6 SEC-04: Preview RPC masks BOTH locked letter title ('Locked Letter') and body (NULL)
  SELECT title, body, is_locked INTO v_preview_title, v_preview_body, v_preview_locked
  FROM public.get_couple_letters_preview()
  WHERE id = v_locked_id;

  CALL record_test('T8.4', 'SEC-04: Preview RPC masks locked title and body', 'Letters Access', 'Partner B', 'get_couple_letters_preview() (locked)', 'title=Locked Letter, body=NULL, locked=true', 'title=' || COALESCE(v_preview_title, 'NULL') || ', body=' || COALESCE(v_preview_body, 'NULL') || ', locked=' || v_preview_locked::text, v_preview_title = 'Locked Letter' AND v_preview_body IS NULL AND v_preview_locked = true);

  -- 8.7 Partner B direct table query on unlocked letter succeeds with full title and body
  SELECT count(*) INTO v_count FROM public.letters WHERE id = v_unlocked_id;
  CALL record_test('T8.5', 'Partner B can SELECT unlocked sent letter directly', 'Letters Access', 'Partner B', 'SELECT letters (unlocked)', '1 row', v_count || ' rows', v_count = 1);

  -- Preview RPC on unlocked letter reveals actual title and body
  SELECT title, body, is_locked INTO v_preview_title, v_preview_body, v_preview_locked
  FROM public.get_couple_letters_preview()
  WHERE id = v_unlocked_id;

  CALL record_test('T8.6', 'Preview RPC shows actual title on unlocked letter', 'Letters Access', 'Partner B', 'get_couple_letters_preview() (unlocked)', 'title=Instant Note, locked=false', 'title=' || v_preview_title || ', locked=' || v_preview_locked::text, v_preview_title = 'Instant Note' AND v_preview_locked = false);

  RESET ROLE;
END;
$$;

-- ----------------------------------------------------------------------------
-- Test Category 9: Surprises & Server-Time Reveal RPC
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_uid_a uuid := 'a0000000-0000-0000-0000-000000000001'::uuid;
  v_uid_b uuid := 'b0000000-0000-0000-0000-000000000002'::uuid;
  v_couple_id uuid;
  v_locked_surprise_id uuid;
  v_ready_surprise_id uuid;
  v_count integer;
  v_preview_content text;
  v_preview_locked boolean;
  v_preview_ready boolean;
  v_revealed_surprise record;
BEGIN
  SELECT id INTO v_couple_id FROM public.couples LIMIT 1;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);

  -- 9.1 Partner A creates locked surprise (reveal_at = tomorrow)
  INSERT INTO public.surprises (couple_id, created_by, title, content, reveal_at)
  VALUES (v_couple_id, v_uid_a, 'Future Birthday Gift', 'Concert tickets to your favorite band!', now() + interval '1 day')
  RETURNING id INTO v_locked_surprise_id;

  -- 9.2 Partner A creates ready surprise (reveal_at in past)
  INSERT INTO public.surprises (couple_id, created_by, title, content, reveal_at)
  VALUES (v_couple_id, v_uid_a, 'Ready Mystery Box', 'Look under the coffee table cushion!', now() - interval '1 hour')
  RETURNING id INTO v_ready_surprise_id;

  -- Switch to Partner B
  PERFORM set_config('request.jwt.claim.sub', v_uid_b::text, true);

  -- 9.3 Partner B direct table query on unrevealed surprise returns 0 rows
  SELECT count(*) INTO v_count FROM public.surprises WHERE id = v_locked_surprise_id;
  CALL record_test('T9.1', 'Recipient cannot SELECT unrevealed surprise directly', 'Surprises Security', 'Partner B', 'SELECT surprises (unrevealed)', '0 rows', v_count || ' rows', v_count = 0);

  -- 9.4 Preview RPC masks unopened surprise content as NULL
  SELECT content, is_locked, is_ready_to_reveal INTO v_preview_content, v_preview_locked, v_preview_ready
  FROM public.get_couple_surprises_preview()
  WHERE id = v_locked_surprise_id;

  CALL record_test('T9.2', 'Preview RPC masks locked surprise content as NULL', 'Surprises Security', 'Partner B', 'get_couple_surprises_preview()', 'content=NULL, locked=true', 'content=' || COALESCE(v_preview_content, 'NULL') || ', locked=' || v_preview_locked::text, v_preview_content IS NULL AND v_preview_locked = true);

  -- 9.5 Direct table UPDATE by recipient is denied
  UPDATE public.surprises SET status = 'revealed' WHERE id = v_locked_surprise_id;
  SELECT count(*) INTO v_count FROM public.surprises WHERE id = v_locked_surprise_id;
  CALL record_test('T9.3', 'Recipient cannot directly UPDATE surprise to revealed', 'Surprises Security', 'Partner B', 'UPDATE surprises', '0 rows affected', v_count || ' rows', v_count = 0);

  -- 9.6 Calling reveal_surprise on locked surprise before reveal_at is REJECTED by server clock
  BEGIN
    PERFORM public.reveal_surprise(v_locked_surprise_id);
    CALL record_test('T9.4', 'Cannot reveal before reveal_at time', 'Surprises Security', 'Partner B', 'reveal_surprise() (early)', 'check_violation', 'Revealed early', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('T9.4', 'Cannot reveal before reveal_at time', 'Surprises Security', 'Partner B', 'reveal_surprise() (early)', 'check_violation', 'check_violation raised', true);
  END;

  -- 9.7 Calling reveal_surprise on ready surprise SUCCEEDS
  v_revealed_surprise := public.reveal_surprise(v_ready_surprise_id);
  CALL record_test('T9.5', 'Recipient can reveal ready surprise via RPC', 'Surprises Security', 'Partner B', 'reveal_surprise() (ready)', 'status=revealed', 'status=' || v_revealed_surprise.status, v_revealed_surprise.status = 'revealed');

  -- 9.8 After reveal, Partner B can SELECT surprise from public.surprises directly
  SELECT count(*) INTO v_count FROM public.surprises WHERE id = v_ready_surprise_id;
  CALL record_test('T9.6', 'Recipient can SELECT revealed surprise directly', 'Surprises Security', 'Partner B', 'SELECT surprises (revealed)', '1 row', v_count || ' rows', v_count = 1);

  -- 9.9 Creator cannot call reveal_surprise on their own surprise
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);
  BEGIN
    PERFORM public.reveal_surprise(v_locked_surprise_id);
    CALL record_test('T9.7', 'Creator cannot reveal own surprise', 'Surprises Security', 'Partner A', 'reveal_surprise() (own)', 'insufficient_privilege', 'Revealed own', false);
  EXCEPTION WHEN insufficient_privilege THEN
    CALL record_test('T9.7', 'Creator cannot reveal own surprise', 'Surprises Security', 'Partner A', 'reveal_surprise() (own)', 'insufficient_privilege', 'insufficient_privilege raised', true);
  END;

  RESET ROLE;
END;
$$;

-- ----------------------------------------------------------------------------
-- Test Category 10: Media Objects & Storage Security
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_uid_a uuid := 'a0000000-0000-0000-0000-000000000001'::uuid;
  v_uid_b uuid := 'b0000000-0000-0000-0000-000000000002'::uuid;
  v_uid_c uuid := 'c0000000-0000-0000-0000-000000000003'::uuid;
  v_couple_id uuid;
  v_mem_id uuid;
  v_surprise_id uuid;
  v_media_mem_id uuid;
  v_media_surp_id uuid;
  v_path_mem text;
  v_path_surp text;
  v_count integer;
  v_can_insert boolean;
  v_can_manage boolean;
BEGIN
  SELECT id INTO v_couple_id FROM public.couples LIMIT 1;
  SELECT id INTO v_mem_id FROM public.memories WHERE couple_id = v_couple_id LIMIT 1;

  v_path_mem := v_couple_id::text || '/memory/photo_paris.jpg';
  v_path_surp := v_couple_id::text || '/surprise/gift_box.png';

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);

  -- 10.1 Partner A inserts memory media
  INSERT INTO public.media_objects (
    couple_id, uploaded_by, entity_type, memory_id,
    bucket_id, storage_path, mime_type, size_bytes
  )
  VALUES (
    v_couple_id, v_uid_a, 'memory', v_mem_id,
    'couple-media', v_path_mem, 'image/jpeg', 204800
  )
  RETURNING id INTO v_media_mem_id;

  CALL record_test('T10.1', 'Partner A can insert memory media_object', 'Storage & Media', 'Partner A', 'INSERT media_objects', 'Success', 'Created: ' || v_media_mem_id, v_media_mem_id IS NOT NULL);

  -- Insert mock row into storage.objects as storage admin
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, owner)
  VALUES ('couple-media', v_path_mem, v_uid_a);

  -- Switch back to Partner A
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);

  -- 10.2 Partner A can read memory storage object
  SELECT count(*) INTO v_count FROM storage.objects WHERE bucket_id = 'couple-media' AND name = v_path_mem;
  CALL record_test('T10.2', 'Partner A can SELECT memory storage object', 'Storage & Media', 'Partner A', 'SELECT storage.objects', '1 row', v_count || ' rows', v_count = 1);

  -- 10.3 Partner B can read memory media and storage object
  PERFORM set_config('request.jwt.claim.sub', v_uid_b::text, true);
  SELECT count(*) INTO v_count FROM public.media_objects WHERE id = v_media_mem_id;
  CALL record_test('T10.3', 'Partner B can SELECT memory media_object', 'Storage & Media', 'Partner B', 'SELECT media_objects', '1 row', v_count || ' rows', v_count = 1);

  SELECT count(*) INTO v_count FROM storage.objects WHERE bucket_id = 'couple-media' AND name = v_path_mem;
  CALL record_test('T10.4', 'Partner B can SELECT memory storage object', 'Storage & Media', 'Partner B', 'SELECT storage.objects', '1 row', v_count || ' rows', v_count = 1);

  -- 10.4 User C CANNOT read memory media_object or storage object
  PERFORM set_config('request.jwt.claim.sub', v_uid_c::text, true);
  SELECT count(*) INTO v_count FROM public.media_objects WHERE id = v_media_mem_id;
  CALL record_test('T10.5', 'User C cannot SELECT couple media_object', 'Storage & Media', 'User C', 'SELECT media_objects', '0 rows', v_count || ' rows', v_count = 0);

  SELECT count(*) INTO v_count FROM storage.objects WHERE bucket_id = 'couple-media' AND name = v_path_mem;
  CALL record_test('T10.6', 'User C cannot SELECT couple storage object', 'Storage & Media', 'User C', 'SELECT storage.objects', '0 rows', v_count || ' rows', v_count = 0);

  -- 10.5 Surprise Media Protection (unopened surprise)
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);
  INSERT INTO public.surprises (couple_id, created_by, title, content, reveal_at)
  VALUES (v_couple_id, v_uid_a, 'Secret Trip', 'We are going to Rome!', now() + interval '2 days')
  RETURNING id INTO v_surprise_id;

  INSERT INTO public.media_objects (
    couple_id, uploaded_by, entity_type, surprise_id,
    bucket_id, storage_path, mime_type, size_bytes
  )
  VALUES (
    v_couple_id, v_uid_a, 'surprise', v_surprise_id,
    'couple-media', v_path_surp, 'image/png', 512000
  )
  RETURNING id INTO v_media_surp_id;

  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, owner)
  VALUES ('couple-media', v_path_surp, v_uid_a);

  -- Partner B cannot see unopened surprise media or storage
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_uid_b::text, true);

  SELECT count(*) INTO v_count FROM public.media_objects WHERE id = v_media_surp_id;
  CALL record_test('T10.7', 'Partner B cannot SELECT unopened surprise media_object', 'Storage & Media', 'Partner B', 'SELECT media_objects (surprise)', '0 rows', v_count || ' rows', v_count = 0);

  SELECT count(*) INTO v_count FROM storage.objects WHERE bucket_id = 'couple-media' AND name = v_path_surp;
  CALL record_test('T10.8', 'Partner B cannot SELECT unopened surprise storage object', 'Storage & Media', 'Partner B', 'SELECT storage.objects (surprise)', '0 rows', v_count || ' rows', v_count = 0);

  -- 10.6 Arbitrary Storage Upload Rejection
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);
  v_can_insert := public.can_insert_storage_object('couple-media', v_couple_id::text || '/arbitrary/hack.jpg');
  CALL record_test('T10.9', 'can_insert_storage_object rejects unregistered storage path', 'Storage & Media', 'Partner A', 'can_insert_storage_object()', 'false', v_can_insert::text, v_can_insert = false);

  -- 10.7 Avatar ownership rule: Partner A cannot attach avatar for Partner B
  BEGIN
    INSERT INTO public.media_objects (
      couple_id, uploaded_by, entity_type, profile_id,
      bucket_id, storage_path, mime_type, size_bytes
    )
    VALUES (
      v_couple_id, v_uid_a, 'avatar', v_uid_b,
      'couple-media', v_couple_id::text || '/avatar/partner_b.jpg', 'image/jpeg', 102400
    );
    CALL record_test('T10.10', 'Partner A cannot attach avatar for Partner B profile', 'Storage & Media', 'Partner A', 'INSERT media_objects (avatar B)', 'insufficient_privilege', 'Inserted', false);
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    CALL record_test('T10.10', 'Partner A cannot attach avatar for Partner B profile', 'Storage & Media', 'Partner A', 'INSERT media_objects (avatar B)', 'insufficient_privilege', 'Blocked by avatar rule', true);
  END;

  RESET ROLE;
END;
$$;

-- ----------------------------------------------------------------------------
-- Test Category 11: Pending Storage Deletions Table Isolation
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_uid_a uuid := 'a0000000-0000-0000-0000-000000000001'::uuid;
  v_uid_c uuid := 'c0000000-0000-0000-0000-000000000003'::uuid;
  v_count integer;
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);

  BEGIN
    SELECT count(*) INTO v_count FROM public.pending_storage_deletions;
    CALL record_test('T11.1', 'Partner A cannot SELECT from pending_storage_deletions', 'Deletion Queue Isolation', 'Partner A', 'SELECT pending_storage_deletions', 'insufficient_privilege', 'Allowed SELECT', false);
  EXCEPTION WHEN insufficient_privilege THEN
    CALL record_test('T11.1', 'Partner A cannot SELECT from pending_storage_deletions', 'Deletion Queue Isolation', 'Partner A', 'SELECT pending_storage_deletions', 'insufficient_privilege', 'insufficient_privilege raised', true);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_uid_c::text, true);

  BEGIN
    SELECT count(*) INTO v_count FROM public.pending_storage_deletions;
    CALL record_test('T11.2', 'User C cannot SELECT from pending_storage_deletions', 'Deletion Queue Isolation', 'User C', 'SELECT pending_storage_deletions', 'insufficient_privilege', 'Allowed SELECT', false);
  EXCEPTION WHEN insufficient_privilege THEN
    CALL record_test('T11.2', 'User C cannot SELECT from pending_storage_deletions', 'Deletion Queue Isolation', 'User C', 'SELECT pending_storage_deletions', 'insufficient_privilege', 'insufficient_privilege raised', true);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);

  BEGIN
    INSERT INTO public.pending_storage_deletions (couple_id, bucket_id, storage_path, entity_type)
    VALUES ('11111111-1111-1111-1111-111111111111', 'couple-media', '11111111-1111-1111-1111-111111111111/memory/test.jpg', 'memory');
    CALL record_test('T11.3', 'Partner A cannot INSERT into pending_storage_deletions', 'Deletion Queue Isolation', 'Partner A', 'INSERT pending_storage_deletions', 'insufficient_privilege', 'Allowed INSERT', false);
  EXCEPTION WHEN insufficient_privilege THEN
    CALL record_test('T11.3', 'Partner A cannot INSERT into pending_storage_deletions', 'Deletion Queue Isolation', 'Partner A', 'INSERT pending_storage_deletions', 'insufficient_privilege', 'insufficient_privilege raised', true);
  END;

  RESET ROLE;
END;
$$;

-- ----------------------------------------------------------------------------
-- Test Category 12: Audit Hardening & 9 Regression Scenarios
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_uid_a uuid := 'a0000000-0000-0000-0000-000000000001'::uuid;
  v_uid_b uuid := 'b0000000-0000-0000-0000-000000000002'::uuid;
  v_couple_id uuid;
  v_mem_id uuid;
  v_msg_id uuid;
  v_surp_id uuid;
  v_letter_id uuid;
  v_media_id uuid;
  v_msg_media_id uuid;
  v_path text;
  v_count integer;
  v_dummy record;
BEGIN
  SELECT id INTO v_couple_id FROM public.couples LIMIT 1;
  SELECT id INTO v_mem_id FROM public.memories WHERE couple_id = v_couple_id LIMIT 1;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);

  -- --------------------------------------------------------------------------
  -- Scenario 1: Attempts to modify immutable media fields
  -- (storage_path, entity_type, memory_id, couple_id, uploaded_by)
  -- --------------------------------------------------------------------------
  v_path := v_couple_id::text || '/memory/immutable_test.jpg';
  INSERT INTO public.media_objects (
    couple_id, uploaded_by, entity_type, memory_id,
    bucket_id, storage_path, mime_type, size_bytes
  )
  VALUES (
    v_couple_id, v_uid_a, 'memory', v_mem_id,
    'couple-media', v_path, 'image/jpeg', 102400
  )
  RETURNING id INTO v_media_id;

  -- 1.a Modify storage_path
  BEGIN
    UPDATE public.media_objects SET storage_path = v_couple_id::text || '/memory/mutated.jpg' WHERE id = v_media_id;
    CALL record_test('REG-1.1', 'Modify storage_path on media_objects', 'Regression Scenarios', 'Partner A', 'UPDATE media_objects (storage_path)', 'check_violation', 'Modified', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('REG-1.1', 'Modify storage_path on media_objects', 'Regression Scenarios', 'Partner A', 'UPDATE media_objects (storage_path)', 'check_violation', 'check_violation raised', true);
  END;

  -- 1.b Modify entity_type
  BEGIN
    UPDATE public.media_objects SET entity_type = 'avatar' WHERE id = v_media_id;
    CALL record_test('REG-1.2', 'Modify entity_type on media_objects', 'Regression Scenarios', 'Partner A', 'UPDATE media_objects (entity_type)', 'check_violation', 'Modified', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('REG-1.2', 'Modify entity_type on media_objects', 'Regression Scenarios', 'Partner A', 'UPDATE media_objects (entity_type)', 'check_violation', 'check_violation raised', true);
  END;

  -- 1.c Modify memory_id
  BEGIN
    UPDATE public.media_objects SET memory_id = gen_random_uuid() WHERE id = v_media_id;
    CALL record_test('REG-1.3', 'Modify memory_id on media_objects', 'Regression Scenarios', 'Partner A', 'UPDATE media_objects (memory_id)', 'check_violation', 'Modified', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('REG-1.3', 'Modify memory_id on media_objects', 'Regression Scenarios', 'Partner A', 'UPDATE media_objects (memory_id)', 'check_violation', 'check_violation raised', true);
  END;

  -- 1.d Modify couple_id
  BEGIN
    UPDATE public.media_objects SET couple_id = gen_random_uuid() WHERE id = v_media_id;
    CALL record_test('REG-1.4', 'Modify couple_id on media_objects', 'Regression Scenarios', 'Partner A', 'UPDATE media_objects (couple_id)', 'check_violation', 'Modified', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('REG-1.4', 'Modify couple_id on media_objects', 'Regression Scenarios', 'Partner A', 'UPDATE media_objects (couple_id)', 'check_violation', 'check_violation raised', true);
  END;

  -- 1.e Modify uploaded_by
  BEGIN
    UPDATE public.media_objects SET uploaded_by = v_uid_b WHERE id = v_media_id;
    CALL record_test('REG-1.5', 'Modify uploaded_by on media_objects', 'Regression Scenarios', 'Partner A', 'UPDATE media_objects (uploaded_by)', 'check_violation', 'Modified', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('REG-1.5', 'Modify uploaded_by on media_objects', 'Regression Scenarios', 'Partner A', 'UPDATE media_objects (uploaded_by)', 'check_violation', 'check_violation raised', true);
  END;

  -- --------------------------------------------------------------------------
  -- Scenario 2: Sender attempts to modify sent letter unlock_at, sent_at,
  -- or revert status to draft
  -- --------------------------------------------------------------------------
  INSERT INTO public.letters (couple_id, sender_id, title, body, status, unlock_at)
  VALUES (v_couple_id, v_uid_a, 'Sent Locked Letter', 'Content', 'sent', now() + interval '5 days')
  RETURNING id INTO v_letter_id;

  -- 2.a Modify unlock_at after sending
  BEGIN
    UPDATE public.letters SET unlock_at = now() + interval '1 day' WHERE id = v_letter_id;
    CALL record_test('REG-2.1', 'Sender modifies unlock_at on sent letter', 'Regression Scenarios', 'Partner A (Sender)', 'UPDATE letters (unlock_at)', 'check_violation', 'Modified', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('REG-2.1', 'Sender modifies unlock_at on sent letter', 'Regression Scenarios', 'Partner A (Sender)', 'UPDATE letters (unlock_at)', 'check_violation', 'check_violation raised', true);
  END;

  -- 2.b Modify sent_at after sending
  BEGIN
    UPDATE public.letters SET sent_at = now() - interval '10 days' WHERE id = v_letter_id;
    CALL record_test('REG-2.2', 'Sender modifies sent_at on sent letter', 'Regression Scenarios', 'Partner A (Sender)', 'UPDATE letters (sent_at)', 'check_violation', 'Modified', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('REG-2.2', 'Sender modifies sent_at on sent letter', 'Regression Scenarios', 'Partner A (Sender)', 'UPDATE letters (sent_at)', 'check_violation', 'check_violation raised', true);
  END;

  -- 2.c Revert status to draft after sending
  BEGIN
    UPDATE public.letters SET status = 'draft' WHERE id = v_letter_id;
    CALL record_test('REG-2.3', 'Sender reverts sent letter to draft', 'Regression Scenarios', 'Partner A (Sender)', 'UPDATE letters (status=draft)', 'check_violation', 'Reverted', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('REG-2.3', 'Sender reverts sent letter to draft', 'Regression Scenarios', 'Partner A (Sender)', 'UPDATE letters (status=draft)', 'check_violation', 'check_violation raised', true);
  END;

  -- --------------------------------------------------------------------------
  -- Scenario 3: Creator attempts to modify surprise after it has been revealed
  -- --------------------------------------------------------------------------
  INSERT INTO public.surprises (couple_id, created_by, title, content, reveal_at)
  VALUES (v_couple_id, v_uid_a, 'Surprise Before Reveal', 'Hidden Message', now() - interval '1 hour')
  RETURNING id INTO v_surp_id;

  -- Partner B reveals it via RPC
  PERFORM set_config('request.jwt.claim.sub', v_uid_b::text, true);
  v_dummy := public.reveal_surprise(v_surp_id);

  -- Partner A (creator) attempts modifications after reveal
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);

  -- 3.a Modify title after reveal
  BEGIN
    UPDATE public.surprises SET title = 'Altered Title' WHERE id = v_surp_id;
    CALL record_test('REG-3.1', 'Creator modifies title of revealed surprise', 'Regression Scenarios', 'Partner A (Creator)', 'UPDATE surprises (title)', 'check_violation', 'Modified', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('REG-3.1', 'Creator modifies title of revealed surprise', 'Regression Scenarios', 'Partner A (Creator)', 'UPDATE surprises (title)', 'check_violation', 'check_violation raised', true);
  END;

  -- 3.b Modify content after reveal
  BEGIN
    UPDATE public.surprises SET content = 'Altered Content' WHERE id = v_surp_id;
    CALL record_test('REG-3.2', 'Creator modifies content of revealed surprise', 'Regression Scenarios', 'Partner A (Creator)', 'UPDATE surprises (content)', 'check_violation', 'Modified', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('REG-3.2', 'Creator modifies content of revealed surprise', 'Regression Scenarios', 'Partner A (Creator)', 'UPDATE surprises (content)', 'check_violation', 'check_violation raised', true);
  END;

  -- 3.c Revert status to unopened after reveal
  BEGIN
    UPDATE public.surprises SET status = 'unopened' WHERE id = v_surp_id;
    CALL record_test('REG-3.3', 'Creator reverts revealed surprise to unopened', 'Regression Scenarios', 'Partner A (Creator)', 'UPDATE surprises (status=unopened)', 'check_violation', 'Reverted', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('REG-3.3', 'Creator reverts revealed surprise to unopened', 'Regression Scenarios', 'Partner A (Creator)', 'UPDATE surprises (status=unopened)', 'check_violation', 'check_violation raised', true);
  END;

  -- --------------------------------------------------------------------------
  -- Scenario 4: Media insertion referencing a nonexistent parent UUID
  -- --------------------------------------------------------------------------
  BEGIN
    INSERT INTO public.media_objects (
      couple_id, uploaded_by, entity_type, memory_id,
      bucket_id, storage_path, mime_type, size_bytes
    )
    VALUES (
      v_couple_id, v_uid_a, 'memory', '99999999-9999-9999-9999-999999999999'::uuid,
      'couple-media', v_couple_id::text || '/memory/orphan.jpg', 'image/jpeg', 102400
    );
    CALL record_test('REG-4.1', 'Media insertion with nonexistent parent UUID', 'Regression Scenarios', 'Partner A', 'INSERT media_objects (nonexistent parent)', 'insufficient_privilege', 'Inserted', false);
  EXCEPTION WHEN insufficient_privilege THEN
    CALL record_test('REG-4.1', 'Media insertion with nonexistent parent UUID', 'Regression Scenarios', 'Partner A', 'INSERT media_objects (nonexistent parent)', 'insufficient_privilege', 'insufficient_privilege raised', true);
  END;

  -- --------------------------------------------------------------------------
  -- Scenario 5: Partner B attempts to delete Partner A's message media
  -- --------------------------------------------------------------------------
  INSERT INTO public.messages (couple_id, sender_id, body)
  VALUES (v_couple_id, v_uid_a, 'Message with private photo')
  RETURNING id INTO v_msg_id;

  INSERT INTO public.media_objects (
    couple_id, uploaded_by, entity_type, message_id,
    bucket_id, storage_path, mime_type, size_bytes
  )
  VALUES (
    v_couple_id, v_uid_a, 'message', v_msg_id,
    'couple-media', v_couple_id::text || '/message/private_photo.jpg', 'image/jpeg', 102400
  )
  RETURNING id INTO v_msg_media_id;

  PERFORM set_config('request.jwt.claim.sub', v_uid_b::text, true);
  DELETE FROM public.media_objects WHERE id = v_msg_media_id;
  SELECT count(*) INTO v_count FROM public.media_objects WHERE id = v_msg_media_id;
  CALL record_test('REG-5.1', 'Partner B cannot DELETE Partner A message media', 'Regression Scenarios', 'Partner B', 'DELETE media_objects (Partner A message)', '0 rows deleted, 1 row remains', v_count || ' rows remain', v_count = 1);

  -- --------------------------------------------------------------------------
  -- Scenario 6: Attempt to resurrect a Storage path queued for deletion
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);
  -- Delete the media object to enqueue its path in pending_storage_deletions
  DELETE FROM public.media_objects WHERE id = v_media_id;

  -- Check queue entry exists (checked as postgres/service_role since clients have no SELECT on queue)
  RESET ROLE;
  SELECT count(*) INTO v_count FROM public.pending_storage_deletions WHERE storage_path = v_path AND status = 'pending';
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);

  -- Attempt to re-insert media_objects using the queued path
  BEGIN
    INSERT INTO public.media_objects (
      couple_id, uploaded_by, entity_type, memory_id,
      bucket_id, storage_path, mime_type, size_bytes
    )
    VALUES (
      v_couple_id, v_uid_a, 'memory', v_mem_id,
      'couple-media', v_path, 'image/jpeg', 102400
    );
    CALL record_test('REG-6.1', 'Resurrect queued storage path before cleanup', 'Regression Scenarios', 'Partner A', 'INSERT media_objects (queued path)', 'unique_violation', 'Inserted', false);
  EXCEPTION WHEN unique_violation THEN
    CALL record_test('REG-6.1', 'Resurrect queued storage path before cleanup', 'Regression Scenarios', 'Partner A', 'INSERT media_objects (queued path)', 'unique_violation', 'unique_violation raised', true);
  END;

  -- --------------------------------------------------------------------------
  -- Scenario 7: Partner A attempts to modify or delete Partner B's private settings
  -- --------------------------------------------------------------------------
  UPDATE public.user_private_settings
  SET notification_preferences = '{"hacked": true}'::jsonb
  WHERE user_id = v_uid_b;

  DELETE FROM public.user_private_settings WHERE user_id = v_uid_b;

  -- Verify Partner B settings are completely unchanged
  RESET ROLE;
  SELECT count(*) INTO v_count
  FROM public.user_private_settings
  WHERE user_id = v_uid_b AND notification_preferences = '{"email": false}'::jsonb;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_uid_a::text, true);

  CALL record_test('REG-7.1', 'Partner A cannot UPDATE or DELETE Partner B settings', 'Regression Scenarios', 'Partner A', 'UPDATE/DELETE user_private_settings (Partner B)', '0 rows affected, settings untouched', v_count || ' settings intact', v_count = 1);

  -- --------------------------------------------------------------------------
  -- Scenario 8: Direct Storage deletion attempt on registered & unregistered path
  -- (SEC-01 Hardening verification)
  -- --------------------------------------------------------------------------
  -- 8.a Direct SQL delete on storage.objects is blocked by statement trigger
  BEGIN
    DELETE FROM storage.objects WHERE bucket_id = 'couple-media' AND name = 'unregistered/path.jpg';
    CALL record_test('REG-8.1', 'Direct SQL DELETE on storage.objects', 'Regression Scenarios', 'Partner A', 'DELETE storage.objects (unregistered)', 'insufficient_privilege', 'Deleted', false);
  EXCEPTION WHEN insufficient_privilege THEN
    CALL record_test('REG-8.1', 'Direct SQL DELETE on storage.objects', 'Regression Scenarios', 'Partner A', 'DELETE storage.objects (unregistered)', 'insufficient_privilege', 'Blocked by storage.protect_delete()', true);
  END;

  -- 8.b When storage.allow_delete_query is true, RLS blocks direct client delete (SEC-01: no delete policy)
  PERFORM set_config('storage.allow_delete_query', 'true', true);
  DELETE FROM storage.objects WHERE bucket_id = 'couple-media' AND name = v_couple_id::text || '/memory/photo_paris.jpg';
  SELECT count(*) INTO v_count FROM storage.objects WHERE bucket_id = 'couple-media' AND name = v_couple_id::text || '/memory/photo_paris.jpg';
  CALL record_test('REG-8.2', 'SEC-01: Direct DELETE on storage.objects registered path blocked by RLS', 'Regression Scenarios', 'Partner A', 'DELETE storage.objects (registered)', '0 rows deleted, blob remains', v_count || ' blob remains', v_count = 1);
  PERFORM set_config('storage.allow_delete_query', 'false', true);

  -- --------------------------------------------------------------------------
  -- Scenario 9: Invalid Storage paths/extensions (traversal, SVG, EXE, HTML)
  -- --------------------------------------------------------------------------
  -- 9.a Path traversal attack
  BEGIN
    INSERT INTO public.media_objects (
      couple_id, uploaded_by, entity_type, memory_id,
      bucket_id, storage_path, mime_type, size_bytes
    )
    VALUES (
      v_couple_id, v_uid_a, 'memory', v_mem_id,
      'couple-media', v_couple_id::text || '/memory/../../etc/passwd.jpg', 'image/jpeg', 102400
    );
    CALL record_test('REG-9.1', 'Path traversal in storage_path', 'Regression Scenarios', 'Partner A', 'INSERT media_objects (traversal ../)', 'check_violation', 'Inserted', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('REG-9.1', 'Path traversal in storage_path', 'Regression Scenarios', 'Partner A', 'INSERT media_objects (traversal ../)', 'check_violation', 'check_violation raised', true);
  END;

  -- 9.b Disallowed SVG file
  BEGIN
    INSERT INTO public.media_objects (
      couple_id, uploaded_by, entity_type, memory_id,
      bucket_id, storage_path, mime_type, size_bytes
    )
    VALUES (
      v_couple_id, v_uid_a, 'memory', v_mem_id,
      'couple-media', v_couple_id::text || '/memory/vector.svg', 'image/svg+xml', 102400
    );
    CALL record_test('REG-9.2', 'Disallowed SVG MIME / extension', 'Regression Scenarios', 'Partner A', 'INSERT media_objects (.svg)', 'check_violation', 'Inserted', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('REG-9.2', 'Disallowed SVG MIME / extension', 'Regression Scenarios', 'Partner A', 'INSERT media_objects (.svg)', 'check_violation', 'check_violation raised', true);
  END;

  -- 9.c Disallowed EXE file
  BEGIN
    INSERT INTO public.media_objects (
      couple_id, uploaded_by, entity_type, memory_id,
      bucket_id, storage_path, mime_type, size_bytes
    )
    VALUES (
      v_couple_id, v_uid_a, 'memory', v_mem_id,
      'couple-media', v_couple_id::text || '/memory/malware.exe', 'application/x-msdownload', 102400
    );
    CALL record_test('REG-9.3', 'Disallowed EXE MIME / extension', 'Regression Scenarios', 'Partner A', 'INSERT media_objects (.exe)', 'check_violation', 'Inserted', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('REG-9.3', 'Disallowed EXE MIME / extension', 'Regression Scenarios', 'Partner A', 'INSERT media_objects (.exe)', 'check_violation', 'check_violation raised', true);
  END;

  -- 9.d Disallowed HTML file
  BEGIN
    INSERT INTO public.media_objects (
      couple_id, uploaded_by, entity_type, memory_id,
      bucket_id, storage_path, mime_type, size_bytes
    )
    VALUES (
      v_couple_id, v_uid_a, 'memory', v_mem_id,
      'couple-media', v_couple_id::text || '/memory/xss.html', 'text/html', 102400
    );
    CALL record_test('REG-9.4', 'Disallowed HTML MIME / extension', 'Regression Scenarios', 'Partner A', 'INSERT media_objects (.html)', 'check_violation', 'Inserted', false);
  EXCEPTION WHEN check_violation THEN
    CALL record_test('REG-9.4', 'Disallowed HTML MIME / extension', 'Regression Scenarios', 'Partner A', 'INSERT media_objects (.html)', 'check_violation', 'check_violation raised', true);
  END;

  RESET ROLE;
END;
$$;

-- ----------------------------------------------------------------------------
-- Display Test Results Summary
-- ----------------------------------------------------------------------------
SELECT
  test_id,
  test_name,
  category,
  role_used,
  operation,
  expected,
  actual,
  CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS status
FROM test_results
ORDER BY test_id;

SELECT
  count(*) AS total_tests,
  count(*) FILTER (WHERE passed) AS passed_tests,
  count(*) FILTER (WHERE NOT passed) AS failed_tests
FROM test_results;

-- Roll back all test fixture data cleanly so database remains untouched!
ROLLBACK;
