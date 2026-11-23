-- Recruitment posts: a captain says "we need N players"; players (free agents or
-- already on other teams) ask to join; the captain approves. When the approved
-- count reaches N the post closes itself. Also removes the 3-teams-per-player
-- limit.

-- 1) No more team limit per player.
drop trigger if exists trg_max_teams on public.team_members;
drop function if exists public.enforce_max_teams();

-- 2) Posts. Written only through the RPCs below (no write policies).
create table if not exists public.team_recruitments (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid not null references public.teams(id) on delete cascade,
  spots       int  not null check (spots between 1 and 5),
  accepted    int  not null default 0,
  position    text check (position is null or char_length(position) <= 20),
  note        text check (note is null or char_length(note) <= 200),
  status      text not null default 'open'
              check (status in ('open', 'filled', 'closed', 'expired')),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '14 days'
);

-- One open post per team.
create unique index if not exists uq_recruitment_one_open
  on public.team_recruitments (team_id) where status = 'open';

alter table public.team_recruitments enable row level security;
revoke all on public.team_recruitments from anon;

drop policy if exists "View open posts or own team's" on public.team_recruitments;
create policy "View open posts or own team's" on public.team_recruitments
  for select to authenticated
  using (
    (status = 'open' and expires_at > now())
    or exists (select 1 from public.teams t
               where t.id = team_id and t.captain_id = (select auth.uid()))
  );

-- 3) Link a join request to the post it answers.
alter table public.team_join_requests
  add column if not exists recruitment_id uuid
  references public.team_recruitments(id) on delete set null;

-- A player asks a given post once (a declined request stays declined).
create unique index if not exists uq_join_request_recruitment
  on public.team_join_requests (recruitment_id, user_id)
  where recruitment_id is not null;

-- 4) Captain opens a post.
create or replace function public.create_team_recruitment(
  p_team_id uuid, p_spots int, p_position text default null, p_note text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from teams
                 where id = p_team_id and captain_id = v_uid and disbanded_at is null) then
    raise exception 'Only the team captain can do this';
  end if;
  if p_spots is null or p_spots not between 1 and 5 then
    raise exception 'recruit_spots_invalid';
  end if;

  update team_recruitments set status = 'expired'
  where team_id = p_team_id and status = 'open' and expires_at <= now();

  if exists (select 1 from team_recruitments
             where team_id = p_team_id and status = 'open') then
    raise exception 'recruit_already_open';
  end if;

  insert into team_recruitments (team_id, spots, position, note)
  values (p_team_id, p_spots, nullif(btrim(p_position), ''), nullif(btrim(p_note), ''))
  returning id into v_id;
  return v_id;
end $$;

-- 5) Captain closes a post by hand; waiting requests are declined.
create or replace function public.close_team_recruitment(p_recruitment_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_team uuid;
begin
  select r.team_id into v_team
  from team_recruitments r join teams t on t.id = r.team_id
  where r.id = p_recruitment_id and r.status = 'open' and t.captain_id = auth.uid()
  for update of r;
  if v_team is null then raise exception 'Recruitment not found or already closed'; end if;

  update team_recruitments set status = 'closed' where id = p_recruitment_id;
  update team_join_requests set status = 'rejected'
  where recruitment_id = p_recruitment_id and status = 'pending';
end $$;

-- 6) Player asks to join. The usual join-request triggers still run on the
-- insert (Pitch Power quiz done, rate limit, team not disbanded).
create or replace function public.request_join_recruitment(p_recruitment_id uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_rec  team_recruitments;
  v_team teams;
  v_name text;
  v_id   uuid;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  select * into v_rec from team_recruitments where id = p_recruitment_id;
  if v_rec.id is null or v_rec.status <> 'open' or v_rec.expires_at <= now() then
    raise exception 'recruit_closed';
  end if;

  select * into v_team from teams where id = v_rec.team_id;
  if v_team.disbanded_at is not null then raise exception 'This team has been disbanded'; end if;
  if exists (select 1 from team_members where team_id = v_team.id and user_id = v_uid) then
    raise exception 'You are already in this team';
  end if;

  insert into team_join_requests (team_id, user_id, status, recruitment_id)
  values (v_team.id, v_uid, 'pending', v_rec.id)
  returning id into v_id;

  select name into v_name from users where id = v_uid;
  if v_team.captain_id is not null then
    insert into notifications (user_id, type, title, body, reference_id)
    values (v_team.captain_id, 'join_request', 'New join request',
            coalesce(v_name, 'A player') || ' wants to join ' || v_team.name, v_team.id);
  end if;
  return v_id;
end $$;

-- 7) Player withdraws a waiting request.
create or replace function public.cancel_join_request(p_request_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from team_join_requests
  where id = p_request_id and user_id = auth.uid() and status = 'pending';
end $$;

-- 8) Approve: add the player, tell them, count the spot, and close the post
-- (declining the rest) once every spot is taken. One transaction, so two quick
-- approvals cannot overfill it.
create or replace function public.approve_join_request_atomic(p_request_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_req        team_join_requests;
  v_captain_id uuid;
  v_team_name  text;
  v_rec        team_recruitments;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;

  select * into v_req from team_join_requests where id = p_request_id for update;
  if v_req.id is null then raise exception 'Join request not found'; end if;

  select captain_id, name into v_captain_id, v_team_name from teams where id = v_req.team_id;
  if v_captain_id is distinct from auth.uid() then
    raise exception 'Only the team captain can approve this request';
  end if;
  if v_req.status <> 'pending' then raise exception 'This request is no longer pending'; end if;
  if (select pwr_assessment_completed_at from users where id = v_req.user_id) is null then
    raise exception 'pwr_assessment_required: %', v_req.user_id;
  end if;

  insert into team_members (team_id, user_id, role) values (v_req.team_id, v_req.user_id, 'player');
  update team_join_requests set status = 'approved' where id = p_request_id;

  insert into notifications (user_id, type, title, body, reference_id)
  values (v_req.user_id, 'join_accepted', 'You''re in!',
          'Welcome to ' || coalesce(v_team_name, 'the team') || '.', v_req.team_id);

  if v_req.recruitment_id is not null then
    select * into v_rec from team_recruitments where id = v_req.recruitment_id for update;
    if v_rec.id is not null and v_rec.status = 'open' then
      update team_recruitments
      set accepted = accepted + 1,
          status = case when accepted + 1 >= spots then 'filled' else 'open' end
      where id = v_rec.id;

      if v_rec.accepted + 1 >= v_rec.spots then
        with declined as (
          update team_join_requests set status = 'rejected'
          where recruitment_id = v_rec.id and status = 'pending'
          returning user_id)
        insert into notifications (user_id, type, title, body, reference_id)
        select user_id, 'recruit_filled', 'Spots filled',
               coalesce(v_team_name, 'The team') || ' found all the players they needed.',
               v_rec.team_id
        from declined;
      end if;
    end if;
  end if;
end $$;

-- 9) Housekeeping: posts expire after 14 days, or when the team disbands.
create or replace function public.expire_team_recruitments()
returns void
language sql security definer set search_path = public as $$
  with ended as (
    update team_recruitments r
    set status = case when t.disbanded_at is not null then 'closed' else 'expired' end
    from teams t
    where t.id = r.team_id and r.status = 'open'
      and (r.expires_at <= now() or t.disbanded_at is not null)
    returning r.id)
  update team_join_requests set status = 'rejected'
  where status = 'pending' and recruitment_id in (select id from ended);
$$;

revoke all on function public.create_team_recruitment(uuid, int, text, text) from public, anon;
revoke all on function public.close_team_recruitment(uuid) from public, anon;
revoke all on function public.request_join_recruitment(uuid) from public, anon;
revoke all on function public.cancel_join_request(uuid) from public, anon;
revoke all on function public.approve_join_request_atomic(uuid) from public, anon;
revoke all on function public.expire_team_recruitments() from public, anon, authenticated;
grant execute on function public.create_team_recruitment(uuid, int, text, text) to authenticated;
grant execute on function public.close_team_recruitment(uuid) to authenticated;
grant execute on function public.request_join_recruitment(uuid) to authenticated;
grant execute on function public.cancel_join_request(uuid) to authenticated;
grant execute on function public.approve_join_request_atomic(uuid) to authenticated;

do $$
begin
  perform cron.schedule('expire-team-recruitments', '*/30 * * * *',
                        'select public.expire_team_recruitments()');
exception when others then
  raise notice 'pg_cron not available: %', sqlerrm;
end $$;
