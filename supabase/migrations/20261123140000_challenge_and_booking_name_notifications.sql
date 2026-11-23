-- Notifications:
--  1. New match request -> every captain in the same city hears which team
--     wants to play ("Go challenge them!"). The old +-50 rating filter is gone
--     (the matchmaking rating gap was removed in 20261102140914).
--  2. Proposal accepted / match confirmed -> the opponent also gets the
--     booking name, so they can say it at the court.
-- A new proposal already notifies the request's captain (propose_match).

create or replace function public.notify_match_request()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_name text;
begin
  if not config_flag('match_request_broadcast_enabled', true) then
    return new;
  end if;

  select name into v_name from public.teams where id = new.team_id;

  insert into public.notifications(user_id, type, title, body, reference_id)
  select t.captain_id, 'match_request',
         coalesce(v_name, 'A team') || ' wants to play',
         new.city || ' · ' ||
           to_char(new.scheduled_at at time zone 'Asia/Nicosia', 'DD Mon HH24:MI') ||
           ' · ' || new.match_type || '. Go challenge them!',
         new.id
    from public.teams t
   where lower(t.city) = lower(new.city)
     and t.id <> new.team_id
     and t.captain_id is not null
     and t.captain_id <> new.captain_id
     and t.disbanded_at is null;
  return new;
end;
$$;

-- Confirmation notice to the non-booking team now carries the booking name
-- (only while the name's author is the Booker).
create or replace function public.trg_match_booking_after_confirm()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_booker text; v_other uuid; v_bname text;
begin
  if new.status <> 'confirmed' or new.booker_team_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'confirmed' then return new; end if;

  select name into v_booker from public.teams where id = new.booker_team_id;
  v_other := case when new.booker_team_id = new.home_team_id then new.away_team_id else new.home_team_id end;
  select b.name into v_bname from public.match_booking_names b
   where b.request_id = new.request_id and b.team_id = new.booker_team_id;

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
    case when v_bname is not null
         then 'Booking name: "' || v_bname || '" - say it at the court. Or tap "I''ll book it" to book it yourself.'
         else 'Want to book it yourself? Tap "I''ll book it" on the match.' end,
    new.id);
  return new;
end $$;

-- "Proposal accepted!" (to the proposing team) also carries the booking name.
-- Patches the live function in place; fails loudly if its text has changed.
do $$
declare d text; n text;
begin
  select pg_get_functiondef(p.oid) into d
    from pg_proc p
   where p.proname = 'accept_match_proposal' and p.pronamespace = 'public'::regnamespace;
  n := replace(d,
    $old$' accepted your proposal. Match confirmed!' ||$old$,
    $new$' accepted your proposal. Match confirmed!' ||
    coalesce((select ' Booking name: ' || b.name || '.'
                from public.match_booking_names b
                join public.matches mm on mm.id = v_match_id
               where b.request_id = v_req.id and b.team_id = mm.booker_team_id), '') ||$new$);
  if n = d then raise exception 'accept_match_proposal: expected text not found'; end if;
  execute n;
end $$;
