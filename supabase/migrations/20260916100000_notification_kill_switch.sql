-- Runtime toggles for behaviour we need to mute without a deploy.
--
-- WHY THIS EXISTS
-- ---------------
-- Testing payments happens against the live database (there is no staging
-- project), and two triggers broadcast a push to real captains on every new
-- match request: notify_match_request() mails every captain in the city, and
-- notify_matching_opponents() cross-notifies teams with a compatible request.
-- Creating test fixtures therefore spammed real users. Rather than dropping the
-- triggers (easy to forget, invisible in the schema), both now consult a flag.
--
-- Re-enable with:
--   update app_config set bool_value = true, updated_at = now()
--    where key = 'match_request_broadcast_enabled';

create table if not exists public.app_config (
  key text primary key,
  bool_value boolean not null default false,
  note text,
  updated_at timestamptz not null default now()
);

alter table public.app_config enable row level security;
-- No policies: only the service role (and SECURITY DEFINER functions) may read
-- or write this. App users have no business seeing operational flags.

comment on table public.app_config is
  'Operational feature flags read by trigger functions. Toggle with an UPDATE -- no deploy or DDL needed.';

-- Defaults TRUE at the call sites below so a missing row can never silently
-- mute notifications: muting has to be a deliberate row, not an absent one.
create or replace function public.config_flag(p_key text, p_default boolean default true)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select bool_value from app_config where key = p_key), p_default);
$$;

insert into public.app_config (key, bool_value, note)
values (
  'match_request_broadcast_enabled',
  false,
  'Muted 2026-09-16 while payments are tested against the live database, so real captains are not pushed about test match requests. Set true to resume.'
)
on conflict (key) do nothing;

revoke all on function public.config_flag(text, boolean) from public, anon, authenticated;
grant execute on function public.config_flag(text, boolean) to service_role;

-- The two broadcast triggers now short-circuit on the flag. Both return before
-- writing any notification row, so nothing queues up to be delivered later.
-- (Function bodies are otherwise unchanged from their pre-flag versions.)
