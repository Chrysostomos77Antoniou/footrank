-- New match request: notify every member (captain and players) of the teams in
-- the same city, not only the captains. A player on several teams gets one
-- notification; the requesting team's own members and the requester are skipped.

create or replace function public.notify_match_request()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_name text; v_title text; v_body text;
begin
  if not config_flag('match_request_broadcast_enabled', true) then
    return new;
  end if;

  select name into v_name from public.teams where id = new.team_id;
  v_title := coalesce(v_name, 'A team') || ' wants to play';
  v_body := new.city || ' · ' ||
            to_char(new.scheduled_at at time zone 'Asia/Nicosia', 'DD Mon HH24:MI') ||
            ' · ' || new.match_type || '. Go challenge them!';

  insert into public.notifications(user_id, type, title, body, reference_id)
  select distinct u.user_id, 'match_request', v_title, v_body, new.id
    from (
      select tm.user_id
        from public.team_members tm
        join public.teams t on t.id = tm.team_id
       where lower(t.city) = lower(new.city) and t.id <> new.team_id
         and t.disbanded_at is null
      union
      select t.captain_id
        from public.teams t
       where lower(t.city) = lower(new.city) and t.id <> new.team_id
         and t.disbanded_at is null and t.captain_id is not null
    ) u
   where u.user_id <> new.captain_id
     and not exists (select 1 from public.team_members m
                      where m.team_id = new.team_id and m.user_id = u.user_id);
  return new;
end;
$$;
