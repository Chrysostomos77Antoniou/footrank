-- Approving a join request when the player already joined the team another way
-- (e.g. via invite code) used to fail with a raw duplicate-key error and leave
-- the request stuck. It now resolves the request without adding a duplicate
-- member and without using up one of a recruitment post's spots.
-- Applied live as migration `approve_join_request_already_member`.
create or replace function public.approve_join_request_atomic(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_req        team_join_requests;
  v_captain_id uuid;
  v_team_name  text;
  v_rec        team_recruitments;
  v_added      int;
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

  insert into team_members (team_id, user_id, role) values (v_req.team_id, v_req.user_id, 'player')
  on conflict do nothing;
  get diagnostics v_added = row_count;
  update team_join_requests set status = 'approved' where id = p_request_id;

  -- Already a member (joined another way meanwhile): request is resolved, no spot used.
  if v_added = 0 then return; end if;

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
end $function$;
