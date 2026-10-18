-- Match rosters: captains/vice-captains pick who is playing BEFORE the match.
-- match_players.attended = true means "on the roster". The roster can be edited
-- until kick-off (min 5 players) and replaces the old post-match attendance
-- marking. Not being on the roster no longer costs reliability or PWR.

alter table public.match_requests
  add column if not exists roster_user_ids uuid[];
alter table public.match_request_proposals
  add column if not exists roster_user_ids uuid[];

-- Validate a roster supplied on a request / proposal (>=5, all team members).
create or replace function public.validate_roster_ids()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_team uuid;
  v_ids uuid[];
begin
  if new.roster_user_ids is null then
    return new;
  end if;
  v_team := case when tg_table_name = 'match_requests'
                 then new.team_id else new.proposing_team_id end;
  select array_agg(distinct x) into v_ids from unnest(new.roster_user_ids) x;
  if coalesce(array_length(v_ids, 1), 0) < 5 then
    raise exception 'ROSTER_MIN: a match roster needs at least 5 players';
  end if;
  if exists (
    select 1 from unnest(v_ids) x
    where not exists (
      select 1 from public.team_members tm
      where tm.team_id = v_team and tm.user_id = x)
  ) then
    raise exception 'Roster can only contain members of the team';
  end if;
  new.roster_user_ids := v_ids;
  return new;
end;
$$;

create trigger trg_validate_request_roster
  before insert or update of roster_user_ids on public.match_requests
  for each row execute function public.validate_roster_ids();

create trigger trg_validate_proposal_roster
  before insert or update of roster_user_ids on public.match_request_proposals
  for each row execute function public.validate_roster_ids();

-- Internal helper: write a team's roster into match_players. Falls back to the
-- whole team when fewer than 5 valid ids are given.
create or replace function public.apply_team_roster(
  p_match_id uuid, p_team_id uuid, p_ids uuid[], p_by uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v uuid[];
begin
  select coalesce(array_agg(tm.user_id), '{}') into v
    from public.team_members tm
   where tm.team_id = p_team_id
     and p_ids is not null and tm.user_id = any(p_ids);
  if cardinality(v) < 5 then
    select coalesce(array_agg(tm.user_id), '{}') into v
      from public.team_members tm where tm.team_id = p_team_id;
  end if;
  insert into public.match_players (match_id, user_id, team_id, attended, marked_by)
  select p_match_id, tm.user_id, tm.team_id, tm.user_id = any(v), p_by
    from public.team_members tm
   where tm.team_id = p_team_id
  on conflict (match_id, user_id)
  do update set attended = excluded.attended, marked_by = excluded.marked_by;
end;
$$;
revoke all on function public.apply_team_roster(uuid, uuid, uuid[], uuid) from public, anon, authenticated;

-- New confirmed match: home roster comes from the request, away defaults to the
-- whole team until the accepted proposal's roster is applied (below).
create or replace function public.apply_rosters_on_match_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_home_ids uuid[];
begin
  if new.status = 'confirmed' then
    select roster_user_ids into v_home_ids
      from public.match_requests where id = new.request_id;
    perform public.apply_team_roster(new.id, new.home_team_id, v_home_ids, null);
    perform public.apply_team_roster(new.id, new.away_team_id, null, null);
  end if;
  return new;
end;
$$;
revoke all on function public.apply_rosters_on_match_insert() from public, anon, authenticated;

create trigger trg_apply_rosters_on_match_insert
  after insert on public.matches
  for each row execute function public.apply_rosters_on_match_insert();

-- Accepted proposal: apply the proposing (away) team's chosen roster.
create or replace function public.apply_proposal_roster()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match uuid;
begin
  if new.status = 'accepted' and old.status is distinct from 'accepted'
     and new.roster_user_ids is not null then
    select id into v_match from public.matches
     where request_id = new.request_id and away_team_id = new.proposing_team_id
       and status = 'confirmed'
     order by created_at desc limit 1;
    if v_match is not null then
      perform public.apply_team_roster(v_match, new.proposing_team_id,
        new.roster_user_ids, null);
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.apply_proposal_roster() from public, anon, authenticated;

create trigger trg_apply_proposal_roster
  after update of status on public.match_request_proposals
  for each row execute function public.apply_proposal_roster();

-- Propose with a roster (captain / vice-captain of the proposing team).
create or replace function public.propose_match_with_roster(
  p_request_id uuid, p_team_id uuid, p_roster_user_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not exists (
    select 1 from public.team_members tm
     where tm.team_id = p_team_id and tm.user_id = auth.uid()
       and tm.role in ('captain', 'vice_captain')
  ) then
    raise exception 'Only the captain or vice-captain can choose the roster';
  end if;
  v_id := public.propose_match(p_request_id, p_team_id);
  update public.match_request_proposals
     set roster_user_ids = p_roster_user_ids
   where id = v_id;
  return v_id;
end;
$$;
revoke all on function public.propose_match_with_roster(uuid, uuid, uuid[]) from public, anon;
grant execute on function public.propose_match_with_roster(uuid, uuid, uuid[]) to authenticated;

-- Edit a team's roster for a confirmed match, until kick-off.
create or replace function public.set_match_roster(
  p_match_id uuid, p_team_id uuid, p_user_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  m public.matches;
  v_ids uuid[];
begin
  select * into m from public.matches where id = p_match_id for update;
  if m.id is null then raise exception 'Match not found'; end if;
  if p_team_id is distinct from m.home_team_id and p_team_id is distinct from m.away_team_id then
    raise exception 'That team is not part of this match';
  end if;
  if not exists (
    select 1 from public.team_members tm
     where tm.team_id = p_team_id and tm.user_id = auth.uid()
       and tm.role in ('captain', 'vice_captain')
  ) then
    raise exception 'Only the captain or vice-captain can edit the roster';
  end if;
  if m.status <> 'confirmed' then
    raise exception 'The roster can only be changed for an upcoming match';
  end if;
  if now() >= m.scheduled_at then
    raise exception 'ROSTER_LOCKED: the match has kicked off, the roster can no longer be changed';
  end if;
  select array_agg(distinct x) into v_ids from unnest(p_user_ids) x;
  if coalesce(array_length(v_ids, 1), 0) < 5 then
    raise exception 'ROSTER_MIN: a match roster needs at least 5 players';
  end if;
  if exists (
    select 1 from unnest(v_ids) x
    where not exists (
      select 1 from public.team_members tm
      where tm.team_id = p_team_id and tm.user_id = x)
  ) then
    raise exception 'Roster can only contain members of the team';
  end if;
  perform public.apply_team_roster(p_match_id, p_team_id, v_ids, auth.uid());
end;
$$;
revoke all on function public.set_match_roster(uuid, uuid, uuid[]) from public, anon;
grant execute on function public.set_match_roster(uuid, uuid, uuid[]) to authenticated;

-- Clients may no longer write match_players directly: the roster is only
-- changeable through set_match_roster (which enforces the kick-off lock).
create or replace function public.block_direct_match_player_writes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    raise exception 'The match roster is edited from the match page. Please update the app.';
  end if;
  return new;
end;
$$;
create trigger trg_block_direct_match_player_writes
  before insert or update on public.match_players
  for each row execute function public.block_direct_match_player_writes();

-- No-shows are no longer tracked: remove the reliability penalty for
-- attended = false from the rating trigger (attended = on the roster).
do $$
declare
  d text;
  d2 text;
begin
  d := pg_get_functiondef('public.apply_elo_on_completion'::regproc);
  d2 := replace(d,
    E'    update public.users u set reliability=greatest(0,least(100,u.reliability+v_noshow_change))\n      from public.match_players mp where mp.match_id=new.id and mp.user_id=u.id and mp.attended=false;\n',
    '');
  if d2 = d then
    raise exception 'apply_elo_on_completion: no-show penalty block not found';
  end if;
  execute d2;
end;
$$;

-- Score submission wording: roster instead of attendance.
create or replace function public.submit_match_score(p_match_id uuid, p_home_score integer, p_away_score integer)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  m public.matches; v_is_home boolean; v_is_away boolean;
  v_hh integer; v_ha integer; v_ah integer; v_aa integer;
  v_out_home integer; v_out_away integer; v_home_cap uuid; v_away_cap uuid;
  v_home_cnt integer; v_away_cnt integer; v_rounds integer; v_win_h integer; v_win_a integer;
  v_my_team_id uuid;
  v_attended_count integer;
begin
  select * into m from public.matches where id=p_match_id for update;
  if m.id is null then raise exception 'Match not found'; end if;
  if m.status = 'completed' then raise exception 'Match already completed'; end if;
  if m.status <> 'confirmed' then raise exception 'Match must be confirmed by both captains first'; end if;
  if now() < m.scheduled_at + interval '90 minutes' then
    raise exception 'Score can be submitted 90 minutes after kick-off';
  end if;
  if p_home_score < 0 or p_away_score < 0 then raise exception 'Scores must be zero or greater'; end if;
  v_is_home := exists (select 1 from public.teams where id=m.home_team_id and captain_id=auth.uid());
  v_is_away := exists (select 1 from public.teams where id=m.away_team_id and captain_id=auth.uid());
  if not (v_is_home or v_is_away) then raise exception 'Only a team captain can submit a score'; end if;

  v_my_team_id := case when v_is_home then m.home_team_id else m.away_team_id end;
  select count(*) into v_attended_count
    from public.match_players
   where match_id = p_match_id and team_id = v_my_team_id and attended = true;
  if v_attended_count < 5 then
    raise exception 'ATTENDANCE_REQUIRED: your team needs a roster of at least 5 players before submitting a score';
  end if;

  if v_is_home then
    update public.matches set home_report_h=p_home_score, home_report_a=p_away_score,
      score_proposed_by=auth.uid(), score_disputed=false where id=p_match_id;
  else
    update public.matches set away_report_h=p_home_score, away_report_a=p_away_score,
      score_proposed_by=auth.uid(), score_disputed=false where id=p_match_id;
  end if;
  select home_report_h, home_report_a, away_report_h, away_report_a into v_hh,v_ha,v_ah,v_aa
    from public.matches where id=p_match_id;
  if v_hh is null or v_ah is null then return 'awaiting_opponent'; end if;
  v_out_home := case when v_hh>v_ha then 1 when v_hh<v_ha then -1 else 0 end;
  v_out_away := case when v_ah>v_aa then 1 when v_ah<v_aa then -1 else 0 end;
  if v_out_home = v_out_away then
    update public.matches set home_score=v_hh, away_score=v_ha, home_confirmed=true, away_confirmed=true,
      score_disputed=false, status='completed' where id=p_match_id;
    return 'completed';
  end if;
  select captain_id into v_home_cap from public.teams where id=m.home_team_id;
  select captain_id into v_away_cap from public.teams where id=m.away_team_id;
  update public.matches set dispute_rounds=dispute_rounds+1, score_disputed=true
    where id=p_match_id returning dispute_rounds into v_rounds;
  update public.users set dispute_count=dispute_count+1 where id in (v_home_cap, v_away_cap);
  perform public.flag_captain_if_needed(v_home_cap);
  perform public.flag_captain_if_needed(v_away_cap);
  if v_rounds >= 2 then
    select dispute_count into v_home_cnt from public.users where id=v_home_cap;
    select dispute_count into v_away_cnt from public.users where id=v_away_cap;
    if v_home_cnt <= v_away_cnt then v_win_h:=v_hh; v_win_a:=v_ha; else v_win_h:=v_ah; v_win_a:=v_aa; end if;
    update public.matches set home_score=v_win_h, away_score=v_win_a, home_confirmed=true, away_confirmed=true,
      score_disputed=false, status='completed' where id=p_match_id;
    return 'resolved';
  end if;
  return 'disputed';
end;
$$;
