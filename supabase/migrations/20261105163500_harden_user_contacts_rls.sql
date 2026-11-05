-- Harden public.user_contacts RLS to owner read-only.
--
-- The table holds phone numbers. Writes go only through the security-definer
-- RPCs (update_my_phone, create_profile_with_phone). No INSERT, UPDATE, or
-- DELETE policies exist on purpose: anon and authenticated have full table
-- grants, so a write policy would open direct PostgREST writes that are denied
-- today. fetchMyPhone() still SELECTs the signed-in user's own row.
--
-- Rebased from PR #1 (supabase/migrations/20250101000000_harden_user_contacts_rls.sql).
-- Drops the live policy "Own contact select" and the PR #1 policy names, then
-- recreates only the owner SELECT policy.
--
-- Uses (select auth.uid()) for correct row scoping and per-statement caching.

-- 1) Ensure RLS is enabled.
ALTER TABLE public.user_contacts ENABLE ROW LEVEL SECURITY;

-- 2) Drop the live policy and the PR #1 names. Write policies are not recreated.
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
