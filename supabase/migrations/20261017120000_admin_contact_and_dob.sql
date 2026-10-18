-- Admin panel: show a player's phone and (new) date of birth.
--
-- Phone and date of birth are personal data, so both live in the owner-only
-- `user_contacts` table (RLS: a user can only SELECT their own row). They are
-- NOT put on `users`, whose rows are readable by every signed-in user.
--
-- * user_contacts.date_of_birth: optional, set by the player in the app.
-- * update_my_date_of_birth(date): player writes their own DOB (needs a phone
--   row first, because phone is the row's mandatory column).
-- * admin_get_user_contact(uuid): admin-only read of phone + DOB for one user.

alter table public.user_contacts
  add column if not exists date_of_birth date;

alter table public.user_contacts
  drop constraint if exists user_contacts_date_of_birth_range;
alter table public.user_contacts
  add constraint user_contacts_date_of_birth_range
  check (date_of_birth is null
         or (date_of_birth >= date '1900-01-01' and date_of_birth <= current_date));

create or replace function public.update_my_date_of_birth(p_dob date)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if p_dob is not null and (p_dob < date '1900-01-01' or p_dob > current_date) then
    raise exception 'DOB_INVALID';
  end if;
  update public.user_contacts
     set date_of_birth = p_dob, updated_at = now()
   where user_id = v_uid;
  if not found then raise exception 'PHONE_REQUIRED'; end if;
end;
$$;

revoke all on function public.update_my_date_of_birth(date) from public, anon;
grant execute on function public.update_my_date_of_birth(date) to authenticated;

create or replace function public.admin_get_user_contact(p_user_id uuid)
returns table (phone text, date_of_birth date)
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not exists (select 1 from public.users where id = auth.uid() and is_admin = true) then
    raise exception 'Admin only';
  end if;
  return query
    select c.phone, c.date_of_birth
      from public.user_contacts c
     where c.user_id = p_user_id;
end;
$$;

revoke all on function public.admin_get_user_contact(uuid) from public, anon;
grant execute on function public.admin_get_user_contact(uuid) to authenticated;
