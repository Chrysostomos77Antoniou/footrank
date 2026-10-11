-- A team's STARTING Pwr is the average Pwr of its roster, not a flat 1500:
--   start = round( sum(player Pwr) / number of players )
-- for any roster size (5 players -> sum / 5, 6 players -> sum / 6, ...).
--
-- That starting value follows the roster (players joining / leaving, or a
-- member's own Pwr changing) ONLY until the team plays its first completed
-- match. From the first completed match on, teams.rating works exactly as it
-- did before: it moves with match results (apply_elo_on_completion, unchanged).
--
-- Teams that have already played are never touched.

create or replace function public.seed_team_pwr(p_team_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_avg numeric;
begin
  -- Already played? Then the rating is match-driven; leave it alone.
  if exists (
    select 1 from public.matches m
     where m.status = 'completed'
       and (m.home_team_id = p_team_id or m.away_team_id = p_team_id)
  ) then
    return;
  end if;

  select avg(u.elo) into v_avg
    from public.team_members tm
    join public.users u on u.id = tm.user_id
   where tm.team_id = p_team_id;

  if v_avg is not null then
    update public.teams
       set rating = round(v_avg)::int
     where id = p_team_id
       and disbanded_at is null
       and rating is distinct from round(v_avg)::int;
  end if;
end;
$$;
revoke execute on function public.seed_team_pwr(uuid) from public, anon, authenticated;

create or replace function public.seed_team_pwr_on_roster_change()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if tg_op = 'DELETE' then
    perform public.seed_team_pwr(old.team_id);
    return old;
  end if;
  perform public.seed_team_pwr(new.team_id);
  return new;
end;
$$;
revoke execute on function public.seed_team_pwr_on_roster_change() from public, anon, authenticated;

create or replace function public.seed_team_pwr_on_user_elo()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_team uuid;
begin
  for v_team in select team_id from public.team_members where user_id = new.id loop
    perform public.seed_team_pwr(v_team);
  end loop;
  return new;
end;
$$;
revoke execute on function public.seed_team_pwr_on_user_elo() from public, anon, authenticated;

drop trigger if exists trg_seed_team_pwr_on_roster_change on public.team_members;
create trigger trg_seed_team_pwr_on_roster_change
  after insert or delete on public.team_members
  for each row execute function public.seed_team_pwr_on_roster_change();

drop trigger if exists trg_seed_team_pwr_on_user_elo on public.users;
create trigger trg_seed_team_pwr_on_user_elo
  after update of elo on public.users
  for each row when (old.elo is distinct from new.elo)
  execute function public.seed_team_pwr_on_user_elo();

-- One-off: teams that exist today but have not played yet get their starting
-- value now (only affects teams with no completed match).
do $$
declare
  v_team uuid;
begin
  for v_team in
    select t.id from public.teams t
     where t.disbanded_at is null
       and not exists (
         select 1 from public.matches m
          where m.status = 'completed'
            and (m.home_team_id = t.id or m.away_team_id = t.id))
  loop
    perform public.seed_team_pwr(v_team);
  end loop;
end;
$$;
