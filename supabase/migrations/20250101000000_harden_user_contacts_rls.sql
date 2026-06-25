-- Enforce row ownership on user_contacts (holds PII: phone numbers).
-- Without an INSERT/UPDATE WITH CHECK clause, ProfileRepository.saveMyPhone()
-- (which sends a client-supplied user_id) would let any authenticated user
-- overwrite another user's phone number or write rows under arbitrary user_ids.
--
-- Idempotent: safe to re-run. Uses (select auth.uid()) for correct row
-- scoping and per-statement caching (CVE-2025-48757 best practice).

-- 1) Ensure RLS is enabled.
ALTER TABLE public.user_contacts ENABLE ROW LEVEL SECURITY;

-- 2) Drop any pre-existing policies so we recreate them cleanly/correctly.
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
