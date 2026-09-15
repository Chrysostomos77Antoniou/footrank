-- FootRank payments: the €2-per-team facilitation fee on a confirmed match.
--
-- WHY FEE-ONLY (and not a full marketplace)
-- -----------------------------------------
-- FootRank never touches the pitch rental money. Teams still settle that with
-- the venue directly (cash, as today) -- we charge only our own platform fee,
-- once per team per match, to that team's captain. That deliberately keeps us
-- out of Stripe Connect, pitch-owner KYC, weekly payout runs and any
-- escrow/PSD2 exposure: the money that lands in our Stripe account is entirely
-- our own revenue, so there is nobody to pay out to.
--
-- The trade-off is that we are NOT selling a guaranteed booking -- we do not
-- own pitch inventory, so we must never imply the slot is reserved.
--
-- WRITE PATH
-- ----------
-- Rows are written exclusively by the `create-match-payment` and
-- `stripe-webhook` Edge Functions using the service role. There are
-- deliberately NO insert/update/delete policies below: a client must never be
-- able to mark itself paid. Only the Stripe webhook may set 'succeeded'.
--
-- This migration is purely additive and enforces nothing: existing matches get
-- payment_status 'unpaid' and every current flow (propose/accept/confirm/score)
-- behaves exactly as before. Gating a match on payment is a separate, later
-- decision.

create table if not exists public.match_payments (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches (id) on delete cascade,
  team_id uuid not null references public.teams (id),
  -- Who was charged. Captured at charge time rather than read back through
  -- teams.captain_id, which can change (transfer_captaincy) or go null once a
  -- captain deletes their account -- we still need to know who actually paid.
  captain_id uuid not null references public.users (id),
  amount_cents integer not null default 200 check (amount_cents > 0),
  currency text not null default 'eur',
  stripe_payment_intent_id text unique,
  status text not null default 'pending'
    check (status in ('pending', 'succeeded', 'failed', 'refunded')),
  -- Stripe's decline/refusal message, kept so the app can tell a captain why
  -- their card was refused instead of a generic "payment failed".
  failure_reason text,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  refunded_at timestamptz,
  -- One charge per team per match. A retry after a decline REUSES this row
  -- (upsert, new payment_intent_id) rather than inserting a second one, so
  -- this constraint is also what makes retries idempotent.
  unique (match_id, team_id)
);

comment on table public.match_payments is
  'One €2 platform-fee charge per team per confirmed match, paid by that team''s '
  'captain. Pitch rental is NOT handled here -- teams pay the venue directly. '
  'Written only by the create-match-payment / stripe-webhook Edge Functions.';

alter table public.match_payments enable row level security;

-- Deliberately tighter than the app's usual "any authenticated user can read"
-- policy (see matches/teams/users): this row carries financial state, so it is
-- visible only to the captain who was charged and that team's own members --
-- not to the opposing team, and not to the whole user base.
create policy "Team can view its own match payments"
  on public.match_payments
  for select
  to authenticated
  using (
    captain_id = (select auth.uid())
    or exists (
      select 1
      from public.team_members tm
      where tm.team_id = match_payments.team_id
        and tm.user_id = (select auth.uid())
    )
  );

-- Derived payment state on the match itself, so the Matches list can show a
-- "paid / awaiting payment" chip without joining match_payments for every row.
alter table public.matches
  add column if not exists payment_status text not null default 'unpaid';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'matches_payment_status_check'
  ) then
    alter table public.matches
      add constraint matches_payment_status_check
      check (payment_status in ('unpaid', 'awaiting_payment', 'paid'));
  end if;
end $$;

comment on column public.matches.payment_status is
  'Derived from match_payments by recalc_match_payment_status(): unpaid = no '
  'charge attempted, awaiting_payment = at least one team has a row but not '
  'both succeeded, paid = both teams'' fees succeeded. Advisory only -- nothing '
  'currently blocks a match from being played or scored while unpaid.';

-- Single source of truth for the derived status, shared by the webhook and any
-- future admin/refund tooling, so the "both teams paid" rule lives in exactly
-- one place. SECURITY DEFINER because the webhook's service-role client calls
-- it, and a later admin RPC may too.
create or replace function public.recalc_match_payment_status(p_match_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_succeeded int;
  v_total int;
  v_status text;
begin
  select count(*) filter (where status = 'succeeded'), count(*)
    into v_succeeded, v_total
  from match_payments
  where match_id = p_match_id;

  -- A match has exactly two teams, so two succeeded fees == fully paid.
  if v_succeeded >= 2 then
    v_status := 'paid';
  elsif v_total > 0 then
    v_status := 'awaiting_payment';
  else
    v_status := 'unpaid';
  end if;

  update matches set payment_status = v_status where id = p_match_id;
  return v_status;
end;
$$;

-- Not callable by app users: payment state is only ever derived server-side
-- from what Stripe told us.
revoke all on function public.recalc_match_payment_status(uuid) from public;
revoke all on function public.recalc_match_payment_status(uuid) from anon;
revoke all on function public.recalc_match_payment_status(uuid) from authenticated;
grant execute on function public.recalc_match_payment_status(uuid) to service_role;
