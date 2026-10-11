-- Team Pwr is now simply the average Pwr of everyone on the roster:
--   team Pwr = round( sum(player Pwr) / number of players )
-- for any roster size (5 players -> sum / 5, 6 players -> sum / 6, ...).
--
-- Before this, teams.rating was a separate score that moved on its own after
-- each match (with a "hidden power" catch-up bonus). Now teams.rating is a
-- derived value that the database keeps in sync with users.elo (the player
-- Pwr), so rankings, matchmaking windows and every badge in the app, which
-- all read teams.rating, automatically show the roster average.
--
-- It is recomputed whenever:
--   * someone joins or leaves a team (team_members insert / delete), and
--   * a player's Pwr changes (match result, Pwr quiz, cancel penalty, ...).
--
-- The old ratings are kept in team_rating_backup_20261011 (service role only).

-- 1. Safety copy of the old ratings -----------------------------------------
create table if not exists public.team_rating_backup_20261011 as
  select id as team_id, rating as old_rating, now() as saved_at from public.teams;
alter table public.team_rating_backup_20261011 enable row level security;
revoke all on public.team_rating_backup_20261011 from public, anon, authenticated;

-- 2. Recompute helper ---------------------------------------------------------
create or replace function public.recompute_team_pwr(p_team_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_avg numeric;
begin
  select avg(u.elo) into v_avg
    from public.team_members tm
    join public.users u on u.id = tm.user_id
   where tm.team_id = p_team_id;
  -- An empty roster keeps its last value.
  if v_avg is not null then
    update public.teams
       set rating = round(v_avg)::int
     where id = p_team_id
       and rating is distinct from round(v_avg)::int;
  end if;
end;
$$;
revoke execute on function public.recompute_team_pwr(uuid) from public, anon, authenticated;

-- 3. Match completion: player Pwr moves as before; team Pwr follows from it --
create or replace function public.apply_elo_on_completion()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  k integer;
  home_actual numeric;
  away_actual numeric;
  home_avg numeric;
  away_avg numeric;
  home_expected numeric;
  away_expected numeric;
  home_delta integer;
  away_delta integer;
  v_attended_change integer;
  v_noshow_change integer;
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    k := case when new.match_type = 'ranked' then 40 else 20 end;
    if new.home_score > new.away_score then home_actual:=1; away_actual:=0;
    elsif new.home_score < new.away_score then home_actual:=0; away_actual:=1;
    else home_actual:=0.5; away_actual:=0.5; end if;

    select avg(u.elo) into home_avg
      from public.match_players mp join public.users u on u.id = mp.user_id
      where mp.match_id = new.id and mp.team_id = new.home_team_id and mp.attended = true;
    select avg(u.elo) into away_avg
      from public.match_players mp join public.users u on u.id = mp.user_id
      where mp.match_id = new.id and mp.team_id = new.away_team_id and mp.attended = true;
    home_avg := coalesce(home_avg, 1500);
    away_avg := coalesce(away_avg, 1500);

    home_expected := 1.0 / (1.0 + power(10, (away_avg - home_avg) / 400.0));
    away_expected := 1.0 / (1.0 + power(10, (home_avg - away_avg) / 400.0));
    home_delta := round(k * (home_actual - home_expected));
    away_delta := round(k * (away_actual - away_expected));

    update public.users u set elo = u.elo + home_delta, matches_played = u.matches_played + 1
      from public.match_players mp
      where mp.match_id = new.id and mp.team_id = new.home_team_id and mp.attended = true
        and mp.user_id = u.id;
    update public.users u set elo = u.elo + away_delta, matches_played = u.matches_played + 1
      from public.match_players mp
      where mp.match_id = new.id and mp.team_id = new.away_team_id and mp.attended = true
        and mp.user_id = u.id;

    -- Team Pwr is derived from the roster average (trg_team_pwr_on_user_elo),
    -- so it is no longer adjusted directly here.

    select value_change into v_attended_change from public.reliability_config where event_type='attended';
    select value_change into v_noshow_change from public.reliability_config where event_type='no_show';
    v_attended_change := coalesce(v_attended_change,0);
    v_noshow_change := coalesce(v_noshow_change,0);
    update public.users u set reliability=greatest(0,least(100,u.reliability+v_attended_change))
      from public.match_players mp where mp.match_id=new.id and mp.user_id=u.id and mp.attended=true;
    update public.users u set reliability=greatest(0,least(100,u.reliability+v_noshow_change))
      from public.match_players mp where mp.match_id=new.id and mp.user_id=u.id and mp.attended=false;
  end if;
  return new;
end;
$$;

-- 4. "Pitch Power at stake" preview ------------------------------------------
-- Projected change of the roster average for an evenly matched opponent: each
-- attending player moves by about k/2 for a win (-k/2 for a loss, 0 for a
-- draw), and only up to 5 players play, so the average moves by
-- (players who play / roster size) of that.
create or replace function public.preview_team_rating_delta(p_team_id uuid, p_match_type text)
returns table(win_delta integer, draw_delta integer, loss_delta integer)
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  k integer;
  v_roster integer;
  v_factor numeric;
begin
  k := case when p_match_type = 'ranked' then 40 else 20 end;
  select count(*) into v_roster from public.team_members where team_id = p_team_id;
  v_factor := case when v_roster <= 0 then 1 else least(5, v_roster)::numeric / v_roster end;
  win_delta := round(k * 0.5 * v_factor);
  loss_delta := -round(k * 0.5 * v_factor);
  draw_delta := 0;
  return next;
end;
$$;

-- 5. Triggers keep teams.rating in sync ---------------------------------------
create or replace function public.team_pwr_on_roster_change()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if tg_op = 'DELETE' then
    perform public.recompute_team_pwr(old.team_id);
    return old;
  end if;
  perform public.recompute_team_pwr(new.team_id);
  return new;
end;
$$;
revoke execute on function public.team_pwr_on_roster_change() from public, anon, authenticated;

create or replace function public.team_pwr_on_user_elo()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_team uuid;
begin
  for v_team in select team_id from public.team_members where user_id = new.id loop
    perform public.recompute_team_pwr(v_team);
  end loop;
  return new;
end;
$$;
revoke execute on function public.team_pwr_on_user_elo() from public, anon, authenticated;

drop trigger if exists trg_team_pwr_on_roster_change on public.team_members;
create trigger trg_team_pwr_on_roster_change
  after insert or delete on public.team_members
  for each row execute function public.team_pwr_on_roster_change();

drop trigger if exists trg_team_pwr_on_user_elo on public.users;
create trigger trg_team_pwr_on_user_elo
  after update of elo on public.users
  for each row when (old.elo is distinct from new.elo)
  execute function public.team_pwr_on_user_elo();

-- 6. One-off backfill: set every active team to its current roster average ----
update public.teams t
   set rating = s.r
  from (
    select tm.team_id, round(avg(u.elo))::int as r
      from public.team_members tm
      join public.users u on u.id = tm.user_id
     group by tm.team_id
  ) s
 where t.id = s.team_id
   and t.disbanded_at is null
   and t.rating is distinct from s.r;
