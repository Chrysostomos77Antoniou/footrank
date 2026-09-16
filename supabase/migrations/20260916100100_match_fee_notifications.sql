-- Direct captains to the fee instead of making them find the card.
--
-- Two notification types, both routed to the match detail page by the app
-- (see notification_router.dart), which is where the pay card lives:
--   fee_due   -- inserted here when a fixture becomes confirmed
--   fee_paid  -- inserted by the stripe-webhook Edge Function on success
--
-- fee_due is gated on its own flag because the database cannot know whether a
-- given captain's installed build has payments compiled in -- that depends on
-- STRIPE_PUBLISHABLE_KEY being passed at build time. With the flag off, nobody
-- is told about a fee they have no button to pay.
--
-- Mute with:
--   update app_config set bool_value = false, updated_at = now()
--    where key = 'match_fee_enabled';

insert into public.app_config (key, bool_value, note)
values (
  'match_fee_enabled',
  true,
  'Controls the "fee due" notification sent when a match is confirmed. Set false if captains on older builds (no payment UI) start receiving it.'
)
on conflict (key) do nothing;

-- confirm_fixture() gains the fee_due insert. Everything else in the function
-- -- the captain checks, the status transition, the existing match_accepted
-- notifications and the mission-control/Telegram webhook -- is unchanged; see
-- the full body applied to the project.
