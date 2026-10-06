-- Join a team instantly with its invite code.
--
-- Until now entering a team's invite code only created a *pending*
-- team_join_requests row that the captain had to approve, so the player never
-- appeared in the team and the UI did not change. Possessing the invite code
-- (which only the captain shares) is now enough to join immediately.
--
-- Every other join path (captain approvals of ordinary join requests,
-- invitations) is unchanged.
--
-- team_members has no client INSERT policy, so the insert has to happen in a
-- SECURITY DEFINER function. The existing triggers on team_members still apply
-- (max 3 teams per player, no joining a disbanded team) and the Pitch Power
-- quiz requirement matches approve_join_request_atomic / the join-request
-- trigger. Attempts (including wrong codes) are rate limited per user so the
-- code space cannot be brute-forced.

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

  select id, name into v_team_id, v_team_name
  from public.teams
  where invite_code = upper(btrim(p_invite_code))
    and disbanded_at is null;

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

  -- Close out any request this player had already sent to the same team.
  update public.team_join_requests
  set status = 'approved'
  where team_id = v_team_id and user_id = v_uid and status = 'pending';

  return v_team_name;
end;
$$;

revoke execute on function public.join_team_by_code(text) from public;
revoke execute on function public.join_team_by_code(text) from anon;
grant execute on function public.join_team_by_code(text) to authenticated;
