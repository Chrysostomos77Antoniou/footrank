-- Admin-only: read a user's sign-in email (lives in auth.users).
create or replace function public.admin_get_user_email(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  if not exists (select 1 from public.users where id = auth.uid() and is_admin = true) then
    raise exception 'Admin only';
  end if;
  select au.email into v_email from auth.users au where au.id = p_user_id;
  return v_email;
end;
$$;
revoke all on function public.admin_get_user_email(uuid) from public, anon;
grant execute on function public.admin_get_user_email(uuid) to authenticated;
