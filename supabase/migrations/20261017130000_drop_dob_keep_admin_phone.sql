-- Date of birth was dropped from scope before it shipped: remove the column
-- and RPC added in 20261017120000, and make the admin read return phone only.

drop function if exists public.update_my_date_of_birth(date);

alter table public.user_contacts
  drop constraint if exists user_contacts_date_of_birth_range;
alter table public.user_contacts
  drop column if exists date_of_birth;

drop function if exists public.admin_get_user_contact(uuid);

create or replace function public.admin_get_user_contact(p_user_id uuid)
returns table (phone text)
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not exists (select 1 from public.users where id = auth.uid() and is_admin = true) then
    raise exception 'Admin only';
  end if;
  return query
    select c.phone from public.user_contacts c where c.user_id = p_user_id;
end;
$$;

revoke all on function public.admin_get_user_contact(uuid) from public, anon;
grant execute on function public.admin_get_user_contact(uuid) to authenticated;
