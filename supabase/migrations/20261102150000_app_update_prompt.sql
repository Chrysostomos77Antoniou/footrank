-- "New version" window: one switch row the owner controls.
--
-- When enabled, every user on a build OLDER than latest_version sees a small
-- window, which cannot be closed, with one button that opens their own store
-- (App Store on iPhone, Google Play on Android -- chosen by the app from the
-- phone it runs on). Off by default. People already on latest_version or newer
-- never see it.
--
-- * app_update_prompt: exactly one row (id is always true). Readable by anyone,
--   including signed-out users (nothing in it is secret); nobody can write to it
--   directly.
-- * admin_set_app_update_prompt(enabled, latest_version): the only way to change
--   it from the app side (the admin panel). Checks is_admin. Enabling needs a
--   valid version such as 1.1.8, so the window can never be switched on for
--   everyone by accident.
-- The owner can also flip it with a plain UPDATE on the row.
-- Additive: installed apps ignore the table. Undo: rollback_app_update_prompt.sql.

create table if not exists public.app_update_prompt (
  id boolean primary key default true check (id),
  enabled boolean not null default false,
  latest_version text not null default '',
  ios_url text not null default 'https://apps.apple.com/cy/app/footrank-5-a-side-ranking/id6789153684',
  android_url text not null default 'https://play.google.com/store/apps/details?id=com.footballcy.footrank',
  updated_at timestamptz not null default now(),
  updated_by uuid
);

insert into public.app_update_prompt (id) values (true) on conflict (id) do nothing;

alter table public.app_update_prompt enable row level security;

drop policy if exists "anyone can read the update prompt" on public.app_update_prompt;
create policy "anyone can read the update prompt"
  on public.app_update_prompt for select
  to anon, authenticated
  using (true);

revoke all on table public.app_update_prompt from public, anon, authenticated;
grant select on table public.app_update_prompt to anon, authenticated;

create or replace function public.admin_set_app_update_prompt(
  p_enabled boolean,
  p_latest_version text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v text := btrim(coalesce(p_latest_version, ''));
begin
  if not exists (select 1 from public.users where id = auth.uid() and is_admin = true) then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if v <> '' and v !~ '^[0-9]+(\.[0-9]+){1,2}$' then
    raise exception 'The version must look like 1.1.8' using errcode = '22023';
  end if;
  if p_enabled and v = '' then
    raise exception 'Enter the newest version (for example 1.1.8) before switching the window on' using errcode = '22023';
  end if;
  update public.app_update_prompt
     set enabled = p_enabled,
         latest_version = v,
         updated_at = now(),
         updated_by = auth.uid()
   where id;
end;
$function$;

revoke all on function public.admin_set_app_update_prompt(boolean, text) from public;
revoke all on function public.admin_set_app_update_prompt(boolean, text) from anon;
grant execute on function public.admin_set_app_update_prompt(boolean, text) to authenticated, service_role;

comment on table public.app_update_prompt is
  'One row. When enabled, apps older than latest_version show a window that sends the user to their store.';
