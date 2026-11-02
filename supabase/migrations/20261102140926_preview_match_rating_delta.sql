-- Exact Pitch Power preview against a specific opponent.
--
-- The app's "Pitch Power at stake" panel calls preview_team_rating_delta(team, type). That function cannot see the
-- opponent: it always shows the base move (+-40 ranked, +-20 casual) plus the hidden-power catch-up of the team's own
-- roster, whatever the other team's rating is. The move apply_elo_on_completion really applies also scales with the
-- rating difference of the two teams: beating a stronger team pays up to 2.5x, beating a much weaker one pays down to
-- 0.4x, losing to a weaker team costs up to 2.5x, losing to a stronger one costs less.
--
-- preview_match_rating_delta(team, opponent, type) returns what the trigger would apply to p_team_id today if it
-- played p_opponent_team_id: the same formulas and the same rounding, then the same catch-up for p_team_id's own roster.
-- The hidden power itself never leaves the database, only the three resulting numbers do (as before).
-- Unknown team ids return no rows (the app then shows nothing instead of invented numbers).
--
-- Additive: one new function. preview_team_rating_delta and everything else are untouched, so installed apps keep
-- working. Safe to run twice. Undo: rollback_preview_match_rating_delta.sql (drops the function).

set local lock_timeout = '3s';

create or replace function public.preview_match_rating_delta(
  p_team_id uuid,
  p_opponent_team_id uuid,
  p_match_type text)
returns table(win_delta integer, draw_delta integer, loss_delta integer)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  k integer;
  v_rating integer;
  v_opp_rating integer;
  v_hidden_power numeric;
  v_gap numeric;
  v_mult numeric;
  v_team_gap numeric;
  v_scale numeric;
  v_win integer;
  v_loss integer;
begin
  k := case when p_match_type = 'ranked' then 40 else 20 end;

  select t.rating into v_rating from public.teams t where t.id = p_team_id;
  if not found then
    return;
  end if;
  select t.rating into v_opp_rating from public.teams t where t.id = p_opponent_team_id;
  if not found then
    return;
  end if;

  select avg(u.elo) into v_hidden_power
    from public.team_members tm join public.users u on u.id = tm.user_id
    where tm.team_id = p_team_id;
  v_hidden_power := coalesce(v_hidden_power, 1500);

  -- this team's own catch-up, exactly as apply_elo_on_completion computes it
  v_gap := v_hidden_power - v_rating;
  v_mult := 1 + least(abs(v_gap) / 200.0, 1.5);

  -- the base move, from this team's side (the trigger works from the home side; the result is symmetric)
  v_team_gap := v_rating - v_opp_rating;
  v_scale := 1 + least(greatest(abs(v_team_gap) - 100, 0) / 300.0, 1.5);
  if v_team_gap >= 0 then
    v_win := round(k / v_scale);
  else
    v_win := round(k * v_scale);
  end if;
  if v_team_gap > 0 then
    v_loss := -round(k * v_scale);
  else
    v_loss := -round(k / v_scale);
  end if;

  -- the catch-up only amplifies a move that also closes the gap to the roster's real power
  if v_win > 0 and v_gap > 0 then
    v_win := round(v_win * v_mult);
  end if;
  if v_loss < 0 and v_gap < 0 then
    v_loss := round(v_loss * v_mult);
  end if;

  win_delta := v_win;
  draw_delta := 0;
  loss_delta := v_loss;
  return next;
end;
$function$;

revoke all on function public.preview_match_rating_delta(uuid, uuid, text) from public;
revoke all on function public.preview_match_rating_delta(uuid, uuid, text) from anon;
grant execute on function public.preview_match_rating_delta(uuid, uuid, text) to authenticated, service_role;

comment on function public.preview_match_rating_delta(uuid, uuid, text) is
  'Pitch Power change p_team_id would get today for a win / draw / loss against p_opponent_team_id (same formulas as apply_elo_on_completion, incl. the roster catch-up). Added 2026-11-01.';
