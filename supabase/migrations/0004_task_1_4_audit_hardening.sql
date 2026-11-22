-- ============================================================================
-- Migration: 0004_task_1_4_audit_hardening.sql
-- Purpose:   Address outstanding findings from independent security audit
--            for TwoFold Task 1.4:
--            - SEC-01: Remove direct client DELETE policy on storage.objects.
--            - SEC-02: Revoke unnecessary table-level DML privileges from anon
--                      and non-manageable tables from authenticated.
--            - SEC-03: Document storage metadata consistency investigation.
--            - SEC-04: Mask letter titles as 'Locked Letter' before unlock_at.
-- Depends:   0001_core_couple_schema.sql, 0002_mvp_feature_tables.sql,
--            0003_rls_and_storage_policies.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Finding SEC-01: Remove Direct Storage Deletion Policy
-- ----------------------------------------------------------------------------
-- All application media deletion must strictly originate through the application
-- metadata layer:
--   1. Client deletes the public.media_objects record (or parent entity).
--   2. Database trigger trg_media_objects_enqueue_storage_deletion enqueues the
--      path in public.pending_storage_deletions.
--   3. The trusted server-side cleanup worker processes the deletion queue using
--      privileged service_role credentials.
-- Removing direct client DELETE on storage.objects prevents dangling metadata
-- records and preserves the durable deletion queue architecture.
DROP POLICY IF EXISTS "storage_objects_couple_media_delete" ON storage.objects;

-- ----------------------------------------------------------------------------
-- 2. Finding SEC-02: Least-Privilege Table Grants
-- ----------------------------------------------------------------------------
-- Revoke all table-level DML (INSERT, UPDATE, DELETE) privileges from role 'anon'
-- across all application tables. Role 'anon' retains only SELECT privileges,
-- which are fully closed by fail-closed RLS policies (0 rows returned).
REVOKE INSERT, UPDATE, DELETE ON TABLE
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
FROM anon;

-- Revoke client-side INSERT and DELETE on couples from role 'authenticated'.
-- Couples cannot be created or deleted through direct client operations.
-- Active couple members retain SELECT and UPDATE (for space_name, settings).
REVOKE INSERT, DELETE ON TABLE public.couples FROM authenticated;

-- Revoke client-side INSERT, UPDATE, and DELETE on couple_members from 'authenticated'.
-- Membership records are immutable and cannot be provisioned or modified by clients.
-- Active couple members retain SELECT only (to identify their partner).
REVOKE INSERT, UPDATE, DELETE ON TABLE public.couple_members FROM authenticated;

-- Re-affirm zero access on pending_storage_deletions for client roles
REVOKE ALL ON TABLE public.pending_storage_deletions FROM PUBLIC, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3. Finding SEC-03: Storage Metadata Consistency (Investigation & Status)
-- ----------------------------------------------------------------------------
-- Technical investigation of installed Supabase Storage (storage-api:v1.96.0):
--   - storage-api checks upload authorization during prepareUpload() via
--     can_insert_object() BEFORE binary streaming completes.
--   - At RLS evaluation time, storage.objects.metadata does NOT contain the
--     final server-computed 'size' field (only client-declared contentLength,
--     which is undefined for streaming/chunked requests).
--   - The final record is written during completeUpload() via asSuperUser(),
--     bypassing RLS.
--   - Therefore, checking (metadata->>'size') in the RLS INSERT policy is not
--     safely supported at policy-probe time across standard/chunked uploads.
-- Protection guarantees:
--   - The storage bucket 'couple-media' strictly enforces file_size_limit (5 MB)
--     and allowed_mime_types (image/jpeg, image/png, image/webp) at daemon level.
--   - public.media_objects strictly enforces size_bytes <= 5242880, MIME types,
--     and extension regex matching at the PostgreSQL schema level.
--   - Production architecture requires server-side magic-byte inspection in the
--     trusted media ingestion worker.

-- ----------------------------------------------------------------------------
-- 4. Finding SEC-04: Locked Letter Title Privacy in Preview RPC
-- ----------------------------------------------------------------------------
-- Update get_couple_letters_preview() so recipients cannot see the actual title
-- of a locked letter before its scheduled unlock_at time.
-- Returns 'Locked Letter' while locked; reveals actual title upon unlock.
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
    CASE
      WHEN l.sender_id = v_user_id
        OR (l.status = 'sent' AND (l.unlock_at IS NULL OR v_now >= l.unlock_at))
      THEN l.title
      ELSE 'Locked Letter'
    END AS title,
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

REVOKE ALL ON FUNCTION public.get_couple_letters_preview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_couple_letters_preview() TO authenticated;
