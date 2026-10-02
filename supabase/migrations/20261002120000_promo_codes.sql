-- Promo codes: "WELCOME" waives the €2 per-team match fee until 15 Nov 2026.
--
-- DESIGN
-- ------
-- * The goal is downloads, not revenue, so abuse protection is deliberately
--   light (see the README note at the bottom).
-- * A redemption belongs to a USER (promo_redemptions.user_id), and a TEAM's
--   fee is waived while ANY current member of that team holds an active
--   redemption. That one rule covers every case without extra bookkeeping:
--     - a new user with no team yet can redeem; the benefit follows them into
--       the first team they create or join;
--     - a member who joins later benefits automatically (their redemption
--       now counts for the team);
--     - a member who leaves takes their redemption with them.
-- * Redeemable until `valid_until`; the benefit also ends at `valid_until`
--   for everyone, however late it was redeemed (redeem on 14 Nov, free until
--   15 Nov).
-- * Fee waiving is decided ONLY on the server (create-match-payment calls
--   team_fee_waived). The client can never mark itself waived.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists public.promo_codes (
  code        text primary key,                 -- stored UPPER-CASE
  type        text not null default 'fee_waiver' check (type in ('fee_waiver')),
  valid_until timestamptz not null,             -- redeem deadline AND benefit end (exclusive)
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  constraint promo_codes_code_upper check (code = upper(code))
);
alter table public.promo_codes enable row level security;
-- No policies: not readable or writable by app users. Only the SECURITY
-- DEFINER functions below (and the service role) touch it.

create table if not exists public.promo_redemptions (
  id          uuid primary key default gen_random_uuid(),
  code        text not null references public.promo_codes (code),
  user_id     uuid not null references public.users (id) on delete cascade,
  redeemed_at timestamptz not null default now(),
  unique (code, user_id)                        -- one redemption per account per code
);
alter table public.promo_redemptions enable row level security;

create policy "Users can view their own promo redemptions"
  on public.promo_redemptions
  for select
  to authenticated
  using (user_id = (select auth.uid()));
-- Deliberately NO insert/update/delete policies: redeeming goes through
-- redeem_promo_code() only.

create index if not exists promo_redemptions_user_idx
  on public.promo_redemptions (user_id);

insert into public.promo_codes (code, type, valid_until)
values ('WELCOME', 'fee_waiver', '2026-11-16 00:00:00+02')  -- = end of 15 Nov, Cyprus time
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- Redeem (called by the app)
-- ---------------------------------------------------------------------------
-- Returns jsonb: {status, valid_until?}
--   status: 'ok' | 'already_redeemed' | 'invalid' | 'expired' | 'rate_limited'
create or replace function public.redeem_promo_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_code public.promo_codes%rowtype;
begin
  if v_uid is null then
    raise exception 'Not signed in';
  end if;

  -- A single well-known code is trivially guessable, but this stops a script
  -- hammering the endpoint.
  if not public.check_rate_limit('redeem_promo_code:' || v_uid::text, 10, 60) then
    return jsonb_build_object('status', 'rate_limited');
  end if;

  select * into v_code
  from public.promo_codes
  where code = upper(btrim(coalesce(p_code, '')));

  if not found or not v_code.active then
    return jsonb_build_object('status', 'invalid');
  end if;

  if now() >= v_code.valid_until then
    return jsonb_build_object('status', 'expired');
  end if;

  if exists (
    select 1 from public.promo_redemptions
    where code = v_code.code and user_id = v_uid
  ) then
    return jsonb_build_object('status', 'already_redeemed',
                              'valid_until', v_code.valid_until);
  end if;

  insert into public.promo_redemptions (code, user_id)
  values (v_code.code, v_uid)
  on conflict (code, user_id) do nothing;

  return jsonb_build_object('status', 'ok', 'valid_until', v_code.valid_until);
end;
$$;

revoke all on function public.redeem_promo_code(text) from public, anon;
grant execute on function public.redeem_promo_code(text) to authenticated;

-- ---------------------------------------------------------------------------
-- "Is this team's fee waived right now?"
-- ---------------------------------------------------------------------------
-- True when any CURRENT member of the (non-disbanded) team holds a redemption
-- of an active fee_waiver code that has not reached its end date.
create or replace function public.team_fee_waived(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.teams t
    join public.team_members tm on tm.team_id = t.id
    join public.promo_redemptions r on r.user_id = tm.user_id
    join public.promo_codes c on c.code = r.code
    where t.id = p_team_id
      and t.disbanded_at is null
      and c.type = 'fee_waiver'
      and c.active
      and now() < c.valid_until
  );
$$;

-- Service role (the Edge Function) only: this is the authority the payment
-- function trusts.
revoke all on function public.team_fee_waived(uuid) from public, anon, authenticated;
grant execute on function public.team_fee_waived(uuid) to service_role;

-- App-facing version: lets the Home banner say "fee waived" instead of
-- "Pay €2". Only answers for a team the caller belongs to.
create or replace function public.my_team_fee_waived(p_team_id uuid)
returns boolean
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
    return false;
  end if;
  return public.team_fee_waived(p_team_id);
end;
$$;

revoke all on function public.my_team_fee_waived(uuid) from public, anon;
grant execute on function public.my_team_fee_waived(uuid) to authenticated;

-- The caller's own active promo, for the "No booking fees until ..." line in
-- Settings. Null when they have none.
create or replace function public.my_active_promo()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object('code', r.code, 'valid_until', c.valid_until)
  from public.promo_redemptions r
  join public.promo_codes c on c.code = r.code
  where r.user_id = auth.uid()
    and c.type = 'fee_waiver'
    and c.active
    and now() < c.valid_until
  order by c.valid_until desc
  limit 1;
$$;

revoke all on function public.my_active_promo() from public, anon;
grant execute on function public.my_active_promo() to authenticated;

-- ---------------------------------------------------------------------------
-- Payments: a 'waived' fee counts as settled
-- ---------------------------------------------------------------------------
alter table public.match_payments drop constraint if exists match_payments_status_check;
alter table public.match_payments
  add constraint match_payments_status_check
  check (status in ('pending', 'succeeded', 'failed', 'refunded', 'waived'));

comment on column public.match_payments.status is
  'pending | succeeded | failed | refunded | waived. ''succeeded'' is set only by '
  'the Stripe webhook; ''waived'' only by create-match-payment when '
  'team_fee_waived() is true (no money moved).';

create or replace function public.recalc_match_payment_status(p_match_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settled int;
  v_total int;
  v_status text;
begin
  select count(*) filter (where status in ('succeeded', 'waived')), count(*)
    into v_settled, v_total
  from match_payments
  where match_id = p_match_id;

  -- A match has exactly two teams, so two settled fees == fully paid.
  if v_settled >= 2 then
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

revoke all on function public.recalc_match_payment_status(uuid) from public, anon, authenticated;
grant execute on function public.recalc_match_payment_status(uuid) to service_role;

-- NOTE on abuse: intentionally not defended (no minimum team size, no
-- device limits, no redemption cap). The promo exists to drive downloads
-- before 15 Nov 2026, when no fee revenue is expected anyway. If that
-- changes, add a cap column to promo_codes and count promo_redemptions here.
