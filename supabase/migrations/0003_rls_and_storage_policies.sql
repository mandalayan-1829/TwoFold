-- ============================================================================
-- Migration: 0003_rls_and_storage_policies.sql
-- Purpose:   Row Level Security (RLS) policies for all 11 application tables
--            and Supabase Storage access-control for TwoFold.
-- Depends:   0001_core_couple_schema.sql, 0002_mvp_feature_tables.sql
-- Notes:
--   - TwoFold strictly enforces exactly two active members per couple space.
--   - All client policies are restricted to role 'authenticated'. Role 'anon'
--     has zero access to private couple tables or storage objects (fail-closed).
--   - Recursion between couples and couple_members is avoided via carefully
--     scoped SECURITY DEFINER helper functions with SET search_path = '' and
--     fully qualified table references.
--   - Initial couple creation and membership provisioning are privileged
--     server-side operations (e.g. service_role or admin setup); client-side
--     INSERT into couples and couple_members is disallowed.
--   - Direct table SELECT on locked letters and unrevealed surprises is denied
--     to the recipient. Metadata-only envelope preview cards are accessed
--     via get_couple_letters_preview() and get_couple_surprises_preview().
--   - Direct UPDATE on surprises is creator-only; recipients open ready
--     surprises exclusively via the server-time-checked reveal_surprise() RPC.
--   - Supabase Storage bucket 'couple-media' is private (5 MB limit, JPEG/PNG/WebP).
--     Storage access is validated against public.media_objects and parent records.
--   - public.pending_storage_deletions remains strictly inaccessible to anon
--     and authenticated client roles; only service_role processes the queue.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Helper Functions (SECURITY DEFINER, safe search_path, least privilege)
-- ----------------------------------------------------------------------------

-- Check whether the authenticated user is an active member of the given couple.
CREATE OR REPLACE FUNCTION public.is_couple_member(p_couple_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL OR p_couple_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.couple_members AS cm
    WHERE cm.couple_id = p_couple_id
      AND cm.user_id = v_uid
      AND cm.status = 'active'
  );
END;
$$;

COMMENT ON FUNCTION public.is_couple_member(uuid) IS
  'Returns true if auth.uid() is an active member of the specified couple space.';

REVOKE ALL ON FUNCTION public.is_couple_member(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_couple_member(uuid) TO authenticated;

-- Check whether the authenticated user can view the specified profile
-- (their own profile, or their active couple partner profile).
CREATE OR REPLACE FUNCTION public.can_read_profile(p_target_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL OR p_target_user_id IS NULL THEN
    RETURN false;
  END IF;

  -- Users can always read their own profile
  IF v_uid = p_target_user_id THEN
    RETURN true;
  END IF;

  -- Couple members can read each other's profile within the shared space
  RETURN EXISTS (
    SELECT 1
    FROM public.couple_members AS my_cm
    JOIN public.couple_members AS partner_cm
      ON my_cm.couple_id = partner_cm.couple_id
    WHERE my_cm.user_id = v_uid
      AND my_cm.status = 'active'
      AND partner_cm.user_id = p_target_user_id
      AND partner_cm.status = 'active'
  );
END;
$$;

COMMENT ON FUNCTION public.can_read_profile(uuid) IS
  'Returns true if auth.uid() is the profile owner or their active couple partner.';

REVOKE ALL ON FUNCTION public.can_read_profile(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_profile(uuid) TO authenticated;

-- Validate whether auth.uid() is authorized to read a storage object in couple-media.
-- Access is checked against the corresponding media_objects record and parent entity state.
CREATE OR REPLACE FUNCTION public.can_read_storage_object(
  p_bucket_id text,
  p_object_name text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid;
  v_media record;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL OR p_bucket_id IS NULL OR p_object_name IS NULL THEN
    RETURN false;
  END IF;

  IF p_bucket_id <> 'couple-media' THEN
    RETURN false;
  END IF;

  SELECT
    mo.id,
    mo.couple_id,
    mo.uploaded_by,
    mo.entity_type,
    mo.surprise_id
  INTO v_media
  FROM public.media_objects AS mo
  WHERE mo.bucket_id = p_bucket_id
    AND mo.storage_path = p_object_name;

  IF NOT FOUND THEN
    -- Unregistered storage paths are inaccessible
    RETURN false;
  END IF;

  -- Must be an active member of the couple
  IF NOT EXISTS (
    SELECT 1
    FROM public.couple_members AS cm
    WHERE cm.couple_id = v_media.couple_id
      AND cm.user_id = v_uid
      AND cm.status = 'active'
  ) THEN
    RETURN false;
  END IF;

  -- If surprise media: creator always allowed; partner only if revealed and now() >= reveal_at
  IF v_media.entity_type = 'surprise' THEN
    IF v_media.uploaded_by = v_uid THEN
      RETURN true;
    END IF;

    RETURN EXISTS (
      SELECT 1
      FROM public.surprises AS s
      WHERE s.id = v_media.surprise_id
        AND s.status = 'revealed'
        AND (s.reveal_at IS NULL OR pg_catalog.now() >= s.reveal_at)
    );
  END IF;

  -- Memory, message, and avatar media are readable by both active couple members
  RETURN true;
END;
$$;

COMMENT ON FUNCTION public.can_read_storage_object(text, text) IS
  'Returns true if auth.uid() is authorized to read the storage object according to media_objects and parent status.';

REVOKE ALL ON FUNCTION public.can_read_storage_object(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_storage_object(text, text) TO authenticated;

-- Validate whether auth.uid() is authorized to insert an object into couple-media.
-- Requires an existing, matching media_objects row where uploaded_by matches auth.uid().
CREATE OR REPLACE FUNCTION public.can_insert_storage_object(
  p_bucket_id text,
  p_object_name text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid;
  v_media record;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL OR p_bucket_id IS NULL OR p_object_name IS NULL THEN
    RETURN false;
  END IF;

  IF p_bucket_id <> 'couple-media' THEN
    RETURN false;
  END IF;

  SELECT
    mo.id,
    mo.couple_id,
    mo.uploaded_by,
    mo.entity_type
  INTO v_media
  FROM public.media_objects AS mo
  WHERE mo.bucket_id = p_bucket_id
    AND mo.storage_path = p_object_name;

  IF NOT FOUND THEN
    -- Arbitrary storage object insertion without a media_objects record is denied
    RETURN false;
  END IF;

  -- Uploader must match auth.uid()
  IF v_media.uploaded_by IS DISTINCT FROM v_uid THEN
    RETURN false;
  END IF;

  -- Uploader must be an active member of the couple
  RETURN EXISTS (
    SELECT 1
    FROM public.couple_members AS cm
    WHERE cm.couple_id = v_media.couple_id
      AND cm.user_id = v_uid
      AND cm.status = 'active'
  );
END;
$$;

COMMENT ON FUNCTION public.can_insert_storage_object(text, text) IS
  'Returns true if auth.uid() is authorized to upload the storage object based on prior media_objects registration.';

REVOKE ALL ON FUNCTION public.can_insert_storage_object(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_insert_storage_object(text, text) TO authenticated;

-- Validate whether auth.uid() is authorized to overwrite (UPDATE) or delete (DELETE) a storage object.
-- Shared memory media: either active couple member.
-- Message, surprise, avatar media: strictly the original uploader.
CREATE OR REPLACE FUNCTION public.can_manage_storage_object(
  p_bucket_id text,
  p_object_name text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid;
  v_media record;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL OR p_bucket_id IS NULL OR p_object_name IS NULL THEN
    RETURN false;
  END IF;

  IF p_bucket_id <> 'couple-media' THEN
    RETURN false;
  END IF;

  SELECT
    mo.id,
    mo.couple_id,
    mo.uploaded_by,
    mo.entity_type
  INTO v_media
  FROM public.media_objects AS mo
  WHERE mo.bucket_id = p_bucket_id
    AND mo.storage_path = p_object_name;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.couple_members AS cm
    WHERE cm.couple_id = v_media.couple_id
      AND cm.user_id = v_uid
      AND cm.status = 'active'
  ) THEN
    RETURN false;
  END IF;

  -- Memory media is shared; message, surprise, avatar media are managed strictly by the uploader
  IF v_media.entity_type = 'memory' THEN
    RETURN true;
  ELSIF v_media.entity_type IN ('message', 'surprise', 'avatar') THEN
    RETURN (v_media.uploaded_by = v_uid);
  END IF;

  RETURN false;
END;
$$;

COMMENT ON FUNCTION public.can_manage_storage_object(text, text) IS
  'Returns true if auth.uid() is authorized to overwrite or delete the storage object based on parent ownership.';

REVOKE ALL ON FUNCTION public.can_manage_storage_object(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_storage_object(text, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 2. Core Identity & Settings Policies (profiles, user_private_settings)
-- ----------------------------------------------------------------------------

-- Table 1: profiles
-- A user can access their own profile; couple members may access limited profile info of partner.
-- Users cannot modify or delete another user's profile.
CREATE POLICY "profiles_select_self_or_partner"
ON public.profiles
FOR SELECT
TO authenticated
USING (public.can_read_profile(id));

CREATE POLICY "profiles_insert_self"
ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK (id = (select auth.uid()));

CREATE POLICY "profiles_update_self"
ON public.profiles
FOR UPDATE
TO authenticated
USING (id = (select auth.uid()))
WITH CHECK (id = (select auth.uid()));

CREATE POLICY "profiles_delete_self"
ON public.profiles
FOR DELETE
TO authenticated
USING (id = (select auth.uid()));

-- Table 2: user_private_settings
-- Strictly per-user private preferences and unread cursor.
-- Never readable or modifiable by partner or unrelated users.
CREATE POLICY "user_private_settings_select_self"
ON public.user_private_settings
FOR SELECT
TO authenticated
USING (user_id = (select auth.uid()));

CREATE POLICY "user_private_settings_insert_self"
ON public.user_private_settings
FOR INSERT
TO authenticated
WITH CHECK (user_id = (select auth.uid()));

CREATE POLICY "user_private_settings_update_self"
ON public.user_private_settings
FOR UPDATE
TO authenticated
USING (user_id = (select auth.uid()))
WITH CHECK (user_id = (select auth.uid()));

CREATE POLICY "user_private_settings_delete_self"
ON public.user_private_settings
FOR DELETE
TO authenticated
USING (user_id = (select auth.uid()));

-- ----------------------------------------------------------------------------
-- 3. Couple Space & Membership Policies (couples, couple_members)
-- ----------------------------------------------------------------------------

-- Table 3: couples
-- Only authenticated members of the couple space may read its record.
-- Active couple members may update couple display settings (space_name, anniversary_date, display_preferences).
-- Arbitrary creation (INSERT) or deletion (DELETE) via client operations is disallowed.
CREATE POLICY "couples_select_active_member"
ON public.couples
FOR SELECT
TO authenticated
USING (public.is_couple_member(id));

CREATE POLICY "couples_update_active_member"
ON public.couples
FOR UPDATE
TO authenticated
USING (public.is_couple_member(id))
WITH CHECK (public.is_couple_member(id));

-- Table 4: couple_members
-- Active members may read membership information in their couple to identify their partner.
-- Adding, removing, replacing, or modifying members via client operations is strictly disallowed.
CREATE POLICY "couple_members_select_active_member"
ON public.couple_members
FOR SELECT
TO authenticated
USING (public.is_couple_member(couple_id));

-- ----------------------------------------------------------------------------
-- 4. Shared Memories & Date Plans Policies (memories, date_plans)
-- ----------------------------------------------------------------------------

-- Table 5: memories
-- Shared relationship memories. Both authorized partners may read, create, update, and delete.
-- Couple membership is enforced on every operation; created_by spoofing is blocked on insert.
CREATE POLICY "memories_select_couple_member"
ON public.memories
FOR SELECT
TO authenticated
USING (public.is_couple_member(couple_id));

CREATE POLICY "memories_insert_couple_member"
ON public.memories
FOR INSERT
TO authenticated
WITH CHECK (
  public.is_couple_member(couple_id)
  AND created_by = (select auth.uid())
);

CREATE POLICY "memories_update_couple_member"
ON public.memories
FOR UPDATE
TO authenticated
USING (public.is_couple_member(couple_id))
WITH CHECK (public.is_couple_member(couple_id));

CREATE POLICY "memories_delete_couple_member"
ON public.memories
FOR DELETE
TO authenticated
USING (public.is_couple_member(couple_id));

-- Table 6: date_plans
-- Shared date plans. Both authorized partners may read, create, update, and delete.
-- Couple membership is enforced on every operation; created_by spoofing is blocked on insert.
CREATE POLICY "date_plans_select_couple_member"
ON public.date_plans
FOR SELECT
TO authenticated
USING (public.is_couple_member(couple_id));

CREATE POLICY "date_plans_insert_couple_member"
ON public.date_plans
FOR INSERT
TO authenticated
WITH CHECK (
  public.is_couple_member(couple_id)
  AND created_by = (select auth.uid())
);

CREATE POLICY "date_plans_update_couple_member"
ON public.date_plans
FOR UPDATE
TO authenticated
USING (public.is_couple_member(couple_id))
WITH CHECK (public.is_couple_member(couple_id));

CREATE POLICY "date_plans_delete_couple_member"
ON public.date_plans
FOR DELETE
TO authenticated
USING (public.is_couple_member(couple_id));

-- ----------------------------------------------------------------------------
-- 5. Communication & Locked Content Policies (messages, letters, surprises)
-- ----------------------------------------------------------------------------

-- Table 7: messages
-- Both partners may read messages in their couple chat.
-- Members may create messages only as themselves (no sender_id spoofing).
-- Only the original sender may edit or delete their own messages.
CREATE POLICY "messages_select_couple_member"
ON public.messages
FOR SELECT
TO authenticated
USING (public.is_couple_member(couple_id));

CREATE POLICY "messages_insert_sender"
ON public.messages
FOR INSERT
TO authenticated
WITH CHECK (
  public.is_couple_member(couple_id)
  AND sender_id = (select auth.uid())
);

CREATE POLICY "messages_update_sender"
ON public.messages
FOR UPDATE
TO authenticated
USING (
  public.is_couple_member(couple_id)
  AND sender_id = (select auth.uid())
)
WITH CHECK (
  public.is_couple_member(couple_id)
  AND sender_id = (select auth.uid())
);

CREATE POLICY "messages_delete_sender"
ON public.messages
FOR DELETE
TO authenticated
USING (
  public.is_couple_member(couple_id)
  AND sender_id = (select auth.uid())
);

-- Table 8: letters
-- Sender may always view, edit, or delete their own letters (including drafts).
-- Recipient may SELECT sent letters from public.letters ONLY after unlock_at has arrived.
-- Locked received letters are queried exclusively via get_couple_letters_preview() RPC (masks body to NULL).
-- Only the sender may edit or delete their own letters.
CREATE POLICY "letters_select_sender_or_unlocked"
ON public.letters
FOR SELECT
TO authenticated
USING (
  public.is_couple_member(couple_id)
  AND (
    sender_id = (select auth.uid())
    OR (
      status = 'sent'
      AND (unlock_at IS NULL OR pg_catalog.now() >= unlock_at)
    )
  )
);

CREATE POLICY "letters_insert_sender"
ON public.letters
FOR INSERT
TO authenticated
WITH CHECK (
  public.is_couple_member(couple_id)
  AND sender_id = (select auth.uid())
);

CREATE POLICY "letters_update_sender"
ON public.letters
FOR UPDATE
TO authenticated
USING (
  public.is_couple_member(couple_id)
  AND sender_id = (select auth.uid())
)
WITH CHECK (
  public.is_couple_member(couple_id)
  AND sender_id = (select auth.uid())
);

CREATE POLICY "letters_delete_sender"
ON public.letters
FOR DELETE
TO authenticated
USING (
  public.is_couple_member(couple_id)
  AND sender_id = (select auth.uid())
);

-- Table 9: surprises
-- Creator may always view, edit, or delete their own surprises (subject to lifecycle triggers).
-- Recipient may SELECT from public.surprises ONLY when status = 'revealed' AND now() >= reveal_at.
-- Unopened surprise metadata cards are queried via get_couple_surprises_preview() RPC (content is NULL).
-- Direct UPDATE is creator-only; recipient opens ready surprises via reveal_surprise() RPC.
CREATE POLICY "surprises_select_creator_or_revealed"
ON public.surprises
FOR SELECT
TO authenticated
USING (
  public.is_couple_member(couple_id)
  AND (
    created_by = (select auth.uid())
    OR (
      status = 'revealed'
      AND (reveal_at IS NULL OR pg_catalog.now() >= reveal_at)
    )
  )
);

CREATE POLICY "surprises_insert_creator"
ON public.surprises
FOR INSERT
TO authenticated
WITH CHECK (
  public.is_couple_member(couple_id)
  AND created_by = (select auth.uid())
);

CREATE POLICY "surprises_update_creator"
ON public.surprises
FOR UPDATE
TO authenticated
USING (
  public.is_couple_member(couple_id)
  AND created_by = (select auth.uid())
)
WITH CHECK (
  public.is_couple_member(couple_id)
  AND created_by = (select auth.uid())
);

CREATE POLICY "surprises_delete_creator"
ON public.surprises
FOR DELETE
TO authenticated
USING (
  public.is_couple_member(couple_id)
  AND created_by = (select auth.uid())
);

-- ----------------------------------------------------------------------------
-- 6. Media Objects & Pending Deletions Policies
-- ----------------------------------------------------------------------------

-- Table 10: media_objects
-- Authorization is enforced through the parent entity and couple membership.
-- Avatars are restricted to the owner's profile.
-- Memory media is shared; message, surprise, avatar media are managed by the uploader.
-- Surprise media is visible to non-creators ONLY after the parent surprise is revealed and reveal_at reached.
CREATE POLICY "media_objects_select_authorized"
ON public.media_objects
FOR SELECT
TO authenticated
USING (
  public.is_couple_member(couple_id)
  AND (
    entity_type IN ('memory', 'message', 'avatar')
    OR (
      entity_type = 'surprise'
      AND (
        uploaded_by = (select auth.uid())
        OR EXISTS (
          SELECT 1
          FROM public.surprises AS s
          WHERE s.id = media_objects.surprise_id
            AND s.status = 'revealed'
            AND (s.reveal_at IS NULL OR pg_catalog.now() >= s.reveal_at)
        )
      )
    )
  )
);

CREATE POLICY "media_objects_insert_authorized"
ON public.media_objects
FOR INSERT
TO authenticated
WITH CHECK (
  public.is_couple_member(couple_id)
  AND uploaded_by = (select auth.uid())
  AND (
    (entity_type = 'memory' AND EXISTS (
      SELECT 1 FROM public.memories AS m
      WHERE m.id = media_objects.memory_id
        AND m.couple_id = media_objects.couple_id
    ))
    OR (entity_type = 'surprise' AND EXISTS (
      SELECT 1 FROM public.surprises AS s
      WHERE s.id = media_objects.surprise_id
        AND s.couple_id = media_objects.couple_id
        AND s.created_by = (select auth.uid())
    ))
    OR (entity_type = 'message' AND EXISTS (
      SELECT 1 FROM public.messages AS msg
      WHERE msg.id = media_objects.message_id
        AND msg.couple_id = media_objects.couple_id
        AND msg.sender_id = (select auth.uid())
    ))
    OR (entity_type = 'avatar' AND profile_id = (select auth.uid()))
  )
);

CREATE POLICY "media_objects_update_authorized"
ON public.media_objects
FOR UPDATE
TO authenticated
USING (
  public.is_couple_member(couple_id)
  AND (
    entity_type = 'memory'
    OR (entity_type IN ('surprise', 'message', 'avatar') AND uploaded_by = (select auth.uid()))
  )
)
WITH CHECK (
  public.is_couple_member(couple_id)
  AND (
    entity_type = 'memory'
    OR (entity_type IN ('surprise', 'message', 'avatar') AND uploaded_by = (select auth.uid()))
  )
);

CREATE POLICY "media_objects_delete_authorized"
ON public.media_objects
FOR DELETE
TO authenticated
USING (
  public.is_couple_member(couple_id)
  AND (
    entity_type = 'memory'
    OR (entity_type IN ('surprise', 'message', 'avatar') AND uploaded_by = (select auth.uid()))
  )
);

-- Table 11: pending_storage_deletions
-- Strictly inaccessible to anon or authenticated application users.
-- RLS is enabled; zero policies exist for anon/authenticated (fail-closed).
-- Direct table access was revoked in 0002 and is reiterated here for absolute defense in depth.
REVOKE ALL ON TABLE public.pending_storage_deletions FROM PUBLIC, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 7. Supabase Storage Configuration & Policies (couple-media bucket)
-- Note: storage.buckets and storage.objects have RLS enabled by default in Supabase.
-- ----------------------------------------------------------------------------

-- Configure private 'couple-media' bucket with 5 MB limit and allowed image MIME types.
INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES (
  'couple-media',
  'couple-media',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']::text[];

-- Allow authenticated users to inspect the couple-media bucket metadata.
CREATE POLICY "storage_buckets_couple_media_select"
ON storage.buckets
FOR SELECT
TO authenticated
USING (id = 'couple-media');

-- Storage object policies for couple-media:
-- SELECT: Validated against media_objects and parent entity visibility.
CREATE POLICY "storage_objects_couple_media_select"
ON storage.objects
FOR SELECT
TO authenticated
USING (public.can_read_storage_object(bucket_id, name));

-- INSERT: Must have a prior matching media_objects row uploaded by auth.uid().
CREATE POLICY "storage_objects_couple_media_insert"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (public.can_insert_storage_object(bucket_id, name));

-- UPDATE: Managed according to parent entity permissions (memory shared, rest uploader only).
CREATE POLICY "storage_objects_couple_media_update"
ON storage.objects
FOR UPDATE
TO authenticated
USING (public.can_manage_storage_object(bucket_id, name))
WITH CHECK (public.can_manage_storage_object(bucket_id, name));

-- DELETE: Managed according to parent entity permissions (memory shared, rest uploader only).
CREATE POLICY "storage_objects_couple_media_delete"
ON storage.objects
FOR DELETE
TO authenticated
USING (public.can_manage_storage_object(bucket_id, name));
