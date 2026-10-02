-- Match fee credits: if a team has PAID its fee and the match is then
-- cancelled (opponent didn't pay in time, opponent or an admin cancelled, or
-- the team cancelled itself), the fee is not refunded and not lost: it becomes
-- a credit that covers the team's NEXT match fee.
--
-- * A credit belongs to a TEAM (team_id) and is single-use.
-- * It is issued by issue_match_fee_credits(), called from every path that
--   deletes a confirmed match, BEFORE the delete (match_payments cascades).
-- * It is spent by create-match-payment (via consume_match_fee_credit): the
--   fee row is recorded as 'waived' with waiver_source = 'credit', so every
--   existing "settled" check (recalc, reminders, deadline sweep, app) already
--   treats it as paid.
-- * If a match that was paid with a credit is itself cancelled, the credit is
--   given back.
-- * Promo-waived fees move no money and never create a credit.

create table if not exists public.match_fee_credits (
  id                       uuid primary key default gen_random_uuid(),
  team_id                  uuid not null references public.teams (id) on delete cascade,
  amount_cents             integer not null check (amount_cents > 0),
  currency                 text not null default 'eur',
  -- The Stripe payment this credit came from. UNIQUE so a retried cancellation
  -- can never issue the same payment twice.
  source_payment_intent_id text unique,
  source_match_id          uuid,   -- no FK: that match has been deleted
  created_at               timestamptz not null default now(),
  used_at                  timestamptz,
  used_match_id            uuid    -- no FK: kept for the audit trail
);
alter table public.match_fee_credits enable row level security;

create policy "Team members can view their team's fee credits"
  on public.match_fee_credits
  for select
  to authenticated
  using (exists (
    select 1 from public.team_members tm
    where tm.team_id = match_fee_credits.team_id
      and tm.user_id = (select auth.uid())
  ));
-- No insert/update/delete policies: only the SECURITY DEFINER functions below.

create index if not exists match_fee_credits_team_unused_idx
  on public.match_fee_credits (team_id) where used_at is null;

alter table public.match_payments
  add column if not exists waiver_source text
  check (waiver_source in ('promo', 'credit'));

-- ---------------------------------------------------------------------------
-- Issue credits for a match that is about to be deleted.
-- ---------------------------------------------------------------------------
create or replace function public.issue_match_fee_credits(p_match_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_id uuid;
  v_n integer := 0;
begin
  -- A credit that was SPENT on this match goes back to its team, and that
  -- team's captain is told.
  for r in
    select captain_id from public.match_payments
    where match_id = p_match_id and waiver_source = 'credit'
  loop
    update public.match_fee_credits
       set used_at = null, used_match_id = null
     where used_match_id = p_match_id;
    insert into public.notifications (user_id, type, title, body, read)
    values (r.captain_id, 'match_cancelled',
      'Don''t worry — your credit is safe',
      'This match was cancelled, but your saved €2 credit has been given back. '
      || 'Your next match fee is still on us.',
      false);
  end loop;

  -- A fee that was actually PAID becomes a credit.
  for r in
    select team_id, captain_id, amount_cents, currency, stripe_payment_intent_id
    from public.match_payments
    where match_id = p_match_id
      and status = 'succeeded'
      and stripe_payment_intent_id is not null
  loop
    v_id := null;
    insert into public.match_fee_credits
      (team_id, amount_cents, currency, source_payment_intent_id, source_match_id)
    values
      (r.team_id, r.amount_cents, r.currency, r.stripe_payment_intent_id, p_match_id)
    on conflict (source_payment_intent_id) do nothing
    returning id into v_id;

    if v_id is not null then
      v_n := v_n + 1;
      insert into public.notifications (user_id, type, title, body, read)
      values (r.captain_id, 'match_cancelled',
        'Don''t worry — your €2 is saved',
        'Your match was cancelled, but your €2 match fee isn''t lost. It''s saved '
        || 'as credit: your next match fee is on us.',
        false);
    end if;
  end loop;

  return v_n;
end;
$$;

revoke all on function public.issue_match_fee_credits(uuid) from public, anon, authenticated;
grant execute on function public.issue_match_fee_credits(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Spend one credit on a match (called by the create-match-payment function).
-- ---------------------------------------------------------------------------
create or replace function public.consume_match_fee_credit(p_team_id uuid, p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  select id into v_id
  from public.match_fee_credits
  where team_id = p_team_id and used_at is null
  order by created_at
  limit 1
  for update skip locked;

  if v_id is null then
    return false;
  end if;

  update public.match_fee_credits
     set used_at = now(), used_match_id = p_match_id
   where id = v_id;
  return true;
end;
$$;

revoke all on function public.consume_match_fee_credit(uuid, uuid) from public, anon, authenticated;
grant execute on function public.consume_match_fee_credit(uuid, uuid) to service_role;

-- App-facing: how many unused credits a team I belong to has.
create or replace function public.my_team_fee_credits(p_team_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.team_members tm
    where tm.team_id = p_team_id and tm.user_id = auth.uid()
  ) then
    return 0;
  end if;
  return (select count(*)::int from public.match_fee_credits
          where team_id = p_team_id and used_at is null);
end;
$$;

revoke all on function public.my_team_fee_credits(uuid) from public, anon;
grant execute on function public.my_team_fee_credits(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Hook the credit step into every path that deletes a CONFIRMED match.
-- The existing function bodies are patched in place (one added line before the
-- delete) instead of being retyped, so nothing else about them changes.
-- ---------------------------------------------------------------------------
do $patch$
declare
  sig text;
  d text;
  marker constant text := E'  delete from public.matches where id = p_match_id;';
begin
  foreach sig in array array[
    'public.cancel_confirmed_match(uuid)',
    'public.admin_force_cancel_match(uuid,text)',
    'public.auto_cancel_unpaid_match(uuid,boolean,boolean)'
  ] loop
    d := pg_get_functiondef(sig::regprocedure);
    if position('issue_match_fee_credits' in d) = 0 then
      if position(marker in d) = 0 then
        raise exception 'delete marker not found in %', sig;
      end if;
      d := replace(d, marker,
        E'  perform public.issue_match_fee_credits(p_match_id);\n' || marker);
    end if;
    -- The deadline job no longer refunds to the card: the fee is kept as credit.
    d := replace(d, ' and your fee was refunded.', '.');
    execute d;
  end loop;
end
$patch$;
