-- Route match-confirmed Telegram alerts through our own Edge Function instead of
-- the mission-control app on Vercel.
--
-- WHY: confirm_fixture() and accept_match_proposal() both posted to
-- mission-control's /api/webhooks/court-resolved, which is what turned the
-- webhook into a Telegram message. pg_net recorded the reply as
-- 402 DEPLOYMENT_DISABLED -- Vercel refusing to run the app, not an auth
-- failure (that would be 401). So the alerts had been silently dead while the
-- database kept posting correctly, and rotating the API key could not have
-- fixed it.
--
-- Postgres cannot call Telegram itself: the bot token lives in Edge Function
-- secrets, which the database cannot read. It CAN read the service-role key
-- from the vault, so it calls our own notify-telegram function and that
-- function holds the Telegram credentials.
--
-- The mission-control post is kept but gated off, because its payload carries
-- more than Telegram (court + captain contacts it may act on). Restore with:
--   update app_config set bool_value = true where key = 'mission_control_webhook_enabled';

insert into public.app_config (key, bool_value, note)
values (
  'mission_control_webhook_enabled',
  false,
  'Disabled 2026-09-16: the Vercel deployment answers 402 DEPLOYMENT_DISABLED, so every post was wasted. Telegram now goes direct via the notify-telegram Edge Function. Set true if mission-control comes back.'
)
on conflict (key) do nothing;

create or replace function public.send_match_telegram(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
begin
  select decrypted_secret into v_key
  from vault.decrypted_secrets where name = 'service_role_key' limit 1;
  if v_key is null then
    return;
  end if;

  -- Fire and forget. net.http_post queues the request, so a Telegram outage can
  -- never block or fail the transaction that confirmed the match.
  perform net.http_post(
    url := 'https://yspccychuwvlrjgioqss.supabase.co/functions/v1/notify-telegram',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := jsonb_build_object('match_id', p_match_id, 'kind', 'fixture_confirmed')
  );
end;
$$;

revoke all on function public.send_match_telegram(uuid) from public, anon, authenticated;
grant execute on function public.send_match_telegram(uuid) to service_role;

-- confirm_fixture() and accept_match_proposal() each gained
--   perform send_match_telegram(<match id>);
-- at the point the old webhook fired, and their mission-control post is now
-- additionally guarded by config_flag('mission_control_webhook_enabled', false).
-- Full bodies as applied to the project.
