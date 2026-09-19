-- Fix: maybe_send_fee_reminder / send_fee_reminders were callable by any
-- anon/authenticated client with arbitrary match_id/team_id, letting any
-- signed-in (or unauthenticated) caller spam "fee due" notifications to
-- unrelated team captains. These are cron-only internal helpers invoked
-- by the payment-deadline-sweep Edge Function via the service-role key, so
-- lock EXECUTE down to postgres/service_role only.

revoke execute on function public.maybe_send_fee_reminder(uuid, uuid, timestamptz) from public;
revoke execute on function public.maybe_send_fee_reminder(uuid, uuid, timestamptz) from anon;
revoke execute on function public.maybe_send_fee_reminder(uuid, uuid, timestamptz) from authenticated;

revoke execute on function public.send_fee_reminders() from public;
revoke execute on function public.send_fee_reminders() from anon;
revoke execute on function public.send_fee_reminders() from authenticated;
