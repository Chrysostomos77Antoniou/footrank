-- Shared rate-limiting + suspicious-activity logging for Edge Functions.
-- Requested hardening: rate limit endpoints (#5), cap expensive third-party
-- API usage (#6), log + alert on suspicious activity (#10).

create table if not exists public.rate_limit_state (
  bucket_key text primary key,
  window_start timestamptz not null default now(),
  count integer not null default 0
);
alter table public.rate_limit_state enable row level security;
-- service-role only (no policies -> default deny to anon/authenticated)

create table if not exists public.security_alerts (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  severity text not null default 'warning',
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.security_alerts enable row level security;
-- service-role only (no policies -> default deny to anon/authenticated); an
-- admin_* RPC can be added later to surface these to the admin panel.

-- Fixed-window rate limiter: returns true if the call is allowed (and bumps
-- the counter), false if the caller is over budget for this window.
-- SECURITY DEFINER + no grants to anon/authenticated: only callable from
-- Edge Functions using the service-role key.
create or replace function public.check_rate_limit(
  p_key text, p_max_count integer, p_window_seconds integer
) returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_row public.rate_limit_state;
begin
  select * into v_row from public.rate_limit_state where bucket_key = p_key for update;

  if v_row.bucket_key is null then
    insert into public.rate_limit_state (bucket_key, window_start, count)
    values (p_key, now(), 1);
    return true;
  end if;

  if now() > v_row.window_start + make_interval(secs => p_window_seconds) then
    update public.rate_limit_state
      set window_start = now(), count = 1
      where bucket_key = p_key;
    return true;
  end if;

  if v_row.count >= p_max_count then
    return false;
  end if;

  update public.rate_limit_state set count = count + 1 where bucket_key = p_key;
  return true;
end;
$function$;

revoke execute on function public.check_rate_limit(text, integer, integer) from public;
revoke execute on function public.check_rate_limit(text, integer, integer) from anon;
revoke execute on function public.check_rate_limit(text, integer, integer) from authenticated;

create or replace function public.log_security_alert(
  p_source text, p_severity text, p_detail jsonb
) returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  insert into public.security_alerts (source, severity, detail)
  values (p_source, p_severity, coalesce(p_detail, '{}'::jsonb));
end;
$function$;

revoke execute on function public.log_security_alert(text, text, jsonb) from public;
revoke execute on function public.log_security_alert(text, text, jsonb) from anon;
revoke execute on function public.log_security_alert(text, text, jsonb) from authenticated;
