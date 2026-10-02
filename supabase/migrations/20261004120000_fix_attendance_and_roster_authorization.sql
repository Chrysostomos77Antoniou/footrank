-- Security audit fixes FR-01 and FR-02.
--
-- FR-01: a captain could insert/update match_players rows for ANY user_id, so
-- a completed match could change the rating / reliability / matches_played of
-- people who were never on the team, and the "5 attended players" gate could
-- be satisfied with made-up rows. Attendance rows must now belong to a real
-- member of the captain's own team, and only while the match is confirmed
-- (not once it is completed).
--
-- FR-02: a captain could re-point a team_members row at any user_id (forced
-- roster membership), bypassing the join-request / invitation consent, the
-- Pwr assessment gate, the 3-team limit and the disbanded-team check. Clients
-- may now only change a member's role between 'player' and 'vice_captain'.
-- Rows are created only by the SECURITY DEFINER RPCs (create_team_atomic,
-- approve_join_request_atomic, accept_invitation_atomic), which bypass RLS.

-- ---------------------------------------------------------------- FR-01 --
drop policy if exists "Captain can insert own team attendance" on public.match_players;
drop policy if exists "Captain can update own team attendance" on public.match_players;

create policy "Captain can insert own team attendance"
  on public.match_players for insert to authenticated
  with check (
    exists (
      select 1
        from public.matches m
        join public.teams t on t.id in (m.home_team_id, m.away_team_id)
       where m.id = match_players.match_id
         and m.status = 'confirmed'
         and t.id = match_players.team_id
         and t.captain_id = (select auth.uid())
    )
    and exists (
      select 1 from public.team_members tm
       where tm.team_id = match_players.team_id
         and tm.user_id = match_players.user_id
    )
  );

create policy "Captain can update own team attendance"
  on public.match_players for update to authenticated
  using (
    exists (
      select 1
        from public.matches m
        join public.teams t on t.id in (m.home_team_id, m.away_team_id)
       where m.id = match_players.match_id
         and m.status = 'confirmed'
         and t.id = match_players.team_id
         and t.captain_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1
        from public.matches m
        join public.teams t on t.id in (m.home_team_id, m.away_team_id)
       where m.id = match_players.match_id
         and m.status = 'confirmed'
         and t.id = match_players.team_id
         and t.captain_id = (select auth.uid())
    )
    and exists (
      select 1 from public.team_members tm
       where tm.team_id = match_players.team_id
         and tm.user_id = match_players.user_id
    )
  );

-- An attendance row's identity can never change; only attended/marked_by can.
create or replace function public.lock_match_player_identity()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.match_id is distinct from old.match_id
     or new.user_id  is distinct from old.user_id
     or new.team_id  is distinct from old.team_id then
    raise exception 'Cannot change the match, player or team of an attendance row';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_lock_match_player_identity on public.match_players;
create trigger trg_lock_match_player_identity
  before update on public.match_players
  for each row execute function public.lock_match_player_identity();

revoke insert, update, delete on public.match_players from anon;

-- ---------------------------------------------------------------- FR-02 --
drop policy if exists "Captain can add members" on public.team_members;
drop policy if exists "User joins via invitation" on public.team_members;
drop policy if exists "Captain can update members" on public.team_members;

revoke insert, update on public.team_members from anon, authenticated;
grant update (role) on public.team_members to authenticated;

create policy "Captain can update member roles"
  on public.team_members for update to authenticated
  using (
    team_members.role <> 'captain'
    and exists (
      select 1 from public.teams t
       where t.id = team_members.team_id
         and t.captain_id = (select auth.uid())
    )
  )
  with check (
    team_members.role in ('vice_captain', 'player')
    and exists (
      select 1 from public.teams t
       where t.id = team_members.team_id
         and t.captain_id = (select auth.uid())
    )
  );
