-- ============================================================================
-- Migration: 0005_task_1_4_final_privilege_hardening.sql
-- Purpose:   Explicitly revoke INSERT, UPDATE, and DELETE privileges from both
--            PUBLIC and anon on all 10 user-facing application tables.
--            Preserves existing SELECT on anon (restricted fail-closed by RLS),
--            and preserves all authenticated and service_role permissions.
-- Depends:   0001_core_couple_schema.sql, 0002_mvp_feature_tables.sql,
--            0003_rls_and_storage_policies.sql, 0004_task_1_4_audit_hardening.sql
-- ============================================================================

-- Explicitly revoke INSERT, UPDATE, and DELETE privileges from PUBLIC and anon
-- across all 10 user-facing application tables.
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
FROM PUBLIC, anon;
