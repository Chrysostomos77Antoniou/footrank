-- Security audit hardening: FR-M3, FR-M4, FR-M5.
--
-- FR-M3  teams.logo_url was unvalidated, so a captain could make every viewer's
--        phone fetch an arbitrary URL (IP/user-agent tracking, offensive
--        content). It must now point at this project's public `avatars` bucket,
--        exactly like users.avatar_url (validate_avatar_url).
--
-- FR-M4  Notification / push spam:
--        * only a team's CAPTAIN may create a match request (the old policy let
--          any member insert one, which fanned out a notification to captains);
--        * match-request notifications only reach captains whose team rating is
--          within 50 points of the requesting team (both broadcast triggers);
--        * invitations, join requests, match requests and push_debug_log are
--          rate limited per user (and invitations per target user).
--
-- FR-M5  behavior_reports: a captain could rate any opposing player for any
--        match whose scheduled time had passed, including matches never played.
--        The match must now be confirmed or completed and the target must be on
--        that match's roster and not marked absent.
--
-- Rate limiting uses the existing public.check_rate_limit() (service-definer),
-- so the triggers below are SECURITY DEFINER. They only apply to client calls
-- (auth.uid() is not null); server-side inserts (service role, cron) are exempt.

-- ---------------------------------------------------------------- FR-M3 --
create or replace function public.validate_team_logo_url()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.logo_url is not null
     and new.logo_url not like
       'https://yspccychuwvlrjgioqss.supabase.co/storage/v1/object/public/avatars/%' then
    raise exception 'logo_url must be an uploaded team logo';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_team_logo on public.teams;
create trigger trg_validate_team_logo
  before insert or update of logo_url on public.teams
  for each row execute function public.validate_team_logo_url();

-- ---------------------------------------------------------------- FR-M4 --

-- Only the captain of a team may open a match request for it.
drop policy if exists "Team member can create match request" on public.match_requests;
drop policy if exists "Captain can create match request" on public.match_requests;
create policy "Captain can create match request"
  on public.match_requests for insert to authenticated
  with check (
    captain_id = (select auth.uid())
    and exists (
      select 1 from public.teams t
       where t.id = match_requests.team_id
         and t.captain_id = (select auth.uid())
    )
  );

-- Match-request broadcast: only captains of teams within 50 rating points of
-- the team that opened the request. Still honours the operational kill switch.
create or replace function public.notify_match_request()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_rating integer;
begin
  if not config_flag('match_request_broadcast_enabled', true) then
    return new;
  end if;

  select coalesce(t.rating, 1500) into v_rating
    from public.teams t where t.id = new.team_id;
  v_rating := coalesce(v_rating, 1500);

  insert into public.notifications(user_id, type, title, body, reference_id)
  select t.captain_id, 'match_request', 'New match nearby',
         new.city || ' · ' || to_char(new.scheduled_at, 'DD Mon HH24:MI') ||
         ' · ' || new.match_type, new.id
  from public.teams t
  where lower(t.city) = lower(new.city)
    and t.id <> new.team_id
    and t.captain_id is not null
    and t.disbanded_at is null
    and abs(coalesce(t.rating, 1500) - v_rating) <= 50;
  return new;
end;
$function$;

-- "Opponent found" cross-notification: same 50-point ceiling, on top of the
-- existing max_allowed_rating_gap() rule (whichever is stricter wins).
create or replace function public.notify_matching_opponents()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_rating int;
  v_captain uuid;
  v_name text;
  r record;
begin
  if not config_flag('match_request_broadcast_enabled', true) then
    return new;
  end if;

  if new.status <> 'searching' then
    return new;
  end if;

  select coalesce(t.rating, 1500), t.captain_id, t.name
    into v_rating, v_captain, v_name
  from teams t where t.id = new.team_id;

  for r in
    select t.captain_id as opp_captain, t.name as opp_name
    from match_requests mr
    join teams t on t.id = mr.team_id
    where mr.status = 'searching'
      and mr.team_id <> new.team_id
      and mr.id <> new.id
      and mr.city ilike new.city
      and mr.scheduled_at > now() - interval '2 hours'
      and mr.scheduled_at between new.scheduled_at - interval '60 minutes'
                              and new.scheduled_at + interval '60 minutes'
      and abs(coalesce(t.rating, 1500) - v_rating) <= 50
      and abs(coalesce(t.rating, 1500) - v_rating) <= public.max_allowed_rating_gap(mr.id, mr.team_id, mr.city, mr.scheduled_at)
      and t.captain_id is not null
      and t.disbanded_at is null
  loop
    insert into notifications (user_id, type, title, body, read, reference_id)
    values (r.opp_captain, 'opponent_found', 'Opponent available',
      coalesce(v_name, 'A team') || ' is looking for a match in ' || new.city ||
      '. Open Matches to confirm.', false, new.id);
    if v_captain is not null then
      insert into notifications (user_id, type, title, body, read, reference_id)
      values (v_captain, 'opponent_found', 'Opponent found',
        coalesce(r.opp_name, 'A team') || ' is available in ' || new.city ||
        '. Open Matches to confirm.', false, new.id);
    end if;
  end loop;

  return new;
end;
$function$;

-- Rate limits (client-originated writes only).
create or replace function public.enforce_invitation_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  -- A captain can send at most 20 invitations an hour...
  if not public.check_rate_limit('invite:' || auth.uid()::text, 20, 3600) then
    raise exception 'rate_limited: too many invitations, try again later';
  end if;
  -- ...and no player can be invited more than 5 times a day by anyone.
  if not public.check_rate_limit('invite_target:' || new.user_id::text, 5, 86400) then
    raise exception 'rate_limited: this player has received too many invitations today';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_invitation_rate_limit on public.team_invitations;
create trigger trg_invitation_rate_limit
  before insert on public.team_invitations
  for each row execute function public.enforce_invitation_rate_limit();

create or replace function public.enforce_join_request_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if not public.check_rate_limit('join_request:' || auth.uid()::text, 20, 3600) then
    raise exception 'rate_limited: too many join requests, try again later';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_join_request_rate_limit on public.team_join_requests;
create trigger trg_join_request_rate_limit
  before insert on public.team_join_requests
  for each row execute function public.enforce_join_request_rate_limit();

create or replace function public.enforce_match_request_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if not public.check_rate_limit('match_request:' || auth.uid()::text, 10, 3600) then
    raise exception 'rate_limited: too many match requests, try again later';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_match_request_rate_limit on public.match_requests;
create trigger trg_match_request_rate_limit
  before insert on public.match_requests
  for each row execute function public.enforce_match_request_rate_limit();

-- push_debug_log is a diagnostics trail the app writes to best-effort. Cap it
-- instead of removing it: 20 rows an hour per user, message truncated. Over the
-- cap the row is silently dropped (the client ignores failures anyway).
create or replace function public.cap_push_debug_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if not public.check_rate_limit('push_debug:' || auth.uid()::text, 20, 3600) then
    return null;
  end if;
  new.message := left(new.message, 500);
  return new;
end;
$$;

drop trigger if exists trg_cap_push_debug_log on public.push_debug_log;
create trigger trg_cap_push_debug_log
  before insert on public.push_debug_log
  for each row execute function public.cap_push_debug_log();

-- Trigger functions are not meant to be called as RPCs.
revoke execute on function public.validate_team_logo_url() from public, anon, authenticated;
revoke execute on function public.enforce_invitation_rate_limit() from public, anon, authenticated;
revoke execute on function public.enforce_join_request_rate_limit() from public, anon, authenticated;
revoke execute on function public.enforce_match_request_rate_limit() from public, anon, authenticated;
revoke execute on function public.cap_push_debug_log() from public, anon, authenticated;

-- ---------------------------------------------------------------- FR-M5 --
-- The match must be confirmed or completed (never pending/cancelled), and the
-- target must be on that match's roster and not marked absent.
--
-- Deliberately NOT "completed only": the app unlocks behaviour ratings 90
-- minutes after kick-off, which is before the two captains' scores have agreed
-- (completion), so requiring completion would block ratings for exactly the
-- matches where the opponent is slow to submit.
drop policy if exists "Opponent captain can rate" on public.behavior_reports;
drop policy if exists "Opponent captain can update their rating" on public.behavior_reports;

create policy "Opponent captain can rate"
  on public.behavior_reports for insert to authenticated
  with check (
    rater_id = (select auth.uid())
    and exists (
      select 1
        from public.matches m
        join public.teams my on my.captain_id = (select auth.uid())
        join public.team_members tm on tm.user_id = behavior_reports.target_user_id
       where m.id = behavior_reports.match_id
         and m.status in ('confirmed', 'completed')
         and (my.id = m.home_team_id or my.id = m.away_team_id)
         and (tm.team_id = m.home_team_id or tm.team_id = m.away_team_id)
         and tm.team_id <> my.id
         and m.scheduled_at <= now()
    )
    and exists (
      select 1 from public.match_players mp
       where mp.match_id = behavior_reports.match_id
         and mp.user_id = behavior_reports.target_user_id
         and mp.attended is distinct from false
    )
  );

create policy "Opponent captain can update their rating"
  on public.behavior_reports for update to authenticated
  using (rater_id = (select auth.uid()))
  with check (
    rater_id = (select auth.uid())
    and now() < created_at + interval '72 hours'
    and exists (
      select 1
        from public.matches m
        join public.teams my on my.captain_id = (select auth.uid())
        join public.team_members tm on tm.user_id = behavior_reports.target_user_id
       where m.id = behavior_reports.match_id
         and m.status in ('confirmed', 'completed')
         and (my.id = m.home_team_id or my.id = m.away_team_id)
         and (tm.team_id = m.home_team_id or tm.team_id = m.away_team_id)
         and tm.team_id <> my.id
    )
    and exists (
      select 1 from public.match_players mp
       where mp.match_id = behavior_reports.match_id
         and mp.user_id = behavior_reports.target_user_id
         and mp.attended is distinct from false
    )
  );
