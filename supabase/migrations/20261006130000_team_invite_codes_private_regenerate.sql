-- Private, regenerable team invite codes.
--
-- Joining with an invite code is instant (see join_team_by_code), so the code
-- is effectively a key to the team. It used to live in teams.invite_code, which
-- every signed-in user can SELECT (teams are public for rankings) -- anyone
-- could read any team's code and join. Codes move to team_invite_codes,
-- readable only by members of that team, and captains can regenerate them.

create table if not exists public.team_invite_codes (
  team_id uuid primary key references public.teams(id) on delete cascade,
  code text not null unique,
  updated_at timestamptz not null default now()
);

alter table public.team_invite_codes enable row level security;

drop policy if exists "Members can view their team invite code" on public.team_invite_codes;
create policy "Members can view their team invite code"
  on public.team_invite_codes for select
  to authenticated
  using (exists (
    select 1 from public.team_members m
    where m.team_id = team_invite_codes.team_id
      and m.user_id = (select auth.uid())
  ));

revoke all on public.team_invite_codes from anon, authenticated;
grant select on public.team_invite_codes to authenticated;

-- Move the existing codes over...
insert into public.team_invite_codes (team_id, code)
select id, invite_code from public.teams where invite_code is not null
on conflict (team_id) do nothing;

-- Server-side generator: 6 chars from an unambiguous alphabet, drawn from a
-- cryptographically secure source, retried until no team holds that code.
create or replace function public.generate_team_invite_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  chars constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
  v_code text;
  i int;
  tries int := 0;
begin
  loop
    v_bytes := uuid_send(gen_random_uuid());
    v_code := '';
    for i in 0..5 loop
      v_code := v_code || substr(chars, (get_byte(v_bytes, i) % 32) + 1, 1);
    end loop;

    if not exists (select 1 from public.team_invite_codes where code = v_code) then
      return v_code;
    end if;

    tries := tries + 1;
    if tries > 50 then
      raise exception 'Could not generate a unique invite code';
    end if;
  end loop;
end;
$$;

revoke execute on function public.generate_team_invite_code() from public, anon, authenticated;

-- Captain regenerates the code whenever they want; the old one stops working.
create or replace function public.regenerate_team_invite_code(p_team_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_captain uuid;
  v_disbanded timestamptz;
  v_code text;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select captain_id, disbanded_at into v_captain, v_disbanded
  from public.teams where id = p_team_id;

  if v_captain is distinct from v_uid then
    raise exception 'Only the team captain can change the invite code';
  end if;
  if v_disbanded is not null then
    raise exception 'This team has been disbanded';
  end if;

  if not public.check_rate_limit('regen_invite:' || v_uid::text, 30, 3600) then
    raise exception 'Too many attempts, please try again later';
  end if;

  v_code := public.generate_team_invite_code();

  insert into public.team_invite_codes (team_id, code, updated_at)
  values (p_team_id, v_code, now())
  on conflict (team_id) do update set code = excluded.code, updated_at = now();

  return v_code;
end;
$$;

revoke execute on function public.regenerate_team_invite_code(uuid) from public, anon;
grant execute on function public.regenerate_team_invite_code(uuid) to authenticated;

-- join_team_by_code looks the code up in the private table.
create or replace function public.join_team_by_code(p_invite_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_team_id uuid;
  v_team_name text;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  if not public.check_rate_limit('join_by_code:' || v_uid::text, 20, 3600) then
    raise exception 'Too many attempts, please try again later';
  end if;

  if (select pwr_assessment_completed_at from public.users where id = v_uid) is null then
    raise exception 'pwr_assessment_required: %', v_uid;
  end if;

  select t.id, t.name into v_team_id, v_team_name
  from public.team_invite_codes c
  join public.teams t on t.id = c.team_id
  where c.code = upper(btrim(p_invite_code))
    and t.disbanded_at is null;

  if v_team_id is null then
    raise exception 'No team found with that invite code';
  end if;

  if exists (
    select 1 from public.team_members
    where team_id = v_team_id and user_id = v_uid
  ) then
    raise exception 'You are already in this team';
  end if;

  insert into public.team_members (team_id, user_id, role)
  values (v_team_id, v_uid, 'player');

  update public.team_join_requests
  set status = 'approved'
  where team_id = v_team_id and user_id = v_uid and status = 'pending';

  return v_team_name;
end;
$$;

-- create_team_atomic: the client no longer chooses the code (it could collide
-- or be guessable). Same arguments (p_invite_code is now ignored) so older
-- builds keep working; the code is created server-side in team_invite_codes.
create or replace function public.create_team_atomic(
  p_name text, p_city text, p_logo_url text, p_invite_code text default null
)
returns teams
language plpgsql
security definer
set search_path = public
as $$
declare
  v_team public.teams;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if (select pwr_assessment_completed_at from public.users where id = auth.uid()) is null then
    raise exception 'pwr_assessment_required';
  end if;

  insert into public.teams (name, city, logo_url, captain_id)
  values (p_name, p_city, p_logo_url, auth.uid())
  returning * into v_team;

  insert into public.team_members (team_id, user_id, role)
  values (v_team.id, auth.uid(), 'captain');

  insert into public.team_invite_codes (team_id, code)
  values (v_team.id, public.generate_team_invite_code());

  return v_team;
end;
$$;

-- ...and finally blank the publicly readable column (kept, nullable, so older
-- app builds that SELECT teams.* keep working).
update public.teams set invite_code = null where invite_code is not null;
