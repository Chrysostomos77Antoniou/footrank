-- Date of birth, collected from every player (new sign-ups and, via a
-- mandatory prompt, existing users).
--
-- Stored in its own owner-only table: `users` rows are readable by every
-- signed-in user, and `user_contacts` can't be used because its mandatory
-- `phone` column does not exist for most existing players.
--
--  * RLS: a player can SELECT only their own row; there are no write policies.
--  * set_my_date_of_birth(date): the only way to write it. Validates the
--    range and enforces the minimum age (16) server-side.
--  * admin_get_user_private(uuid): admin-only read of phone + date of birth.
--
-- The earlier, unused user_contacts.date_of_birth column and
-- update_my_date_of_birth() from 20261017120000 are superseded by this.

create table if not exists public.user_birthdates (
  user_id       uuid primary key references public.users(id) on delete cascade,
  date_of_birth date not null
    check (date_of_birth >= date '1900-01-01' and date_of_birth <= current_date),
  updated_at    timestamptz not null default now()
);

alter table public.user_birthdates enable row level security;

drop policy if exists "Own birthdate select" on public.user_birthdates;
create policy "Own birthdate select" on public.user_birthdates
  for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.user_birthdates from anon, authenticated;
grant select on public.user_birthdates to authenticated;

create or replace function public.set_my_date_of_birth(p_dob date)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if p_dob is null or p_dob < date '1900-01-01' or p_dob > current_date then
    raise exception 'DOB_INVALID';
  end if;
  if p_dob > (current_date - interval '16 years')::date then
    raise exception 'DOB_UNDERAGE';
  end if;
  if not exists (select 1 from public.users where id = v_uid) then
    raise exception 'PROFILE_REQUIRED';
  end if;
  insert into public.user_birthdates (user_id, date_of_birth, updated_at)
  values (v_uid, p_dob, now())
  on conflict (user_id) do update
    set date_of_birth = excluded.date_of_birth, updated_at = now();
end;
$$;

revoke all on function public.set_my_date_of_birth(date) from public, anon;
grant execute on function public.set_my_date_of_birth(date) to authenticated;

create or replace function public.admin_get_user_private(p_user_id uuid)
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
    select
      (select c.phone from public.user_contacts c where c.user_id = p_user_id),
      (select b.date_of_birth from public.user_birthdates b where b.user_id = p_user_id);
end;
$$;

revoke all on function public.admin_get_user_private(uuid) from public, anon;
grant execute on function public.admin_get_user_private(uuid) to authenticated;
