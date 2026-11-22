-- ============================================================================
-- Migration: 0001_core_couple_schema.sql
-- Purpose:   Core identity, private user settings, single couple space,
--            and race-condition-safe two-member enforcement for TwoFold.
-- Notes:
--   - Row Level Security (RLS) is enabled fail-closed on every table here;
--     RLS policies and Storage bucket policies are intentionally deferred to
--     Task 1.4.
--   - Location-sharing tables are intentionally omitted from the MVP schema.
--   - All timestamps use timestamptz (UTC) and are server-enforced on INSERT
--     and UPDATE; calendar dates use date.
--   - Avatar media is linked relationally via public.media_objects.profile_id
--     in 0002_mvp_feature_tables.sql (no free-form avatar_path on profiles).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. profiles
-- Shared couple-visible identity attributes only (never store secrets or
-- private notification/read-cursor state here).
-- Avatar media is owned via public.media_objects (entity_type = 'avatar',
-- profile_id -> profiles.id) to avoid circular FKs and arbitrary paths.
-- ----------------------------------------------------------------------------
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  display_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT profiles_display_name_length
    CHECK (
      char_length(display_name) BETWEEN 1 AND 80
      AND display_name !~ '^[[:space:]]*$'
    )
);

COMMENT ON TABLE public.profiles IS
  'Couple-visible member profile details. Kept separate from user_private_settings; avatar files link via media_objects.profile_id.';

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.enforce_profile_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := pg_catalog.now();
    NEW.updated_at := pg_catalog.now();
    RETURN NEW;
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Immutable columns on profiles cannot be modified.'
      USING ERRCODE = 'check_violation';
  END IF;

  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_profile_lifecycle() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_profiles_lifecycle
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_profile_lifecycle();

-- ----------------------------------------------------------------------------
-- 2. user_private_settings
-- Strictly per-user private preferences and chat unread cursor.
-- Isolated from profiles so chat_last_seen_at is never exposed as a read
-- receipt to the other partner.
-- ----------------------------------------------------------------------------
CREATE TABLE public.user_private_settings (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  chat_last_seen_at timestamptz,
  notification_preferences jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_private_settings_notif_is_object
    CHECK (
      jsonb_typeof(notification_preferences) = 'object'
      AND octet_length(notification_preferences::text) <= 8192
    )
);

COMMENT ON TABLE public.user_private_settings IS
  'Per-user private preferences and unread cursor; never readable by the other partner.';

ALTER TABLE public.user_private_settings ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.enforce_user_private_settings_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := pg_catalog.now();
    NEW.updated_at := pg_catalog.now();
    RETURN NEW;
  END IF;

  IF NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Immutable columns on user_private_settings cannot be modified.'
      USING ERRCODE = 'check_violation';
  END IF;

  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_user_private_settings_lifecycle() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_user_private_settings_lifecycle
  BEFORE INSERT OR UPDATE ON public.user_private_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_user_private_settings_lifecycle();

-- ----------------------------------------------------------------------------
-- 3. couples
-- Single private couple space for the TwoFold MVP.
-- The singleton_key constraint guarantees only one couple space can exist in
-- this MVP database, eliminating multi-tenant / rogue-space creation risks.
-- ----------------------------------------------------------------------------
CREATE TABLE public.couples (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  singleton_key boolean NOT NULL DEFAULT true,
  space_name text NOT NULL DEFAULT 'TwoFold',
  anniversary_date date,
  display_preferences jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT couples_singleton_true
    CHECK (singleton_key = true),
  CONSTRAINT couples_singleton_unique
    UNIQUE (singleton_key),
  CONSTRAINT couples_space_name_length
    CHECK (
      char_length(space_name) BETWEEN 1 AND 100
      AND space_name !~ '^[[:space:]]*$'
    ),
  CONSTRAINT couples_display_preferences_is_object
    CHECK (
      jsonb_typeof(display_preferences) = 'object'
      AND octet_length(display_preferences::text) <= 8192
    )
);

COMMENT ON TABLE public.couples IS
  'Single shared couple space for TwoFold MVP, guarded by singleton_key.';

ALTER TABLE public.couples ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.enforce_couple_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := pg_catalog.now();
    NEW.updated_at := pg_catalog.now();
    RETURN NEW;
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.singleton_key IS DISTINCT FROM OLD.singleton_key
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Immutable columns on couples cannot be modified.'
      USING ERRCODE = 'check_violation';
  END IF;

  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_couple_lifecycle() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_couples_lifecycle
  BEFORE INSERT OR UPDATE ON public.couples
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_couple_lifecycle();

-- ----------------------------------------------------------------------------
-- 4. couple_members
-- Maps the exactly two authorized accounts ('owner' and 'partner') to the
-- couple space.
--
-- Two-member concurrency safety (defense in depth):
--   1. CHECK (role IN ('owner', 'partner')) + UNIQUE (couple_id, role)
--      structurally guarantees at the B-tree index level that no couple can
--      ever have more than 2 rows, even under concurrent transactions.
--   2. UNIQUE (user_id) guarantees a user can belong to at most one couple.
--   3. BEFORE INSERT SECURITY DEFINER trigger acquires FOR UPDATE lock on the
--      parent couples row, stamps server joined_at, and validates member
--      count < 2 regardless of caller RLS visibility.
--   4. BEFORE UPDATE trigger locks all membership columns (including id)
--      immutable.
-- ----------------------------------------------------------------------------
CREATE TABLE public.couple_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couples (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  role text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  joined_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT couple_members_role_valid
    CHECK (role IN ('owner', 'partner')),
  CONSTRAINT couple_members_status_valid
    CHECK (status IN ('active')),
  CONSTRAINT couple_members_unique_couple_role
    UNIQUE (couple_id, role),
  CONSTRAINT couple_members_unique_user
    UNIQUE (user_id)
);

COMMENT ON TABLE public.couple_members IS
  'Authorized membership table enforcing at most two active users (owner + partner) per couple.';

ALTER TABLE public.couple_members ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.enforce_max_two_couple_members()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_member_count integer;
BEGIN
  -- Always stamp membership join time from the database server clock.
  NEW.joined_at := pg_catalog.now();

  -- Serialize concurrent membership inserts against the parent couple row.
  PERFORM 1
  FROM public.couples AS c
  WHERE c.id = NEW.couple_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target couple space does not exist.'
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  SELECT pg_catalog.count(*)
  INTO v_member_count
  FROM public.couple_members AS cm
  WHERE cm.couple_id = NEW.couple_id;

  IF v_member_count >= 2 THEN
    RAISE EXCEPTION 'TwoFold couple spaces are strictly limited to two authorized members.'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_max_two_couple_members() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_couple_members_enforce_limit
  BEFORE INSERT ON public.couple_members
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_max_two_couple_members();

CREATE OR REPLACE FUNCTION public.prevent_couple_member_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.couple_id IS DISTINCT FROM OLD.couple_id
     OR NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.role IS DISTINCT FROM OLD.role
     OR NEW.status IS DISTINCT FROM OLD.status
     OR NEW.joined_at IS DISTINCT FROM OLD.joined_at THEN
    RAISE EXCEPTION 'Couple membership records are immutable.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.prevent_couple_member_mutation() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_couple_members_immutable
  BEFORE UPDATE ON public.couple_members
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_couple_member_mutation();
