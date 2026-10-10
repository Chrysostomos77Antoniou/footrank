-- Proof of acceptance of the Terms of Service and Privacy Policy.
--
-- One row per (user, document, version). Users can read their own rows but
-- cannot write directly: rows are only created through record_legal_consent(),
-- which stamps the time server-side. Rows are removed automatically when the
-- auth user is deleted (ON DELETE CASCADE), so account deletion leaves no
-- consent trail behind.

create table if not exists public.user_consents (
  user_id     uuid        not null references auth.users(id) on delete cascade,
  document    text        not null check (document in ('terms', 'privacy')),
  version     text        not null check (char_length(version) between 1 and 40),
  accepted_at timestamptz not null default now(),
  source      text        check (source is null or char_length(source) <= 40),
  primary key (user_id, document, version)
);

alter table public.user_consents enable row level security;

drop policy if exists "Users can read own consents" on public.user_consents;
create policy "Users can read own consents"
  on public.user_consents for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.user_consents from anon, authenticated;
grant select on public.user_consents to authenticated;

create or replace function public.record_legal_consent(
  p_terms_version   text,
  p_privacy_version text,
  p_source          text default 'app'
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.user_consents (user_id, document, version, source)
  values (v_uid, 'terms', p_terms_version, p_source),
         (v_uid, 'privacy', p_privacy_version, p_source)
  on conflict (user_id, document, version) do nothing;
end;
$$;

create or replace function public.has_accepted_legal(
  p_terms_version   text,
  p_privacy_version text
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select (
    select count(*) from public.user_consents
    where user_id = auth.uid()
      and ((document = 'terms'   and version = p_terms_version)
        or (document = 'privacy' and version = p_privacy_version))
  ) = 2;
$$;

revoke all on function public.record_legal_consent(text, text, text) from public, anon;
revoke all on function public.has_accepted_legal(text, text) from public, anon;
grant execute on function public.record_legal_consent(text, text, text) to authenticated;
grant execute on function public.has_accepted_legal(text, text) to authenticated;
