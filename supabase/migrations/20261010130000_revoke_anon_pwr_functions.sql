-- Security advisor: two SECURITY DEFINER functions were callable by the
-- signed-out `anon` role through /rest/v1/rpc.
--
-- * submit_pwr_assessment is called by the app only for signed-in users, so it
--   keeps `authenticated` (and service_role) but loses public/anon.
-- * enforce_pwr_assessment_on_join_request is a trigger function. EXECUTE is
--   only checked when a trigger is created, never when it fires, so no role
--   needs it; it is no longer exposed as an RPC at all.

revoke execute on function public.submit_pwr_assessment(jsonb) from public, anon;
revoke execute on function public.enforce_pwr_assessment_on_join_request() from public, anon, authenticated;
