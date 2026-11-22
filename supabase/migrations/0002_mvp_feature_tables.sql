-- ============================================================================
-- Migration: 0002_mvp_feature_tables.sql
-- Purpose:   MVP feature tables, relational integrity, immutability triggers,
--            server-time lifecycle guards, locked-content preview RPCs,
--            reveal_surprise() RPC, media metadata, and pending Storage
--            deletion queue for TwoFold.
-- Depends:   0001_core_couple_schema.sql
-- Notes:
--   - Row Level Security (RLS) is enabled fail-closed on every table here;
--     RLS policies and Storage bucket policies are intentionally deferred to
--     Task 1.4.
--   - Locked-content RLS + RPC contract for Task 1.4:
--       * public.letters SELECT policy: allow sender always; allow partner
--         only when status = 'sent' AND (unlock_at IS NULL OR now() >= unlock_at).
--         Locked received-letter envelope cards are fetched via
--         public.get_couple_letters_preview(), which masks body as NULL while
--         locked and never returns the partner's drafts.
--       * public.surprises SELECT policy: allow creator always; allow partner
--         only when status = 'revealed' AND (reveal_at IS NULL OR now() >= reveal_at).
--         public.surprises UPDATE policy: strictly creator-only.
--         Locked/unopened surprise cards are fetched via
--         public.get_couple_surprises_preview(), which masks content as NULL
--         until revealed; recipients open ready surprises exclusively via
--         public.reveal_surprise(p_surprise_id).
--       * public.media_objects SELECT policy (and Storage bucket RLS): for
--         entity_type = 'surprise', allow non-creator access ONLY when the
--         parent surprise is revealed AND (reveal_at IS NULL OR now() >= reveal_at).
--       * public.pending_storage_deletions: deny all direct anon/authenticated
--         table access; process strictly server-side using service_role.
--   - Deleting a parent record cascades media_objects rows, whose AFTER DELETE
--     trigger records every storage_path in pending_storage_deletions so
--     private Storage blobs can be reliably deleted via Supabase Storage API.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. date_plans (shared edit/delete ownership enforced in Task 1.4 RLS)
-- ----------------------------------------------------------------------------
CREATE TABLE public.date_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couples (id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
  title text NOT NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz,
  location_text text,
  notes text,
  budget numeric(10, 2),
  status text NOT NULL DEFAULT 'proposed',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT date_plans_title_length
    CHECK (
      char_length(title) BETWEEN 1 AND 160
      AND title !~ '^[[:space:]]*$'
    ),
  CONSTRAINT date_plans_ends_after_starts
    CHECK (ends_at IS NULL OR ends_at >= starts_at),
  CONSTRAINT date_plans_location_length
    CHECK (
      location_text IS NULL
      OR (char_length(location_text) BETWEEN 1 AND 240 AND location_text !~ '^[[:space:]]*$')
    ),
  CONSTRAINT date_plans_notes_length
    CHECK (
      notes IS NULL
      OR (char_length(notes) BETWEEN 1 AND 4000 AND notes !~ '^[[:space:]]*$')
    ),
  CONSTRAINT date_plans_budget_non_negative
    CHECK (budget IS NULL OR budget >= 0),
  CONSTRAINT date_plans_status_valid
    CHECK (status IN ('proposed', 'planned', 'completed', 'cancelled'))
);

COMMENT ON TABLE public.date_plans IS
  'Shared date plans. Both active couple members may edit or delete.';

ALTER TABLE public.date_plans ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_date_plans_couple_starts_at
  ON public.date_plans (couple_id, starts_at ASC);

CREATE INDEX idx_date_plans_couple_status
  ON public.date_plans (couple_id, status);

CREATE INDEX idx_date_plans_created_by
  ON public.date_plans (created_by);

CREATE OR REPLACE FUNCTION public.enforce_date_plan_lifecycle()
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
     OR NEW.couple_id IS DISTINCT FROM OLD.couple_id
     OR NEW.created_by IS DISTINCT FROM OLD.created_by
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Immutable columns on date_plans cannot be modified.'
      USING ERRCODE = 'check_violation';
  END IF;

  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_date_plan_lifecycle() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_date_plans_lifecycle
  BEFORE INSERT OR UPDATE ON public.date_plans
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_date_plan_lifecycle();

-- ----------------------------------------------------------------------------
-- 2. memories (shared edit/delete ownership enforced in Task 1.4 RLS)
-- Deleting a linked date plan preserves the memory (ON DELETE SET NULL).
-- ----------------------------------------------------------------------------
CREATE TABLE public.memories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couples (id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
  date_plan_id uuid REFERENCES public.date_plans (id) ON DELETE SET NULL,
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  event_date date NOT NULL,
  category text NOT NULL DEFAULT 'moment',
  location_text text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT memories_title_length
    CHECK (
      char_length(title) BETWEEN 1 AND 160
      AND title !~ '^[[:space:]]*$'
    ),
  CONSTRAINT memories_description_length
    CHECK (char_length(description) <= 10000),
  CONSTRAINT memories_category_length
    CHECK (
      char_length(category) BETWEEN 1 AND 60
      AND category !~ '^[[:space:]]*$'
    ),
  CONSTRAINT memories_location_length
    CHECK (
      location_text IS NULL
      OR (char_length(location_text) BETWEEN 1 AND 240 AND location_text !~ '^[[:space:]]*$')
    )
);

COMMENT ON TABLE public.memories IS
  'Shared relationship memories. Both active couple members may edit or delete.';

ALTER TABLE public.memories ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_memories_couple_event_date
  ON public.memories (couple_id, event_date DESC, created_at DESC);

CREATE INDEX idx_memories_couple_category
  ON public.memories (couple_id, category);

CREATE INDEX idx_memories_date_plan_id
  ON public.memories (date_plan_id)
  WHERE date_plan_id IS NOT NULL;

CREATE INDEX idx_memories_created_by
  ON public.memories (created_by);

CREATE OR REPLACE FUNCTION public.validate_memory_integrity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_plan_couple_id uuid;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := pg_catalog.now();
    NEW.updated_at := pg_catalog.now();
  ELSE
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.couple_id IS DISTINCT FROM OLD.couple_id
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Immutable columns on memories cannot be modified.'
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.updated_at := pg_catalog.now();
  END IF;

  IF NEW.date_plan_id IS NOT NULL THEN
    SELECT dp.couple_id
    INTO v_plan_couple_id
    FROM public.date_plans AS dp
    WHERE dp.id = NEW.date_plan_id;

    IF v_plan_couple_id IS DISTINCT FROM NEW.couple_id THEN
      RAISE EXCEPTION 'Linked date plan must belong to the same couple space.'
        USING ERRCODE = 'foreign_key_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_memory_integrity() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_memories_validate_integrity
  BEFORE INSERT OR UPDATE ON public.memories
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_memory_integrity();

-- ----------------------------------------------------------------------------
-- 3. messages (creator-only edit/delete enforced in Task 1.4 RLS)
-- ----------------------------------------------------------------------------
CREATE TABLE public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couples (id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT messages_body_length
    CHECK (
      char_length(body) BETWEEN 1 AND 4000
      AND body !~ '^[[:space:]]*$'
    )
);

COMMENT ON TABLE public.messages IS
  'Private couple chat messages. Only the sender may edit or delete.';

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_messages_couple_created_at
  ON public.messages (couple_id, created_at DESC);

CREATE INDEX idx_messages_sender_id
  ON public.messages (sender_id);

CREATE OR REPLACE FUNCTION public.enforce_message_lifecycle()
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
     OR NEW.couple_id IS DISTINCT FROM OLD.couple_id
     OR NEW.sender_id IS DISTINCT FROM OLD.sender_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Immutable columns on messages cannot be modified.'
      USING ERRCODE = 'check_violation';
  END IF;

  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_message_lifecycle() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_messages_lifecycle
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_message_lifecycle();

-- ----------------------------------------------------------------------------
-- 4. letters (creator-only edit/delete + server-time unlock integrity)
-- Supports drafts (private to sender) and sent letters (optional unlock_at).
-- Once sent, sent_at is server-stamped and unlock_at becomes immutable so
-- scheduled locks cannot be tampered with.
-- ----------------------------------------------------------------------------
CREATE TABLE public.letters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couples (id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
  title text NOT NULL,
  body text NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  unlock_at timestamptz,
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT letters_title_length
    CHECK (
      char_length(title) BETWEEN 1 AND 160
      AND title !~ '^[[:space:]]*$'
    ),
  CONSTRAINT letters_body_length
    CHECK (
      char_length(body) BETWEEN 1 AND 20000
      AND body !~ '^[[:space:]]*$'
    ),
  CONSTRAINT letters_status_valid
    CHECK (status IN ('draft', 'sent')),
  CONSTRAINT letters_sent_at_matches_status
    CHECK (
      (status = 'draft' AND sent_at IS NULL) OR
      (status = 'sent' AND sent_at IS NOT NULL)
    )
);

COMMENT ON TABLE public.letters IS
  'Love letters supporting drafts and server-time-locked delivery. Creator-only edit/delete.';

ALTER TABLE public.letters ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_letters_couple_status_created
  ON public.letters (couple_id, status, created_at DESC);

CREATE INDEX idx_letters_couple_sent_at
  ON public.letters (couple_id, sent_at DESC)
  WHERE status = 'sent';

CREATE INDEX idx_letters_sender_id
  ON public.letters (sender_id);

CREATE INDEX idx_letters_couple_unlock_at
  ON public.letters (couple_id, unlock_at)
  WHERE status = 'sent' AND unlock_at IS NOT NULL;

CREATE OR REPLACE FUNCTION public.enforce_letter_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := pg_catalog.now();
    NEW.updated_at := pg_catalog.now();
    IF NEW.status = 'sent' THEN
      NEW.sent_at := pg_catalog.now();
    ELSE
      NEW.sent_at := NULL;
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE rules
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.couple_id IS DISTINCT FROM OLD.couple_id
     OR NEW.sender_id IS DISTINCT FROM OLD.sender_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Immutable columns on letters cannot be modified.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF OLD.status = 'sent' THEN
    IF NEW.status IS DISTINCT FROM 'sent' THEN
      RAISE EXCEPTION 'Sent letters cannot be reverted to draft.'
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.sent_at IS DISTINCT FROM OLD.sent_at THEN
      RAISE EXCEPTION 'sent_at cannot be modified once a letter is sent.'
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.unlock_at IS DISTINCT FROM OLD.unlock_at THEN
      RAISE EXCEPTION 'Scheduled unlock_at cannot be altered after a letter is sent.'
        USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    -- OLD.status = 'draft'
    IF NEW.status = 'sent' THEN
      NEW.sent_at := pg_catalog.now();
    ELSE
      NEW.sent_at := NULL;
    END IF;
  END IF;

  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_letter_lifecycle() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_letters_lifecycle
  BEFORE INSERT OR UPDATE ON public.letters
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_letter_lifecycle();

-- Restricted metadata-only preview RPC for letters:
-- Allows the UI to render locked envelope cards (title, sender, unlock_at)
-- while Task 1.4 RLS denies direct table SELECT on locked received rows.
-- Body is strictly masked to NULL for locked received letters, and partner
-- drafts are never returned.
CREATE OR REPLACE FUNCTION public.get_couple_letters_preview()
RETURNS TABLE (
  id uuid,
  couple_id uuid,
  sender_id uuid,
  title text,
  body text,
  status text,
  unlock_at timestamptz,
  sent_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  is_locked boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;
  v_couple_id uuid;
  v_now timestamptz;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT cm.couple_id
  INTO v_couple_id
  FROM public.couple_members AS cm
  WHERE cm.user_id = v_user_id
    AND cm.status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active couple membership is required.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_now := pg_catalog.now();

  RETURN QUERY
  SELECT
    l.id,
    l.couple_id,
    l.sender_id,
    l.title,
    CASE
      WHEN l.sender_id = v_user_id
        OR (l.status = 'sent' AND (l.unlock_at IS NULL OR v_now >= l.unlock_at))
      THEN l.body
      ELSE NULL
    END AS body,
    l.status,
    l.unlock_at,
    l.sent_at,
    l.created_at,
    l.updated_at,
    (l.status = 'sent' AND l.unlock_at IS NOT NULL AND v_now < l.unlock_at) AS is_locked
  FROM public.letters AS l
  WHERE l.couple_id = v_couple_id
    AND (l.sender_id = v_user_id OR l.status = 'sent')
  ORDER BY COALESCE(l.sent_at, l.created_at) DESC, l.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_couple_letters_preview() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_couple_letters_preview() TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. surprises (creator-only direct edit/delete + server-time reveal guard)
-- reveal_at is immutable once created. Recipients cannot directly UPDATE rows;
-- they reveal ready surprises exclusively via public.reveal_surprise().
-- ----------------------------------------------------------------------------
CREATE TABLE public.surprises (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couples (id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
  title text NOT NULL,
  content text NOT NULL,
  reveal_at timestamptz,
  status text NOT NULL DEFAULT 'unopened',
  revealed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT surprises_title_length
    CHECK (
      char_length(title) BETWEEN 1 AND 160
      AND title !~ '^[[:space:]]*$'
    ),
  CONSTRAINT surprises_content_length
    CHECK (
      char_length(content) BETWEEN 1 AND 10000
      AND content !~ '^[[:space:]]*$'
    ),
  CONSTRAINT surprises_status_valid
    CHECK (status IN ('unopened', 'revealed')),
  CONSTRAINT surprises_revealed_at_matches_status
    CHECK (
      (status = 'unopened' AND revealed_at IS NULL) OR
      (status = 'revealed' AND revealed_at IS NOT NULL)
    ),
  CONSTRAINT surprises_revealed_not_before_reveal_at
    CHECK (
      revealed_at IS NULL
      OR reveal_at IS NULL
      OR revealed_at >= reveal_at
    )
);

COMMENT ON TABLE public.surprises IS
  'Private surprises with immutable reveal_at and server-enforced reveal_surprise() transition.';

ALTER TABLE public.surprises ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_surprises_couple_created
  ON public.surprises (couple_id, created_at DESC);

CREATE INDEX idx_surprises_couple_unopened_reveal
  ON public.surprises (couple_id, reveal_at)
  WHERE status = 'unopened';

CREATE INDEX idx_surprises_created_by
  ON public.surprises (created_by);

CREATE OR REPLACE FUNCTION public.enforce_surprise_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_actor_id uuid;
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Surprises always start unopened; timestamps are strictly server-controlled.
    NEW.created_at := pg_catalog.now();
    NEW.updated_at := pg_catalog.now();
    NEW.status := 'unopened';
    NEW.revealed_at := NULL;
    RETURN NEW;
  END IF;

  -- UPDATE rules: identity, timestamps, and scheduled reveal_at are immutable.
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.couple_id IS DISTINCT FROM OLD.couple_id
     OR NEW.created_by IS DISTINCT FROM OLD.created_by
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.reveal_at IS DISTINCT FROM OLD.reveal_at THEN
    RAISE EXCEPTION 'Immutable columns on surprises (including reveal_at) cannot be modified.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF OLD.status = 'revealed' THEN
    IF NEW.status IS DISTINCT FROM 'revealed'
       OR NEW.revealed_at IS DISTINCT FROM OLD.revealed_at THEN
      RAISE EXCEPTION 'Revealed surprises cannot have their reveal state modified.'
        USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.title IS DISTINCT FROM OLD.title
       OR NEW.content IS DISTINCT FROM OLD.content THEN
      RAISE EXCEPTION 'Revealed surprises cannot have their title or content modified.'
        USING ERRCODE = 'check_violation';
    END IF;
  ELSIF NEW.status = 'revealed' THEN
    v_actor_id := auth.uid();

    IF v_actor_id IS NOT NULL AND v_actor_id = OLD.created_by THEN
      RAISE EXCEPTION 'Only the recipient partner can reveal a surprise.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NEW.title IS DISTINCT FROM OLD.title
       OR NEW.content IS DISTINCT FROM OLD.content THEN
      RAISE EXCEPTION 'Surprise title and content cannot be modified during reveal.'
        USING ERRCODE = 'check_violation';
    END IF;

    -- Server-time enforcement: block reveal before reveal_at.
    IF OLD.reveal_at IS NOT NULL AND pg_catalog.now() < OLD.reveal_at THEN
      RAISE EXCEPTION 'This surprise cannot be revealed before its scheduled reveal_at time.'
        USING ERRCODE = 'check_violation';
    END IF;

    NEW.revealed_at := pg_catalog.now();
  ELSE
    NEW.revealed_at := NULL;
  END IF;

  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_surprise_lifecycle() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_surprises_lifecycle
  BEFORE INSERT OR UPDATE ON public.surprises
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_surprise_lifecycle();

-- Restricted metadata-only preview RPC for surprises:
-- Allows the UI to render pending/unopened surprise cards (title, sender,
-- reveal_at, lock/ready flags) while Task 1.4 RLS denies direct table SELECT
-- on unopened rows and surprise media_objects. Content is strictly NULL for
-- the recipient until the surprise is revealed at or after reveal_at.
CREATE OR REPLACE FUNCTION public.get_couple_surprises_preview()
RETURNS TABLE (
  id uuid,
  couple_id uuid,
  created_by uuid,
  title text,
  content text,
  reveal_at timestamptz,
  status text,
  revealed_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  is_locked boolean,
  is_ready_to_reveal boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;
  v_couple_id uuid;
  v_now timestamptz;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT cm.couple_id
  INTO v_couple_id
  FROM public.couple_members AS cm
  WHERE cm.user_id = v_user_id
    AND cm.status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active couple membership is required.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_now := pg_catalog.now();

  RETURN QUERY
  SELECT
    s.id,
    s.couple_id,
    s.created_by,
    s.title,
    CASE
      WHEN s.created_by = v_user_id
        OR (s.status = 'revealed' AND (s.reveal_at IS NULL OR v_now >= s.reveal_at))
      THEN s.content
      ELSE NULL
    END AS content,
    s.reveal_at,
    s.status,
    s.revealed_at,
    s.created_at,
    s.updated_at,
    (s.status = 'unopened' AND s.reveal_at IS NOT NULL AND v_now < s.reveal_at) AS is_locked,
    (s.status = 'unopened' AND (s.reveal_at IS NULL OR v_now >= s.reveal_at)) AS is_ready_to_reveal
  FROM public.surprises AS s
  WHERE s.couple_id = v_couple_id
  ORDER BY s.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_couple_surprises_preview() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_couple_surprises_preview() TO authenticated;

-- Dedicated narrow RPC allowing only the recipient active couple member to
-- reveal an unopened surprise once PostgreSQL server time reaches reveal_at.
-- Keeps direct UPDATE RLS on public.surprises strictly creator-only.
CREATE OR REPLACE FUNCTION public.reveal_surprise(p_surprise_id uuid)
RETURNS public.surprises
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;
  v_couple_id uuid;
  v_surprise public.surprises;
BEGIN
  IF p_surprise_id IS NULL THEN
    RAISE EXCEPTION 'Surprise ID is required.'
      USING ERRCODE = 'not_null_violation';
  END IF;

  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT cm.couple_id
  INTO v_couple_id
  FROM public.couple_members AS cm
  WHERE cm.user_id = v_user_id
    AND cm.status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active couple membership is required.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT s.*
  INTO v_surprise
  FROM public.surprises AS s
  WHERE s.id = p_surprise_id
    AND s.couple_id = v_couple_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Surprise not found or access denied.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_surprise.created_by = v_user_id THEN
    RAISE EXCEPTION 'Only the recipient partner can reveal a surprise.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Idempotent if already revealed (e.g., double-tap on mobile).
  IF v_surprise.status = 'revealed' THEN
    RETURN v_surprise;
  END IF;

  IF v_surprise.reveal_at IS NOT NULL AND pg_catalog.now() < v_surprise.reveal_at THEN
    RAISE EXCEPTION 'This surprise cannot be revealed before its scheduled reveal_at time.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.surprises AS s
  SET status = 'revealed'
  WHERE s.id = v_surprise.id
  RETURNING s.*
  INTO v_surprise;

  RETURN v_surprise;
END;
$$;

REVOKE ALL ON FUNCTION public.reveal_surprise(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reveal_surprise(uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- 6. pending_storage_deletions
-- Durable cleanup queue for private Supabase Storage objects.
-- Created before media_objects triggers so media_objects INSERT validation
-- can reject reuse of any path currently queued for deletion.
--
-- Note: couple_id is stored as a plain audit/scoping UUID without a foreign
-- key back to public.couples so that:
--   1. Deleting a couple space cascades media_objects and still allows the
--      AFTER DELETE trigger to enqueue every storage_path without hitting a
--      foreign-key violation on the deleted couple row.
--   2. Queued storage paths survive couple teardown and auth.users deletion
--      until Storage blobs are confirmed deleted.
--
-- Worker concurrency & retry model (server-side service_role only):
--   - Claim rows via UPDATE ... FOR UPDATE SKIP LOCKED into status='processing'
--     with locked_at=now(), releasing DB locks before calling Storage HTTP API.
--   - On success (or 404 already missing): status='completed', locked_at=NULL,
--     processed_at=now(), last_error=NULL.
--   - On transient failure: status='failed', locked_at=NULL, attempts=attempts+1,
--     next_retry_at=now()+backoff, last_error=... (or status='abandoned' with
--     processed_at=now() once max attempts are exhausted).
--   - Crashed workers are reclaimed using idx_pending_storage_deletions_processing_lease
--     when status='processing' AND locked_at < now() - lease_timeout.
-- ----------------------------------------------------------------------------
CREATE TABLE public.pending_storage_deletions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL,
  bucket_id text NOT NULL DEFAULT 'couple-media',
  storage_path text NOT NULL,
  entity_type text NOT NULL,
  original_uploader_id uuid,
  requested_by uuid,
  status text NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  last_error text,
  locked_at timestamptz,
  next_retry_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  CONSTRAINT pending_storage_deletions_bucket_valid
    CHECK (bucket_id = 'couple-media'),
  CONSTRAINT pending_storage_deletions_entity_type_valid
    CHECK (entity_type IN ('memory', 'surprise', 'message', 'avatar')),
  CONSTRAINT pending_storage_deletions_path_valid
    CHECK (
      char_length(storage_path) BETWEEN 1 AND 512
      AND storage_path LIKE couple_id::text || '/' || entity_type || '/%'
      AND storage_path ~ '^[0-9a-f-]+/(memory|surprise|message|avatar)/[A-Za-z0-9._/-]+$'
      AND storage_path ~ '[A-Za-z0-9_-]\.(jpg|jpeg|png|webp)$'
      AND storage_path NOT LIKE '%//%'
      AND storage_path NOT LIKE '%/'
      AND storage_path !~ '(^|/)\.\.?(/|$)'
    ),
  CONSTRAINT pending_storage_deletions_status_valid
    CHECK (status IN ('pending', 'processing', 'failed', 'completed', 'abandoned')),
  CONSTRAINT pending_storage_deletions_attempts_non_negative
    CHECK (attempts >= 0),
  CONSTRAINT pending_storage_deletions_last_error_length
    CHECK (last_error IS NULL OR char_length(last_error) <= 2000),
  CONSTRAINT pending_storage_deletions_locked_matches_status
    CHECK (
      (status = 'processing' AND locked_at IS NOT NULL) OR
      (status <> 'processing' AND locked_at IS NULL)
    ),
  CONSTRAINT pending_storage_deletions_processed_matches_status
    CHECK (
      (status IN ('completed', 'abandoned') AND processed_at IS NOT NULL) OR
      (status IN ('pending', 'processing', 'failed') AND processed_at IS NULL)
    )
);

COMMENT ON TABLE public.pending_storage_deletions IS
  'Durable server-side cleanup queue for private Storage blobs awaiting confirmed deletion via Storage API.';

ALTER TABLE public.pending_storage_deletions ENABLE ROW LEVEL SECURITY;

-- Prevent duplicate active queue entries for the same Storage object
CREATE UNIQUE INDEX idx_pending_storage_deletions_active_path
  ON public.pending_storage_deletions (bucket_id, storage_path)
  WHERE status IN ('pending', 'processing', 'failed');

-- Global polling index for server-side cleanup workers across all couples
CREATE INDEX idx_pending_storage_deletions_poll
  ON public.pending_storage_deletions (next_retry_at ASC, created_at ASC)
  WHERE status IN ('pending', 'failed');

-- Lease recovery index for reclaiming stalled/crashed processing workers
CREATE INDEX idx_pending_storage_deletions_processing_lease
  ON public.pending_storage_deletions (locked_at ASC)
  WHERE status = 'processing';

-- Couple-scoped operational inspection index
CREATE INDEX idx_pending_storage_deletions_couple_status
  ON public.pending_storage_deletions (couple_id, status, created_at ASC)
  WHERE status IN ('pending', 'processing', 'failed');

CREATE OR REPLACE FUNCTION public.enforce_pending_storage_deletion_lifecycle()
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
     OR NEW.couple_id IS DISTINCT FROM OLD.couple_id
     OR NEW.bucket_id IS DISTINCT FROM OLD.bucket_id
     OR NEW.storage_path IS DISTINCT FROM OLD.storage_path
     OR NEW.entity_type IS DISTINCT FROM OLD.entity_type
     OR NEW.original_uploader_id IS DISTINCT FROM OLD.original_uploader_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Immutable columns on pending_storage_deletions cannot be modified.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF OLD.status IN ('completed', 'abandoned') THEN
    IF NEW.status IS DISTINCT FROM OLD.status
       OR NEW.processed_at IS DISTINCT FROM OLD.processed_at THEN
      RAISE EXCEPTION 'Terminal pending_storage_deletions records cannot change state.'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_pending_storage_deletion_lifecycle() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_pending_storage_deletions_lifecycle
  BEFORE INSERT OR UPDATE ON public.pending_storage_deletions
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_pending_storage_deletion_lifecycle();

-- ----------------------------------------------------------------------------
-- 7. media_objects
-- Metadata for private Supabase Storage files.
-- Parent links use typed nullable FKs with a strict CHECK constraint ensuring
-- each row links to exactly one parent entity (memory, surprise, message, or
-- profile avatar) with zero circular foreign-key dependencies.
--
-- Canonical Storage path format:
--   <couple_id>/<entity_type>/<safe_relative_path>
-- Every upload must use a fresh unique path (e.g., UUID filename); reusing a
-- path currently active in pending_storage_deletions is blocked so async
-- cleanup can never delete a newly uploaded live object.
-- ----------------------------------------------------------------------------
CREATE TABLE public.media_objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id uuid NOT NULL REFERENCES public.couples (id) ON DELETE CASCADE,
  uploaded_by uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
  entity_type text NOT NULL,
  memory_id uuid REFERENCES public.memories (id) ON DELETE CASCADE,
  surprise_id uuid REFERENCES public.surprises (id) ON DELETE CASCADE,
  message_id uuid REFERENCES public.messages (id) ON DELETE CASCADE,
  profile_id uuid REFERENCES public.profiles (id) ON DELETE CASCADE,
  bucket_id text NOT NULL DEFAULT 'couple-media',
  storage_path text NOT NULL,
  mime_type text NOT NULL,
  size_bytes bigint NOT NULL,
  caption text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT media_objects_entity_type_valid
    CHECK (entity_type IN ('memory', 'surprise', 'message', 'avatar')),
  CONSTRAINT media_objects_parent_link_valid
    CHECK (
      (entity_type = 'memory'   AND memory_id IS NOT NULL AND surprise_id IS NULL AND message_id IS NULL AND profile_id IS NULL) OR
      (entity_type = 'surprise' AND surprise_id IS NOT NULL AND memory_id IS NULL AND message_id IS NULL AND profile_id IS NULL) OR
      (entity_type = 'message'  AND message_id IS NOT NULL AND memory_id IS NULL AND surprise_id IS NULL AND profile_id IS NULL) OR
      (entity_type = 'avatar'   AND profile_id IS NOT NULL AND profile_id = uploaded_by AND memory_id IS NULL AND surprise_id IS NULL AND message_id IS NULL)
    ),
  CONSTRAINT media_objects_bucket_valid
    CHECK (bucket_id = 'couple-media'),
  CONSTRAINT media_objects_storage_path_valid
    CHECK (
      char_length(storage_path) BETWEEN 1 AND 512
      AND storage_path LIKE couple_id::text || '/' || entity_type || '/%'
      AND storage_path ~ '^[0-9a-f-]+/(memory|surprise|message|avatar)/[A-Za-z0-9._/-]+$'
      AND storage_path ~ '[A-Za-z0-9_-]\.(jpg|jpeg|png|webp)$'
      AND storage_path NOT LIKE '%//%'
      AND storage_path NOT LIKE '%/'
      AND storage_path !~ '(^|/)\.\.?(/|$)'
    ),
  CONSTRAINT media_objects_unique_bucket_path
    UNIQUE (bucket_id, storage_path),
  CONSTRAINT media_objects_mime_type_valid
    CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp')),
  CONSTRAINT media_objects_mime_extension_match
    CHECK (
      (mime_type = 'image/jpeg' AND storage_path ~ '[A-Za-z0-9_-]\.(jpg|jpeg)$') OR
      (mime_type = 'image/png'  AND storage_path ~ '[A-Za-z0-9_-]\.png$') OR
      (mime_type = 'image/webp' AND storage_path ~ '[A-Za-z0-9_-]\.webp$')
    ),
  CONSTRAINT media_objects_size_bytes_valid
    CHECK (size_bytes > 0 AND size_bytes <= 5242880),
  CONSTRAINT media_objects_caption_length
    CHECK (
      caption IS NULL
      OR (char_length(caption) BETWEEN 1 AND 300 AND caption !~ '^[[:space:]]*$')
    ),
  CONSTRAINT media_objects_metadata_is_object
    CHECK (
      jsonb_typeof(metadata) = 'object'
      AND octet_length(metadata::text) <= 8192
    ),
  CONSTRAINT media_objects_sort_order_non_negative
    CHECK (sort_order >= 0)
);

COMMENT ON TABLE public.media_objects IS
  'Private Storage file metadata. Deleting a parent or replacing an avatar cascades/removes rows and enqueues Storage cleanup.';

ALTER TABLE public.media_objects ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_media_objects_couple_id
  ON public.media_objects (couple_id);

CREATE INDEX idx_media_objects_memory_id
  ON public.media_objects (memory_id, sort_order)
  WHERE memory_id IS NOT NULL;

CREATE INDEX idx_media_objects_surprise_id
  ON public.media_objects (surprise_id, sort_order)
  WHERE surprise_id IS NOT NULL;

CREATE INDEX idx_media_objects_message_id
  ON public.media_objects (message_id)
  WHERE message_id IS NOT NULL;

-- Guarantees at most one active avatar row per profile and indexes profile_id FK
CREATE UNIQUE INDEX idx_media_objects_avatar_profile_id
  ON public.media_objects (profile_id)
  WHERE profile_id IS NOT NULL;

CREATE INDEX idx_media_objects_uploaded_by
  ON public.media_objects (uploaded_by);

-- Deterministic 64-bit advisory lock key for serializing all media_objects
-- inserts and pending_storage_deletions enqueues targeting the same
-- (bucket_id, storage_path). Length-prefixing bucket_id makes the canonical
-- pre-image injective; any 64-bit hash collision only causes harmless extra
-- serialization because all checks still compare exact (bucket_id, storage_path).
CREATE OR REPLACE FUNCTION public.media_storage_path_lock_key(
  p_bucket_id text,
  p_storage_path text
)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = ''
AS $$
  SELECT pg_catalog.hashtextextended(
    'twofold:media_storage_path:'
    || pg_catalog.octet_length(p_bucket_id)::text
    || ':'
    || p_bucket_id
    || ':'
    || p_storage_path,
    0::bigint
  );
$$;

REVOKE ALL ON FUNCTION public.media_storage_path_lock_key(text, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.validate_media_object_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_parent_couple_id uuid;
  v_parent_owner_id uuid;
  v_actor_id uuid;
  v_request_role text;
  v_new_lock_key bigint;
  v_old_avatar_bucket_id text;
  v_old_avatar_storage_path text;
  v_old_lock_key bigint;
  v_has_existing_avatar boolean := false;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.couple_id IS DISTINCT FROM OLD.couple_id
       OR NEW.uploaded_by IS DISTINCT FROM OLD.uploaded_by
       OR NEW.entity_type IS DISTINCT FROM OLD.entity_type
       OR NEW.memory_id IS DISTINCT FROM OLD.memory_id
       OR NEW.surprise_id IS DISTINCT FROM OLD.surprise_id
       OR NEW.message_id IS DISTINCT FROM OLD.message_id
       OR NEW.profile_id IS DISTINCT FROM OLD.profile_id
       OR NEW.bucket_id IS DISTINCT FROM OLD.bucket_id
       OR NEW.storage_path IS DISTINCT FROM OLD.storage_path
       OR NEW.mime_type IS DISTINCT FROM OLD.mime_type
       OR NEW.size_bytes IS DISTINCT FROM OLD.size_bytes
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Immutable storage, metadata, or parent-link columns on media_objects cannot be modified.'
        USING ERRCODE = 'check_violation';
    END IF;

    NEW.updated_at := pg_catalog.now();
    RETURN NEW;
  END IF;

  -- INSERT rules
  NEW.created_at := pg_catalog.now();
  NEW.updated_at := pg_catalog.now();

  IF NEW.couple_id IS NULL
     OR NEW.uploaded_by IS NULL
     OR NEW.bucket_id IS NULL
     OR NEW.storage_path IS NULL THEN
    RAISE EXCEPTION 'Required media_objects fields cannot be null.'
      USING ERRCODE = 'not_null_violation';
  END IF;

  -- Enforce uploader identity for all client-originated INSERT operations.
  -- Under SECURITY DEFINER, current_setting('role', true) reflects the active
  -- PostgREST/session role (e.g., 'anon', 'authenticated', 'service_role').
  v_actor_id := auth.uid();
  v_request_role := pg_catalog.current_setting('role', true);

  IF v_request_role IN ('anon', 'authenticated') THEN
    IF v_actor_id IS NULL OR v_actor_id IS DISTINCT FROM NEW.uploaded_by THEN
      RAISE EXCEPTION 'Media upload is not permitted.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF v_actor_id IS NOT NULL AND v_actor_id IS DISTINCT FROM NEW.uploaded_by THEN
    RAISE EXCEPTION 'Media upload is not permitted.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Validate parent-link shape before touching parent tables.
  IF NOT (
    (NEW.entity_type = 'memory'   AND NEW.memory_id IS NOT NULL   AND NEW.surprise_id IS NULL AND NEW.message_id IS NULL AND NEW.profile_id IS NULL) OR
    (NEW.entity_type = 'surprise' AND NEW.surprise_id IS NOT NULL AND NEW.memory_id IS NULL   AND NEW.message_id IS NULL AND NEW.profile_id IS NULL) OR
    (NEW.entity_type = 'message'  AND NEW.message_id IS NOT NULL  AND NEW.memory_id IS NULL   AND NEW.surprise_id IS NULL AND NEW.profile_id IS NULL) OR
    (NEW.entity_type = 'avatar'   AND NEW.profile_id IS NOT NULL  AND NEW.memory_id IS NULL   AND NEW.surprise_id IS NULL AND NEW.message_id IS NULL)
  ) THEN
    RAISE EXCEPTION 'Media object must reference exactly one valid parent entity.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Lock Level 1 (parent row) + parent couple/ownership validation.
  -- Intentionally uses an identical error message and SQLSTATE across
  -- not-found, wrong-couple, and wrong-owner failures so callers cannot
  -- probe whether another user's private parent record exists.
  IF NEW.entity_type = 'memory' THEN
    -- Shared-memory media: either couple member may attach media to a memory
    -- belonging to NEW.couple_id.
    SELECT m.couple_id
    INTO v_parent_couple_id
    FROM public.memories AS m
    WHERE m.id = NEW.memory_id
    FOR KEY SHARE;

    IF NOT FOUND OR v_parent_couple_id IS DISTINCT FROM NEW.couple_id THEN
      RAISE EXCEPTION 'Media object parent is not accessible or does not match ownership.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF NEW.entity_type = 'surprise' THEN
    -- Creator-only surprise media: only the surprise creator may attach media.
    SELECT s.couple_id, s.created_by
    INTO v_parent_couple_id, v_parent_owner_id
    FROM public.surprises AS s
    WHERE s.id = NEW.surprise_id
    FOR KEY SHARE;

    IF NOT FOUND
       OR v_parent_couple_id IS DISTINCT FROM NEW.couple_id
       OR v_parent_owner_id IS DISTINCT FROM NEW.uploaded_by THEN
      RAISE EXCEPTION 'Media object parent is not accessible or does not match ownership.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF NEW.entity_type = 'message' THEN
    -- Sender-only message media: only the message sender may attach media.
    SELECT msg.couple_id, msg.sender_id
    INTO v_parent_couple_id, v_parent_owner_id
    FROM public.messages AS msg
    WHERE msg.id = NEW.message_id
    FOR KEY SHARE;

    IF NOT FOUND
       OR v_parent_couple_id IS DISTINCT FROM NEW.couple_id
       OR v_parent_owner_id IS DISTINCT FROM NEW.uploaded_by THEN
      RAISE EXCEPTION 'Media object parent is not accessible or does not match ownership.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF NEW.entity_type = 'avatar' THEN
    IF NEW.profile_id IS DISTINCT FROM NEW.uploaded_by THEN
      RAISE EXCEPTION 'Media object parent is not accessible or does not match ownership.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Serialize concurrent avatar replacements for this profile (Lock Level 1).
    PERFORM 1
    FROM public.profiles AS p
    WHERE p.id = NEW.profile_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Media object parent is not accessible or does not match ownership.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT cm.couple_id
    INTO v_parent_couple_id
    FROM public.couple_members AS cm
    WHERE cm.user_id = NEW.profile_id
      AND cm.couple_id = NEW.couple_id
      AND cm.status = 'active';

    IF NOT FOUND OR v_parent_couple_id IS DISTINCT FROM NEW.couple_id THEN
      RAISE EXCEPTION 'Media object parent is not accessible or does not match ownership.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Lock any superseded avatar row before acquiring path advisory locks
    -- (Lock Level 2 -> Lock Level 3) to maintain a strict global lock order.
    SELECT mo.bucket_id, mo.storage_path
    INTO v_old_avatar_bucket_id, v_old_avatar_storage_path
    FROM public.media_objects AS mo
    WHERE mo.entity_type = 'avatar'
      AND mo.profile_id = NEW.profile_id
    FOR UPDATE;

    v_has_existing_avatar := FOUND;
  END IF;

  -- Lock Level 3: acquire transaction-scoped advisory lock(s) for path
  -- serialization BEFORE checking media_objects or pending_storage_deletions.
  -- When replacing an existing avatar, lock both keys in deterministic
  -- ascending order so even hash collisions cannot deadlock.
  v_new_lock_key := public.media_storage_path_lock_key(NEW.bucket_id, NEW.storage_path);

  IF v_has_existing_avatar THEN
    v_old_lock_key := public.media_storage_path_lock_key(v_old_avatar_bucket_id, v_old_avatar_storage_path);

    IF v_old_lock_key < v_new_lock_key THEN
      PERFORM pg_catalog.pg_advisory_xact_lock(v_old_lock_key);
      PERFORM pg_catalog.pg_advisory_xact_lock(v_new_lock_key);
    ELSIF v_new_lock_key < v_old_lock_key THEN
      PERFORM pg_catalog.pg_advisory_xact_lock(v_new_lock_key);
      PERFORM pg_catalog.pg_advisory_xact_lock(v_old_lock_key);
    ELSE
      PERFORM pg_catalog.pg_advisory_xact_lock(v_new_lock_key);
    END IF;
  ELSE
    PERFORM pg_catalog.pg_advisory_xact_lock(v_new_lock_key);
  END IF;

  -- Block reuse of any Storage path currently queued or being deleted.
  IF EXISTS (
    SELECT 1
    FROM public.pending_storage_deletions AS psd
    WHERE psd.bucket_id = NEW.bucket_id
      AND psd.storage_path = NEW.storage_path
      AND psd.status IN ('pending', 'processing', 'failed')
  ) THEN
    RAISE EXCEPTION 'Storage path is currently queued for deletion and cannot be reused.'
      USING ERRCODE = 'unique_violation';
  END IF;

  -- Block reuse of any Storage path currently registered in media_objects.
  -- Checked while holding the advisory lock so a concurrent uncommitted DELETE
  -- on this path is still visible under READ COMMITTED and causes this INSERT
  -- to abort cleanly instead of deadlocking on the unique index.
  IF EXISTS (
    SELECT 1
    FROM public.media_objects AS mo
    WHERE mo.bucket_id = NEW.bucket_id
      AND mo.storage_path = NEW.storage_path
  ) THEN
    RAISE EXCEPTION 'Storage path is already registered and cannot be reused.'
      USING ERRCODE = 'unique_violation';
  END IF;

  -- Remove superseded avatar row; its AFTER DELETE trigger re-entrantly
  -- acquires v_old_lock_key and enqueues Storage cleanup.
  IF v_has_existing_avatar THEN
    DELETE FROM public.media_objects AS mo
    WHERE mo.entity_type = 'avatar'
      AND mo.profile_id = NEW.profile_id;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_media_object_integrity() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_media_objects_validate_integrity
  BEFORE INSERT OR UPDATE ON public.media_objects
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_media_object_integrity();

-- Enqueue storage_path whenever a media_objects row is deleted (directly,
-- via avatar replacement, or via FK cascade). Acquires the same path advisory
-- lock used by validate_media_object_integrity() before modifying the queue.
-- Resets stale 'failed' entries to 'pending' while preserving active
-- 'pending'/'processing' worker leases.
CREATE OR REPLACE FUNCTION public.enqueue_media_storage_deletion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_requester uuid;
BEGIN
  -- Serialize path deletion/enqueue against concurrent media_objects inserts
  -- targeting the same (bucket_id, storage_path).
  PERFORM pg_catalog.pg_advisory_xact_lock(
    public.media_storage_path_lock_key(OLD.bucket_id, OLD.storage_path)
  );

  -- auth.uid() resolves JWT sub across PostgREST v10+ and returns NULL for admin/SQL ops.
  v_requester := auth.uid();

  INSERT INTO public.pending_storage_deletions (
    couple_id,
    bucket_id,
    storage_path,
    entity_type,
    original_uploader_id,
    requested_by,
    status,
    next_retry_at
  )
  VALUES (
    OLD.couple_id,
    OLD.bucket_id,
    OLD.storage_path,
    OLD.entity_type,
    OLD.uploaded_by,
    v_requester,
    'pending',
    pg_catalog.now()
  )
  ON CONFLICT (bucket_id, storage_path)
  WHERE status IN ('pending', 'processing', 'failed')
  DO UPDATE SET
    status = CASE
      WHEN public.pending_storage_deletions.status = 'failed' THEN 'pending'
      ELSE public.pending_storage_deletions.status
    END,
    attempts = CASE
      WHEN public.pending_storage_deletions.status = 'failed' THEN 0
      ELSE public.pending_storage_deletions.attempts
    END,
    last_error = CASE
      WHEN public.pending_storage_deletions.status = 'failed' THEN NULL
      ELSE public.pending_storage_deletions.last_error
    END,
    next_retry_at = CASE
      WHEN public.pending_storage_deletions.status = 'failed' THEN pg_catalog.now()
      ELSE public.pending_storage_deletions.next_retry_at
    END,
    requested_by = COALESCE(EXCLUDED.requested_by, public.pending_storage_deletions.requested_by),
    updated_at = pg_catalog.now();

  RETURN OLD;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_media_storage_deletion() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_media_objects_enqueue_storage_deletion
  AFTER DELETE ON public.media_objects
  FOR EACH ROW
  EXECUTE FUNCTION public.enqueue_media_storage_deletion();

-- ----------------------------------------------------------------------------
-- 8. Table privilege hardening (least privilege for client roles)
-- Supabase grants ALL table privileges in public to anon and authenticated by
-- default. Revoke unnecessary DDL/bypass privileges (TRUNCATE, REFERENCES,
-- TRIGGER) from client roles on all application tables, and deny all direct
-- table access to pending_storage_deletions (server-side service_role only).
-- Legitimate authenticated CRUD (gated by Task 1.4 RLS) and RPC EXECUTE
-- grants (get_couple_letters_preview, get_couple_surprises_preview,
-- reveal_surprise) remain intact.
-- ----------------------------------------------------------------------------
REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE
  public.profiles,
  public.user_private_settings,
  public.couples,
  public.couple_members,
  public.date_plans,
  public.memories,
  public.messages,
  public.letters,
  public.surprises,
  public.media_objects
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON TABLE public.pending_storage_deletions
FROM PUBLIC, anon, authenticated;
