-- Booking name: the name the captain books the court under, so the other team
-- can quote it at the court.
--
-- match_requests is readable by every captain browsing the city, so the name
-- cannot be a column there. It lives in its own table: the request's team
-- always sees it; the opposing team only once a (non-cancelled) match exists
-- for that request, i.e. after the proposal was accepted.

create table if not exists public.match_booking_names (
  request_id uuid primary key references public.match_requests(id) on delete cascade,
  team_id    uuid not null references public.teams(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 60)
);

alter table public.match_booking_names enable row level security;

drop policy if exists "match_booking_names_select" on public.match_booking_names;
create policy "match_booking_names_select"
  on public.match_booking_names for select
  to authenticated
  using (
    exists (
      select 1 from public.team_members tm
       where tm.team_id = match_booking_names.team_id
         and tm.user_id = (select auth.uid()))
    or exists (
      select 1 from public.matches m
       where m.request_id = match_booking_names.request_id
         and m.status <> 'cancelled'
         and public.is_match_member(m.id))
  );

-- Writes only through set_request_booking_name.
revoke all on public.match_booking_names from anon, authenticated;
grant select on public.match_booking_names to authenticated;

-- The request's own captain sets (or clears, with an empty name) the name.
create or replace function public.set_request_booking_name(p_request_id uuid, p_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare r public.match_requests; v_name text := nullif(btrim(p_name), '');
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select * into r from public.match_requests where id = p_request_id;
  if r.id is null or r.captain_id is distinct from auth.uid() then
    raise exception 'Only the captain who opened this request can do this';
  end if;
  if v_name is null then
    delete from public.match_booking_names where request_id = p_request_id;
    return;
  end if;
  if char_length(v_name) > 60 then raise exception 'booking_name_invalid'; end if;
  insert into public.match_booking_names (request_id, team_id, name)
  values (p_request_id, r.team_id, v_name)
  on conflict (request_id) do update set name = excluded.name;
end $$;

revoke all on function public.set_request_booking_name(uuid, text) from public, anon;
grant execute on function public.set_request_booking_name(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- One change after the match is confirmed
-- ---------------------------------------------------------------------------
-- The captain of the team booking the court may add or change the name once
-- while the match is confirmed. `edited` records that the one change is used
-- (a new Booker after a takeover gets their own one change).
alter table public.match_booking_names
  add column if not exists edited boolean not null default false;

create or replace function public.change_match_booking_name(p_match_id uuid, p_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  m public.matches; b public.match_booking_names;
  v_me uuid; v_other uuid; v_who text;
  v_name text := nullif(btrim(p_name), '');
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select * into m from public.matches where id = p_match_id for update;
  if m.id is null then raise exception 'Match not found'; end if;
  v_me := public.booking_my_team(m);
  if v_me is null or v_me is distinct from m.booker_team_id then
    raise exception 'Only the captain booking the court can change the booking name';
  end if;
  if m.status <> 'confirmed' then raise exception 'This match is no longer active'; end if;
  if m.request_id is null then raise exception 'This match has no booking name'; end if;
  if v_name is null or char_length(v_name) > 60 then raise exception 'booking_name_invalid'; end if;

  select * into b from public.match_booking_names where request_id = m.request_id for update;
  if found and b.team_id = v_me then
    if b.edited then raise exception 'booking_name_already_changed'; end if;
    if b.name = v_name then return; end if; -- nothing changed, keep the one change
  end if;

  insert into public.match_booking_names (request_id, team_id, name, edited)
  values (m.request_id, v_me, v_name, true)
  on conflict (request_id) do update
    set team_id = excluded.team_id, name = excluded.name, edited = true;

  v_other := case when v_me = m.home_team_id then m.away_team_id else m.home_team_id end;
  select name into v_who from public.teams where id = v_me;
  perform public.booking_notify(v_other, 'booking_info', 'Booking name changed',
    coalesce(v_who, 'The other team') || ' booked under a new name: ' || v_name, m.id);
end $$;

revoke all on function public.change_match_booking_name(uuid, text) from public, anon;
grant execute on function public.change_match_booking_name(uuid, text) to authenticated;
