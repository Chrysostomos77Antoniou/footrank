-- Remove the rating-gap limit on proposing and accepting a match.
--
-- Until now propose_match / propose_match_with_roster, accept_match_request and
-- accept_match_proposal refused with "rating_gap_too_large" when the PWR
-- (teams.rating) of the two teams differed by more than max_allowed_rating_gap():
-- 150, or the gap to the closest-rated other searching team of the same city
-- (+-60 minutes) when that is larger. From now on the captain decides: a team can
-- propose to, and a captain can accept, any opponent whatever the difference.
--
-- Only max_allowed_rating_gap() changes. It returns the largest integer, so the
-- "abs(difference) > max" test in those three functions can never fire (and the
-- "<= max" test in notify_matching_opponents always passes). Nothing else moves:
--   * the PWR algorithm (apply_elo_on_completion) is untouched. It already makes
--     the stakes grow with the gap: beating a much stronger team pays up to 2.5x
--     the usual points, losing to a much weaker team costs up to 2.5x, and the
--     favourite's win over a much weaker team pays less (down to 0.4x);
--   * the "new match nearby" / "opponent available" notifications still go only to
--     teams within 50 PWR of the request (notify_match_request,
--     notify_matching_opponents) - they are not part of the limit;
--   * no table, policy, grant or app change; installed apps keep working.
-- Safe to run twice. Undo: rollback_remove_pwr_gap_limit.sql (the original function back).

set local lock_timeout = '3s';

create or replace function public.max_allowed_rating_gap(
  p_request_id uuid,
  p_team_id uuid,
  p_city text,
  p_scheduled_at timestamp with time zone)
returns integer
language sql
stable
set search_path to 'public'
as $function$select 2147483647$function$;

comment on function public.max_allowed_rating_gap(uuid, uuid, text, timestamp with time zone) is
  'No limit since 2026-11-01: returns the largest integer. Before: greatest(150, gap to the closest-rated other searching team of the same city within 60 minutes).';
