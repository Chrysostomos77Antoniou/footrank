-- Map location for venues.
--
-- Captains now pick the venue on a map (Google Places search, or a pin dropped
-- by hand). The typed venue name stays exactly as before; this adds WHERE it
-- is, so the other captain gets a map preview and one-tap directions.
--
--   * venue_place_id : Google place id (kept: Google allows storing place ids)
--   * venue_lat/lng  : coordinates for the map preview. Google only allows its
--                      coordinates to be kept for a limited time, so Google
--                      sourced coordinates are cleared after 29 days (the place
--                      id keeps directions working). Hand-dropped pins
--                      ('manual') are the captain's own data and are kept.
--   * venue_source   : 'google' | 'manual'
--
-- Old app versions keep working: they send no location and the columns stay
-- null. Nothing existing is rewritten.

-- ---------------------------------------------------------------------------
-- 1. Columns
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['match_requests', 'match_request_proposals', 'matches'] loop
    execute format('alter table public.%I
      add column if not exists venue_place_id    text,
      add column if not exists venue_lat         double precision,
      add column if not exists venue_lng         double precision,
      add column if not exists venue_source      text,
      add column if not exists venue_location_at timestamptz', t);
    execute format('alter table public.%I drop constraint if exists %I', t, t || '_venue_location_check');
    execute format('alter table public.%I add constraint %I check (
        (venue_lat is null or venue_lat between -90 and 90)
        and (venue_lng is null or venue_lng between -180 and 180)
        and ((venue_lat is null) = (venue_lng is null))
        and (venue_place_id is null or (char_length(venue_place_id) <= 300 and venue_place_id ~ ''^[A-Za-z0-9_-]+$''))
        and (venue_source is null or venue_source in (''google'', ''manual''))
      )', t, t || '_venue_location_check');
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Stamp when a location was written (drives the 29-day clean-up)
-- ---------------------------------------------------------------------------
create or replace function public.trg_venue_location_stamp()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if (new.venue_lat is not null or new.venue_place_id is not null)
       and new.venue_location_at is null then
      new.venue_location_at := now();
    end if;
  elsif (new.venue_lat is distinct from old.venue_lat
         or new.venue_lng is distinct from old.venue_lng
         or new.venue_place_id is distinct from old.venue_place_id)
        and new.venue_location_at is not distinct from old.venue_location_at then
    new.venue_location_at :=
      case when new.venue_lat is null and new.venue_place_id is null
           then null else now() end;
  end if;
  return new;
end $$;

-- A venue name that changes without a new location must not keep the old pin.
create or replace function public.trg_venue_clear_stale_location()
returns trigger
language plpgsql
as $$
begin
  if new.venue_text is distinct from old.venue_text
     and new.venue_place_id is not distinct from old.venue_place_id
     and new.venue_lat      is not distinct from old.venue_lat
     and new.venue_lng      is not distinct from old.venue_lng then
    new.venue_place_id    := null;
    new.venue_lat         := null;
    new.venue_lng         := null;
    new.venue_source      := null;
    new.venue_location_at := null;
  end if;
  return new;
end $$;

-- A confirmed match takes its location from where its venue name came from:
-- the accepted proposal when the venue was the proposer's suggestion, otherwise
-- the request. (The accept functions already copy venue_text; this keeps them
-- untouched.)
create or replace function public.trg_match_copy_venue_location()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.match_request_proposals;
  r public.match_requests;
begin
  if new.venue_place_id is not null or new.venue_lat is not null
     or new.request_id is null or new.venue_text is null then
    return new;
  end if;

  select * into p from public.match_request_proposals
   where request_id = new.request_id
     and venue_text is not distinct from new.venue_text
     and (venue_place_id is not null or venue_lat is not null)
   order by created_at desc
   limit 1;
  if p.id is not null then
    new.venue_place_id := p.venue_place_id;
    new.venue_lat := p.venue_lat;
    new.venue_lng := p.venue_lng;
    new.venue_source := p.venue_source;
    new.venue_location_at := p.venue_location_at;
    return new;
  end if;

  select * into r from public.match_requests
   where id = new.request_id
     and venue_text is not distinct from new.venue_text
     and (venue_place_id is not null or venue_lat is not null);
  if r.id is not null then
    new.venue_place_id := r.venue_place_id;
    new.venue_lat := r.venue_lat;
    new.venue_lng := r.venue_lng;
    new.venue_source := r.venue_source;
    new.venue_location_at := r.venue_location_at;
  end if;
  return new;
end $$;

drop trigger if exists trg_venue_stamp_requests on public.match_requests;
create trigger trg_venue_stamp_requests before insert or update on public.match_requests
  for each row execute function public.trg_venue_location_stamp();
drop trigger if exists trg_venue_stamp_proposals on public.match_request_proposals;
create trigger trg_venue_stamp_proposals before insert or update on public.match_request_proposals
  for each row execute function public.trg_venue_location_stamp();
drop trigger if exists trg_venue_stamp_matches on public.matches;
create trigger trg_venue_stamp_matches before insert or update on public.matches
  for each row execute function public.trg_venue_location_stamp();

drop trigger if exists trg_venue_clear_stale_requests on public.match_requests;
create trigger trg_venue_clear_stale_requests before update of venue_text on public.match_requests
  for each row execute function public.trg_venue_clear_stale_location();
drop trigger if exists trg_venue_clear_stale_matches on public.matches;
create trigger trg_venue_clear_stale_matches before update of venue_text on public.matches
  for each row execute function public.trg_venue_clear_stale_location();

drop trigger if exists trg_match_copy_venue_location on public.matches;
create trigger trg_match_copy_venue_location before insert on public.matches
  for each row execute function public.trg_match_copy_venue_location();

-- ---------------------------------------------------------------------------
-- 3. Location checks shared by the two setters
-- ---------------------------------------------------------------------------
create or replace function public.venue_location_check(
  p_place_id text, p_lat double precision, p_lng double precision, p_source text
) returns void
language plpgsql
immutable
as $$
begin
  if p_source is null or p_source not in ('google', 'manual') then
    raise exception 'bad_venue:location';
  end if;
  if (p_lat is null) <> (p_lng is null) then raise exception 'bad_venue:location'; end if;
  if p_lat is null and p_place_id is null then raise exception 'bad_venue:location'; end if;
  if p_lat is not null and (p_lat not between -90 and 90 or p_lng not between -180 and 180) then
    raise exception 'bad_venue:location';
  end if;
  if p_place_id is not null
     and (char_length(p_place_id) > 300 or p_place_id !~ '^[A-Za-z0-9_-]+$') then
    raise exception 'bad_venue:location';
  end if;
  if p_source = 'manual' and p_place_id is not null then raise exception 'bad_venue:location'; end if;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Setters (called by the app right after the venue name is saved)
-- ---------------------------------------------------------------------------
-- The captain who opened the request (home side) sets where a match is played;
-- same rule as update_match_venue.
create or replace function public.set_match_venue_location(
  p_match_id uuid, p_place_id text, p_lat double precision, p_lng double precision, p_source text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare m public.matches;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  perform public.venue_location_check(p_place_id, p_lat, p_lng, p_source);

  select * into m from public.matches where id = p_match_id for update;
  if m.id is null then raise exception 'Match not found'; end if;
  if not exists (select 1 from public.teams t
                  where t.id = m.home_team_id and t.captain_id = auth.uid()) then
    raise exception 'Only the captain who opened the request can change the venue';
  end if;
  if m.status not in ('pending', 'confirmed') then
    raise exception 'This match can no longer be changed';
  end if;
  if m.scheduled_at < now() then raise exception 'The match has already started'; end if;

  update public.matches
     set venue_place_id = p_place_id, venue_lat = p_lat, venue_lng = p_lng,
         venue_source = p_source, venue_location_at = now()
   where id = p_match_id;
  if m.request_id is not null then
    update public.match_requests
       set venue_place_id = p_place_id, venue_lat = p_lat, venue_lng = p_lng,
           venue_source = p_source, venue_location_at = now()
     where id = m.request_id;
  end if;
end $$;

-- The member who sent a still-pending proposal that names a venue.
create or replace function public.set_proposal_venue_location(
  p_proposal_id uuid, p_place_id text, p_lat double precision, p_lng double precision, p_source text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare pr public.match_request_proposals;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  perform public.venue_location_check(p_place_id, p_lat, p_lng, p_source);

  select * into pr from public.match_request_proposals where id = p_proposal_id for update;
  if pr.id is null then raise exception 'Proposal not found'; end if;
  if pr.proposing_user_id <> auth.uid() then
    raise exception 'Only the member who sent the proposal can change it';
  end if;
  if pr.status <> 'pending' or pr.venue_text is null then
    raise exception 'This proposal can no longer be changed';
  end if;

  update public.match_request_proposals
     set venue_place_id = p_place_id, venue_lat = p_lat, venue_lng = p_lng,
         venue_source = p_source, venue_location_at = now()
   where id = p_proposal_id;
end $$;

revoke all on function public.set_match_venue_location(uuid, text, double precision, double precision, text) from public, anon;
revoke all on function public.set_proposal_venue_location(uuid, text, double precision, double precision, text) from public, anon;
grant execute on function public.set_match_venue_location(uuid, text, double precision, double precision, text) to authenticated;
grant execute on function public.set_proposal_venue_location(uuid, text, double precision, double precision, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Google coordinates are kept for 29 days only
-- ---------------------------------------------------------------------------
create or replace function public.purge_expired_venue_coords()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer := 0; c integer;
begin
  update public.match_requests
     set venue_lat = null, venue_lng = null
   where venue_source = 'google' and venue_lat is not null
     and venue_location_at < now() - interval '29 days';
  get diagnostics c = row_count; n := n + c;
  update public.match_request_proposals
     set venue_lat = null, venue_lng = null
   where venue_source = 'google' and venue_lat is not null
     and venue_location_at < now() - interval '29 days';
  get diagnostics c = row_count; n := n + c;
  update public.matches
     set venue_lat = null, venue_lng = null
   where venue_source = 'google' and venue_lat is not null
     and venue_location_at < now() - interval '29 days';
  get diagnostics c = row_count; n := n + c;
  return n;
end $$;

revoke all on function public.purge_expired_venue_coords() from public, anon, authenticated;

-- Nightly at 03:10 UTC when pg_cron is available.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'purge_expired_venue_coords';
    perform cron.schedule('purge_expired_venue_coords', '10 3 * * *',
                          'select public.purge_expired_venue_coords()');
  end if;
exception when others then
  raise notice 'could not schedule venue coordinate purge: %', sqlerrm;
end $$;
