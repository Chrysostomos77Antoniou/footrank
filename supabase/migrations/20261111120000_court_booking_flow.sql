-- Court booking responsibility flow.
--
-- FootRank does not partner with courts. Once a match is confirmed exactly one
-- team (the Booker) must book the court and tap "I booked it" before the
-- deadline, or the match cancels itself and the Booker's team loses
-- reliability points.
--
-- Rules:
--   * Booker = the team whose venue it is: the requesting team, or the
--     proposing team when its own venue was accepted. The other captain can
--     take it over with "I'll book it".
--   * Deadline = kick-off - 30 min. If the court is changed (or the match is
--     confirmed) in the last hour before kick-off: kick-off - 15 min.
--   * A match cannot be confirmed less than 20 minutes before kick-off, and no
--     court changes can be suggested in the last 20 minutes.
--   * "Court full": either captain suggests another court (max 3 per team per
--     match, one open at a time). Accept = new court, suggester becomes the
--     Booker, status resets. 3 declined suggestions in one match = cancelled,
--     no penalty. A suggestion still open at kick-off - 15 min = cancelled, no
--     penalty.
--   * The kick-off time can no longer be changed.

-- ---------------------------------------------------------------------------
-- 0. Payments are gone: stop the old payment jobs (one of them deleted
--    unpaid matches).
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job
     where jobname in ('payment-deadline-sweep', 'fee-payment-reminders');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Columns
-- ---------------------------------------------------------------------------
alter table public.matches drop constraint if exists matches_court_booking_status_check;
update public.matches set court_booking_status = 'not_booked' where court_booking_status = 'pending';
alter table public.matches add constraint matches_court_booking_status_check
  check (court_booking_status in ('not_booked', 'booked', 'cancelled_unbooked', 'pending'));
-- ('pending' stays allowed only for the legacy court-pick path in old requests.)

alter table public.matches
  add column if not exists booker_team_id      uuid references public.teams(id) on delete set null,
  add column if not exists booked_at           timestamptz,
  add column if not exists booking_deadline_at timestamptz,
  add column if not exists reminder_1h_sent    boolean not null default false,
  add column if not exists venue_change_open   boolean not null default false;

alter table public.teams
  add column if not exists reliability_score integer not null default 100,
  add column if not exists unbooked_cancels  integer not null default 0;

-- ---------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------
create table if not exists public.venue_suggestions (
  id                   uuid primary key default gen_random_uuid(),
  match_id             uuid not null references public.matches(id) on delete cascade,
  suggested_by_team_id uuid not null references public.teams(id) on delete cascade,
  venue_text           text not null check (char_length(venue_text) between 2 and 60),
  venue_place_id       text check (venue_place_id is null or (char_length(venue_place_id) <= 300 and venue_place_id ~ '^[A-Za-z0-9_-]+$')),
  venue_lat            double precision check (venue_lat is null or venue_lat between -90 and 90),
  venue_lng            double precision check (venue_lng is null or venue_lng between -180 and 180),
  venue_source         text check (venue_source in ('google', 'manual')),
  status               text not null default 'pending'
                       check (status in ('pending', 'accepted', 'declined', 'superseded')),
  created_at           timestamptz not null default now(),
  responded_at         timestamptz
);
create unique index if not exists venue_suggestions_one_pending
  on public.venue_suggestions(match_id) where status = 'pending';
create index if not exists venue_suggestions_match on public.venue_suggestions(match_id);

-- Timeline. The payload holds names only, never Google coordinates.
create table if not exists public.match_events (
  id         uuid primary key default gen_random_uuid(),
  match_id   uuid not null references public.matches(id) on delete cascade,
  team_id    uuid references public.teams(id) on delete set null,
  type       text not null check (type in (
               'confirmed', 'booker_claimed', 'booked', 'venue_suggested',
               'venue_accepted', 'venue_declined', 'reminder_sent', 'auto_cancelled')),
  payload    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists match_events_match on public.match_events(match_id, created_at);

alter table public.venue_suggestions enable row level security;
alter table public.match_events enable row level security;

create or replace function public.is_match_member(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.matches m
      join public.team_members tm on tm.team_id in (m.home_team_id, m.away_team_id)
     where m.id = p_match_id and tm.user_id = auth.uid());
$$;

drop policy if exists "members read venue suggestions" on public.venue_suggestions;
create policy "members read venue suggestions" on public.venue_suggestions
  for select to authenticated using (public.is_match_member(match_id));
drop policy if exists "members read match events" on public.match_events;
create policy "members read match events" on public.match_events
  for select to authenticated using (public.is_match_member(match_id));
revoke insert, update, delete on public.venue_suggestions, public.match_events from anon, authenticated;
grant select on public.venue_suggestions, public.match_events to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------------------
create or replace function public.booking_deadline_for(p_kickoff timestamptz, p_changed_at timestamptz)
returns timestamptz
language sql
immutable
as $$
  select case when p_changed_at >= p_kickoff - interval '60 minutes'
              then p_kickoff - interval '15 minutes'
              else p_kickoff - interval '30 minutes' end;
$$;

create or replace function public.booking_notify(
  p_team_id uuid, p_type text, p_title text, p_body text, p_match_id uuid
) returns void
language sql
security definer
set search_path = public
as $$
  insert into public.notifications (user_id, type, title, body, read, reference_id)
  select t.captain_id, p_type, p_title, p_body, false, p_match_id
    from public.teams t where t.id = p_team_id and t.captain_id is not null;
$$;

create or replace function public.booking_local_time(p_ts timestamptz)
returns text
language sql
immutable
as $$ select to_char(p_ts at time zone 'Asia/Nicosia', 'HH24:MI'); $$;

-- Which of the two teams the caller captains (null if neither).
create or replace function public.booking_my_team(m public.matches)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select t.id from public.teams t
   where t.id in (m.home_team_id, m.away_team_id) and t.captain_id = auth.uid()
   limit 1;
$$;

-- ---------------------------------------------------------------------------
-- 4. When a match becomes confirmed: pick the Booker, set the deadline
-- ---------------------------------------------------------------------------
create or replace function public.trg_match_booking_on_confirm()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status <> 'confirmed' then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'confirmed' then return new; end if;

  if new.scheduled_at < now() + interval '20 minutes' then
    raise exception 'too_late_to_confirm: a match must be confirmed at least 20 minutes before kick-off';
  end if;

  -- The team whose venue it is books it. accept_match_proposal inserts the
  -- match before marking the proposal accepted, so the proposal is still
  -- 'pending' here.
  new.booker_team_id := new.home_team_id;
  if new.request_id is not null and new.venue_text is not null and exists (
       select 1 from public.match_request_proposals p
        where p.request_id = new.request_id
          and p.proposing_team_id = new.away_team_id
          and p.status = 'pending'
          and p.venue_text = new.venue_text) then
    new.booker_team_id := new.away_team_id;
  end if;

  new.court_booking_status := 'not_booked';
  new.booked_at := null;
  new.booking_deadline_at := public.booking_deadline_for(new.scheduled_at, now());
  -- Confirmed inside the last hour: the confirmation push already carries
  -- the deadline, so skip the 1-hour reminder.
  new.reminder_1h_sent := now() >= new.scheduled_at - interval '60 minutes';
  new.venue_change_open := false;
  return new;
end $$;

drop trigger if exists trg_match_booking_on_confirm on public.matches;
create trigger trg_match_booking_on_confirm
  before insert or update of status on public.matches
  for each row execute function public.trg_match_booking_on_confirm();

create or replace function public.trg_match_booking_after_confirm()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_booker text; v_other uuid;
begin
  if new.status <> 'confirmed' or new.booker_team_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'confirmed' then return new; end if;

  select name into v_booker from public.teams where id = new.booker_team_id;
  v_other := case when new.booker_team_id = new.home_team_id then new.away_team_id else new.home_team_id end;

  insert into public.match_events (match_id, team_id, type, payload)
  values (new.id, new.booker_team_id, 'confirmed',
          jsonb_build_object('booker', v_booker, 'venue', new.venue_text));

  perform public.booking_notify(new.booker_team_id, 'booking_booker',
    'You book the court',
    'Book ' || coalesce(new.venue_text, 'the court') || ' and tap "I booked it" by ' ||
      public.booking_local_time(new.booking_deadline_at) || ', or the match cancels.',
    new.id);
  perform public.booking_notify(v_other, 'booking_info',
    coalesce(v_booker, 'The other team') || ' is booking the court',
    'Want to book it yourself? Tap "I''ll book it" on the match.',
    new.id);
  return new;
end $$;

drop trigger if exists trg_match_booking_after_confirm on public.matches;
create trigger trg_match_booking_after_confirm
  after insert or update of status on public.matches
  for each row execute function public.trg_match_booking_after_confirm();

-- ---------------------------------------------------------------------------
-- 5. The kick-off time no longer changes; the venue of a confirmed match only
--    changes through a suggestion the other captain accepts.
-- ---------------------------------------------------------------------------
create or replace function public.reschedule_match(p_match_id uuid, p_scheduled_at timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'The kick-off time of a match cannot be changed';
end $$;

create or replace function public.trg_block_confirmed_venue_edit()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'confirmed' and new.status = 'confirmed'
     and new.venue_text is distinct from old.venue_text
     and coalesce(current_setting('footrank.venue_change_ok', true), '') <> 'on'
     -- Admin moderation may still edit it; only the captains are locked out.
     and exists (select 1 from public.teams t
                  where t.id in (new.home_team_id, new.away_team_id)
                    and t.captain_id = auth.uid()) then
    raise exception 'venue_locked: use "Court full" to suggest another court';
  end if;
  return new;
end $$;

drop trigger if exists trg_block_confirmed_venue_edit on public.matches;
create trigger trg_block_confirmed_venue_edit
  before update of venue_text on public.matches
  for each row execute function public.trg_block_confirmed_venue_edit();

-- ---------------------------------------------------------------------------
-- 6. Actions
-- ---------------------------------------------------------------------------
-- The other captain takes over the booking.
create or replace function public.claim_booking(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare m public.matches; v_me uuid; v_name text; v_old uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select * into m from public.matches where id = p_match_id for update;
  if m.id is null then raise exception 'Match not found'; end if;
  v_me := public.booking_my_team(m);
  if v_me is null then raise exception 'Only a captain of this match can do this'; end if;
  if m.status <> 'confirmed' or m.court_booking_status <> 'not_booked' then
    raise exception 'The court is already booked or the match is over';
  end if;
  if m.booker_team_id = v_me then return; end if;
  if now() >= m.booking_deadline_at then raise exception 'The booking deadline has passed'; end if;

  v_old := m.booker_team_id;
  update public.matches set booker_team_id = v_me where id = p_match_id;
  select name into v_name from public.teams where id = v_me;
  insert into public.match_events (match_id, team_id, type, payload)
  values (p_match_id, v_me, 'booker_claimed', jsonb_build_object('team', v_name));
  perform public.booking_notify(v_old, 'booking_claimed',
    coalesce(v_name, 'The other team') || ' will book the court',
    'You no longer need to book ' || coalesce(m.venue_text, 'the court') || '.', p_match_id);
end $$;

-- The Booker confirms the court is booked.
create or replace function public.confirm_booked(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare m public.matches; v_me uuid; v_name text; v_other uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select * into m from public.matches where id = p_match_id for update;
  if m.id is null then raise exception 'Match not found'; end if;
  v_me := public.booking_my_team(m);
  if v_me is null or v_me is distinct from m.booker_team_id then
    raise exception 'Only the captain booking the court can confirm it';
  end if;
  if m.status <> 'confirmed' then raise exception 'This match is no longer active'; end if;
  if m.court_booking_status = 'booked' then return; end if;
  if m.venue_change_open then raise exception 'A court change is still open'; end if;
  if now() >= m.booking_deadline_at then raise exception 'The booking deadline has passed'; end if;

  update public.matches set court_booking_status = 'booked', booked_at = now() where id = p_match_id;
  select name into v_name from public.teams where id = v_me;
  v_other := case when v_me = m.home_team_id then m.away_team_id else m.home_team_id end;
  insert into public.match_events (match_id, team_id, type, payload)
  values (p_match_id, v_me, 'booked', jsonb_build_object('venue', m.venue_text));
  perform public.booking_notify(v_other, 'booking_booked', 'Court booked',
    coalesce(v_name, 'The other team') || ' booked ' || coalesce(m.venue_text, 'the court') ||
      ' for ' || public.booking_local_time(m.scheduled_at) || '.', p_match_id);
end $$;

-- Cancel a match because of the booking flow. Keeps the row (status
-- 'cancelled') so both teams still see what happened.
create or replace function public.booking_cancel(m public.matches, p_reason text, p_penalize boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_title text; v_body text;
begin
  update public.matches
     set status = 'cancelled', cancel_reason = p_reason,
         court_booking_status = case when p_reason = 'court_not_booked' then 'cancelled_unbooked'
                                     else court_booking_status end,
         venue_change_open = false
   where id = m.id and status = 'confirmed';
  if not found then return; end if;

  update public.venue_suggestions set status = 'superseded', responded_at = now()
   where match_id = m.id and status = 'pending';

  if p_penalize and m.booker_team_id is not null then
    update public.teams
       set reliability_score = greatest(0, reliability_score - 10),
           unbooked_cancels = unbooked_cancels + 1
     where id = m.booker_team_id;
  end if;

  insert into public.match_events (match_id, team_id, type, payload)
  values (m.id, m.booker_team_id, 'auto_cancelled', jsonb_build_object('reason', p_reason));

  v_title := 'Match cancelled';
  v_body := case p_reason
    when 'court_not_booked' then 'Match cancelled: the court wasn''t confirmed as booked.'
    when 'venue_declined_3' then 'Match cancelled: no court was agreed after 3 declined suggestions.'
    else 'Match cancelled: the court change wasn''t answered in time.' end;
  perform public.booking_notify(m.home_team_id, 'booking_cancelled', v_title, v_body, m.id);
  perform public.booking_notify(m.away_team_id, 'booking_cancelled', v_title, v_body, m.id);
end $$;

-- "Court full": suggest another court.
create or replace function public.suggest_venue(
  p_match_id uuid, p_venue_text text, p_place_id text,
  p_lat double precision, p_lng double precision, p_source text
) returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare m public.matches; v_me uuid; v_text text; v_id uuid; v_name text; v_other uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select * into m from public.matches where id = p_match_id for update;
  if m.id is null then raise exception 'Match not found'; end if;
  v_me := public.booking_my_team(m);
  if v_me is null then raise exception 'Only a captain of this match can suggest a court'; end if;
  if m.status <> 'confirmed' then raise exception 'This match is no longer active'; end if;
  if now() >= m.scheduled_at - interval '20 minutes' then
    raise exception 'too_late: courts can''t be changed in the last 20 minutes';
  end if;
  if m.venue_change_open or exists (select 1 from public.venue_suggestions
      where match_id = p_match_id and status = 'pending') then
    raise exception 'A court suggestion is already open';
  end if;
  if (select count(*) from public.venue_suggestions
       where match_id = p_match_id and suggested_by_team_id = v_me) >= 3 then
    raise exception 'limit: you can suggest up to 3 courts per match';
  end if;

  v_text := public.venue_validate(p_venue_text);
  if v_text is null then raise exception 'bad_venue:length'; end if;
  perform public.venue_location_check(p_place_id, p_lat, p_lng, p_source);

  insert into public.venue_suggestions (match_id, suggested_by_team_id, venue_text,
      venue_place_id, venue_lat, venue_lng, venue_source)
  values (p_match_id, v_me, v_text, p_place_id, p_lat, p_lng, p_source)
  returning id into v_id;
  update public.matches set venue_change_open = true where id = p_match_id;

  select name into v_name from public.teams where id = v_me;
  v_other := case when v_me = m.home_team_id then m.away_team_id else m.home_team_id end;
  insert into public.match_events (match_id, team_id, type, payload)
  values (p_match_id, v_me, 'venue_suggested', jsonb_build_object('venue', v_text, 'team', v_name));
  perform public.booking_notify(v_other, 'venue_suggested', 'New court suggested',
    coalesce(v_name, 'The other team') || ' suggests ' || v_text || '. Accept or decline.', p_match_id);
  return v_id;
end $$;

-- Accept or decline a suggestion (the other captain).
create or replace function public.respond_venue(p_suggestion_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare s public.venue_suggestions; m public.matches; v_me uuid; v_name text; v_declined int; v_mid uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select match_id into v_mid from public.venue_suggestions where id = p_suggestion_id;
  if v_mid is null then raise exception 'Suggestion not found'; end if;
  select * into m from public.matches where id = v_mid for update;
  select * into s from public.venue_suggestions where id = p_suggestion_id for update;
  if s.status <> 'pending' then raise exception 'This suggestion was already answered'; end if;
  v_me := public.booking_my_team(m);
  if v_me is null or v_me = s.suggested_by_team_id then
    raise exception 'Only the other captain can answer this suggestion';
  end if;
  if m.status <> 'confirmed' then raise exception 'This match is no longer active'; end if;
  select name into v_name from public.teams where id = v_me;

  if p_accept then
    if now() >= m.scheduled_at - interval '15 minutes' then
      raise exception 'too_late: courts can''t be changed this close to kick-off';
    end if;
    update public.venue_suggestions set status = 'accepted', responded_at = now() where id = s.id;
    perform set_config('footrank.venue_change_ok', 'on', true);
    update public.matches
       set venue_text = s.venue_text, venue_place_id = s.venue_place_id,
           venue_lat = s.venue_lat, venue_lng = s.venue_lng, venue_source = s.venue_source,
           booker_team_id = s.suggested_by_team_id,
           court_booking_status = 'not_booked', booked_at = null,
           booking_deadline_at = public.booking_deadline_for(m.scheduled_at, now()),
           reminder_1h_sent = now() >= m.scheduled_at - interval '60 minutes',
           venue_change_open = false
     where id = m.id;
    perform set_config('footrank.venue_change_ok', 'off', true);
    insert into public.match_events (match_id, team_id, type, payload)
    values (m.id, v_me, 'venue_accepted', jsonb_build_object('venue', s.venue_text));
    perform public.booking_notify(s.suggested_by_team_id, 'venue_accepted', 'Court change accepted',
      'You book ' || s.venue_text || ' now. Tap "I booked it" by ' ||
        public.booking_local_time(public.booking_deadline_for(m.scheduled_at, now())) ||
        ', or the match cancels.', m.id);
  else
    update public.venue_suggestions set status = 'declined', responded_at = now() where id = s.id;
    update public.matches set venue_change_open = false where id = m.id;
    insert into public.match_events (match_id, team_id, type, payload)
    values (m.id, v_me, 'venue_declined', jsonb_build_object('venue', s.venue_text));

    select count(*) into v_declined from public.venue_suggestions
     where match_id = m.id and status = 'declined';
    if v_declined >= 3 then
      select * into m from public.matches where id = m.id;
      perform public.booking_cancel(m, 'venue_declined_3', false);
    else
      perform public.booking_notify(s.suggested_by_team_id, 'venue_declined', 'Court change declined',
        coalesce(v_name, 'The other team') || ' declined ' || s.venue_text ||
          '. You can suggest another court.', m.id);
    end if;
  end if;
end $$;

-- Decline and suggest another court in one step.
create or replace function public.counter_venue(
  p_suggestion_id uuid, p_venue_text text, p_place_id text,
  p_lat double precision, p_lng double precision, p_source text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_match uuid;
begin
  select match_id into v_match from public.venue_suggestions where id = p_suggestion_id;
  perform public.respond_venue(p_suggestion_id, false);
  if (select status from public.matches where id = v_match) <> 'confirmed' then
    return null; -- that was the 3rd decline, the match is cancelled
  end if;
  return public.suggest_venue(v_match, p_venue_text, p_place_id, p_lat, p_lng, p_source);
end $$;

-- ---------------------------------------------------------------------------
-- 7. Watchdog: 1-hour reminder and auto-cancel (every minute)
-- ---------------------------------------------------------------------------
create or replace function public.booking_watchdog()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare r public.matches; n integer := 0; v_left int;
begin
  -- Reminders
  for r in
    update public.matches set reminder_1h_sent = true
     where status = 'confirmed' and court_booking_status = 'not_booked'
       and not reminder_1h_sent and not venue_change_open
       and now() >= scheduled_at - interval '60 minutes'
       and now() < booking_deadline_at
    returning *
  loop
    v_left := greatest(1, ceil(extract(epoch from (r.booking_deadline_at - now())) / 60)::int);
    perform public.booking_notify(r.booker_team_id, 'booking_reminder', 'Still not booked',
      v_left || ' minutes left to book ' || coalesce(r.venue_text, 'the court') ||
        ' or the match is cancelled.', r.id);
    insert into public.match_events (match_id, team_id, type) values (r.id, r.booker_team_id, 'reminder_sent');
  end loop;

  -- Not booked at the deadline (no court change open): cancel and penalize.
  for r in
    select * from public.matches
     where status = 'confirmed' and court_booking_status = 'not_booked'
       and not venue_change_open and now() >= booking_deadline_at
     for update skip locked
  loop
    perform public.booking_cancel(r, 'court_not_booked', true);
    n := n + 1;
  end loop;

  -- A court change still unanswered 15 minutes before kick-off: cancel, no penalty.
  for r in
    select * from public.matches
     where status = 'confirmed' and venue_change_open
       and now() >= scheduled_at - interval '15 minutes'
     for update skip locked
  loop
    perform public.booking_cancel(r, 'venue_unresolved', false);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------------
-- 8. Grants
-- ---------------------------------------------------------------------------
revoke all on function public.claim_booking(uuid) from public, anon;
revoke all on function public.confirm_booked(uuid) from public, anon;
revoke all on function public.suggest_venue(uuid, text, text, double precision, double precision, text) from public, anon;
revoke all on function public.respond_venue(uuid, boolean) from public, anon;
revoke all on function public.counter_venue(uuid, text, text, double precision, double precision, text) from public, anon;
grant execute on function public.claim_booking(uuid) to authenticated;
grant execute on function public.confirm_booked(uuid) to authenticated;
grant execute on function public.suggest_venue(uuid, text, text, double precision, double precision, text) to authenticated;
grant execute on function public.respond_venue(uuid, boolean) to authenticated;
grant execute on function public.counter_venue(uuid, text, text, double precision, double precision, text) to authenticated;

revoke all on function public.booking_watchdog() from public, anon, authenticated;
revoke all on function public.booking_cancel(public.matches, text, boolean) from public, anon, authenticated;
revoke all on function public.booking_notify(uuid, text, text, text, uuid) from public, anon, authenticated;
revoke all on function public.booking_my_team(public.matches) from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'booking-watchdog';
    perform cron.schedule('booking-watchdog', '* * * * *', 'select public.booking_watchdog()');
  end if;
end $$;
