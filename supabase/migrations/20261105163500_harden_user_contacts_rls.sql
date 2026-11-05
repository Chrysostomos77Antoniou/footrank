-- Harden public.user_contacts RLS to owner-only select, insert, update, and delete.
-- Rebased from PR #1: supabase/migrations/20250101000000_harden_user_contacts_rls.sql
-- Branch: mc/harden-user-contacts-rls @ ed3a21bd88031b6250696b583dc2b46ee091edef
-- Base tip used for series ordering: master @ f4875a7 (latest file 20261102150000_*).
--
-- Enforce row ownership on user_contacts (holds PII: phone numbers).
-- Current app writes go through security-definer RPCs (update_my_phone,
-- create_profile_with_phone); fetchMyPhone() still SELECTs the table as the
-- signed-in user. Owner-only RLS blocks forged PostgREST upserts while those
-- SECURITY DEFINER paths continue to bypass RLS (confirmed live in
-- FR-0005-pr1-followup.md part a).
--
-- Live today (part a): RLS enabled; single policy "Own contact select"
-- (SELECT only). No INSERT/UPDATE/DELETE policies. This file drops that live
-- name plus the PR #1 names, then recreates four owner policies.
--
-- Uses (select auth.uid()) for correct row scoping and per-statement caching
-- (CVE-2025-48757 best practice).

-- 1) Ensure RLS is enabled.
ALTER TABLE public.user_contacts ENABLE ROW LEVEL SECURITY;

-- 2) Drop live + PR policy names so recreate is clean/idempotent.
DROP POLICY IF EXISTS "Own contact select" ON public.user_contacts;
DROP POLICY IF EXISTS "user_contacts_select_own" ON public.user_contacts;
DROP POLICY IF EXISTS "user_contacts_insert_own" ON public.user_contacts;
DROP POLICY IF EXISTS "user_contacts_update_own" ON public.user_contacts;
DROP POLICY IF EXISTS "user_contacts_delete_own" ON public.user_contacts;

-- 3) SELECT: a user can only read their own contact row.
CREATE POLICY "user_contacts_select_own"
  ON public.user_contacts
  FOR SELECT
  TO authenticated
  USING (user_id = (select auth.uid()));

-- 4) INSERT: a user can only create a row for themselves.
CREATE POLICY "user_contacts_insert_own"
  ON public.user_contacts
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = (select auth.uid()));

-- 5) UPDATE: a user can only update their own row, and cannot reassign user_id.
CREATE POLICY "user_contacts_update_own"
  ON public.user_contacts
  FOR UPDATE
  TO authenticated
  USING (user_id = (select auth.uid()))
  WITH CHECK (user_id = (select auth.uid()));

-- 6) DELETE: a user can only delete their own row.
CREATE POLICY "user_contacts_delete_own"
  ON public.user_contacts
  FOR DELETE
  TO authenticated
  USING (user_id = (select auth.uid()));
