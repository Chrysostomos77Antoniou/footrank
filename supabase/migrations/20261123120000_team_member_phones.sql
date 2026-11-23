-- Teammates can see each other's phone numbers.
--
-- user_contacts is owner-read-only (see 20261105163500), so members cannot
-- SELECT a teammate's phone. This security-definer RPC returns the phones of
-- one team's members, and only to a member of that same team.

create or replace function public.team_member_phones(p_team_id uuid)
returns table (user_id uuid, phone text)
language plpgsql
stable
security definer
set search_path to 'public'
as $$
begin
  if not exists (
    select 1 from public.team_members m
    where m.team_id = p_team_id and m.user_id = auth.uid()
  ) then
    raise exception 'Members only';
  end if;
  return query
    select m.user_id, c.phone
    from public.team_members m
    join public.user_contacts c on c.user_id = m.user_id
    where m.team_id = p_team_id;
end;
$$;

revoke all on function public.team_member_phones(uuid) from public, anon;
grant execute on function public.team_member_phones(uuid) to authenticated;
