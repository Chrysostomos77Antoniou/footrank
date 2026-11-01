-- Free-text venue on match requests.
--
-- The captain who opens a request types the venue name (free text). The app
-- never shows names from the courts table. Server-side, the typed text is
-- silently matched (fuzzy, accent/case-insensitive, Greek<->Latin) against the
-- courts table; the link lives in a private table (venue_reviews) that clients
-- cannot read. Requests that match nothing are still published but flagged for
-- the admin dashboard. Also: max 3 requests per captain per match day, a
-- venue-name validator (length, no links/phones, basic profanity), a report
-- function, and a "change venue" function for the captain who opened the
-- request. Every server path that copies a request or a match (accept, cancel,
-- unpaid-fee auto-cancel) carries the typed venue along. Additive, backward
-- compatible and safe to run twice.
--
-- The team that proposes a match may also suggest a different venue (free
-- text, same rules and same flagging as a request's venue). The captain who
-- receives the proposal sees it next to their own and accepts or declines;
-- accepting makes the suggestion the venue of the match. There is no cap on
-- how many proposals a team can send. Old app versions keep working: the new
-- argument of propose_match / propose_match_with_roster has a default.

-- Fail fast instead of queueing (and holding up the app behind it) when one of
-- the tables below is locked by a long-running transaction: just run it again.
set local lock_timeout = '3s';

create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------- columns
alter table public.match_requests add column if not exists venue_text text;
alter table public.matches        add column if not exists venue_text text;
alter table public.match_request_proposals add column if not exists venue_text text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'match_requests_venue_text_len') then
    alter table public.match_requests add constraint match_requests_venue_text_len
      check (venue_text is null or char_length(venue_text) between 2 and 60);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'matches_venue_text_len') then
    alter table public.matches add constraint matches_venue_text_len
      check (venue_text is null or char_length(venue_text) between 2 and 60);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'match_request_proposals_venue_text_len') then
    alter table public.match_request_proposals add constraint match_request_proposals_venue_text_len
      check (venue_text is null or char_length(venue_text) between 2 and 60);
  end if;
end $$;

-- ------------------------------------------------------- private tables
-- No policies and no grants: only SECURITY DEFINER functions touch these.
create table if not exists public.venue_reviews (
  id               uuid primary key default gen_random_uuid(),
  request_id       uuid references public.match_requests(id) on delete cascade,
  match_id         uuid references public.matches(id) on delete cascade,
  venue_text       text not null,
  matched_court_id uuid references public.courts(id) on delete set null,
  match_score      numeric(4,3),
  status           text not null check (status in ('auto', 'flagged', 'approved', 'removed', 'superseded')),
  reason           text,
  created_by       uuid,
  created_at       timestamptz not null default now(),
  reviewed_at      timestamptz,
  reviewed_by      uuid,
  proposal_id      uuid references public.match_request_proposals(id) on delete cascade,
  check (request_id is not null or match_id is not null or proposal_id is not null)
);
-- (only matters if an earlier version of this migration already created the table)
alter table public.venue_reviews
  add column if not exists proposal_id uuid references public.match_request_proposals(id) on delete cascade;
create index if not exists venue_reviews_flagged_idx
  on public.venue_reviews (created_at desc) where status = 'flagged';
create index if not exists venue_reviews_request_idx  on public.venue_reviews (request_id);
create index if not exists venue_reviews_match_idx    on public.venue_reviews (match_id);
create index if not exists venue_reviews_proposal_idx on public.venue_reviews (proposal_id);
alter table public.venue_reviews enable row level security;
revoke all on public.venue_reviews from anon, authenticated;

-- (only matters if an earlier draft of this migration already created the table)
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'venue_reviews_status_check'
               and conrelid = 'public.venue_reviews'::regclass
               and pg_get_constraintdef(oid) not like '%superseded%') then
    alter table public.venue_reviews drop constraint venue_reviews_status_check;
    alter table public.venue_reviews add constraint venue_reviews_status_check
      check (status in ('auto', 'flagged', 'approved', 'removed', 'superseded'));
  end if;
end $$;

create table if not exists public.venue_reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.users(id) on delete cascade,
  request_id  uuid references public.match_requests(id) on delete cascade,
  match_id    uuid references public.matches(id) on delete cascade,
  venue_text  text,
  created_at  timestamptz not null default now(),
  proposal_id uuid references public.match_request_proposals(id) on delete cascade,
  check (request_id is not null or match_id is not null or proposal_id is not null)
);
-- (only matters if an earlier version of this migration already created the tables:
-- they gain the proposal column, and their "request or match" checks and the
-- one-report-per-person index learn about proposals)
alter table public.venue_reports
  add column if not exists proposal_id uuid references public.match_request_proposals(id) on delete cascade;
do $$
declare c record;
begin
  for c in
    select con.conrelid::regclass::text as tbl, con.conname
      from pg_constraint con
     where con.contype = 'c'
       and con.conrelid in ('public.venue_reviews'::regclass, 'public.venue_reports'::regclass)
       and pg_get_constraintdef(con.oid) like '%request_id IS NOT NULL%'
       and pg_get_constraintdef(con.oid) not like '%proposal_id%'
  loop
    execute format('alter table %s drop constraint %I', c.tbl, c.conname);
    execute format('alter table %s add constraint %I check (request_id is not null or match_id is not null or proposal_id is not null)',
                   c.tbl, c.conname);
  end loop;
  if exists (select 1 from pg_indexes
              where schemaname = 'public' and indexname = 'venue_reports_once'
                and indexdef not like '%proposal_id%') then
    drop index public.venue_reports_once;
  end if;
end $$;
create unique index if not exists venue_reports_once on public.venue_reports (
  reporter_id,
  coalesce(request_id,  '00000000-0000-0000-0000-000000000000'::uuid),
  coalesce(match_id,    '00000000-0000-0000-0000-000000000000'::uuid),
  coalesce(proposal_id, '00000000-0000-0000-0000-000000000000'::uuid)
);
alter table public.venue_reports enable row level security;
revoke all on public.venue_reports from anon, authenticated;

-- --------------------------------------------------------------- helpers
-- Trim, turn control characters and Unicode spaces into plain spaces, drop
-- invisible / bidi-control characters, collapse whitespace.
create or replace function public.venue_clean(p_text text)
returns text
language sql
immutable
set search_path = public
as $$
  select nullif(btrim(regexp_replace(
           regexp_replace(
             regexp_replace(coalesce(p_text, ''),
               U&'[\\u0001-\\u001f\\u007f-\\u009f\00A0\1680\2000-\200A\2028\2029\202F\205F\3000]', ' ', 'g'),
             U&'[\00AD\061C\180E\200B-\200F\202A-\202E\2060-\206F\FEFF\\U000e0000-\\U000e007f]', '', 'g'),
           '\s+', ' ', 'g')), '');
$$;

-- Lower-case, strip accents, transliterate Greek to Latin, keep [a-z0-9 ].
create or replace function public.venue_norm(p_text text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  t text;
begin
  if p_text is null then return null; end if;
  t := lower(p_text);
  -- decomposed accents (letter + combining mark, e.g. typed on a Mac) -> letter
  t := regexp_replace(normalize(t, nfd), U&'[\0300-\036F]', '', 'g');
  t := translate(t, U&'\03AC\03AD\03AE\03AF\03CC\03CD\03CE\03CA\03CB\0390\03B0', U&'\03B1\03B5\03B7\03B9\03BF\03C5\03C9\03B9\03C5\03B9\03C5');
  t := translate(t, U&'\00E0\00E1\00E2\00E3\00E4\00E5\00E7\00E8\00E9\00EA\00EB\00EC\00ED\00EE\00EF\00F1\00F2\00F3\00F4\00F5\00F6\00F8\00F9\00FA\00FB\00FC\00FD\00FF', 'aaaaaaceeeeiiiinoooooouuuuyy');
  t := regexp_replace(t, U&'[.''\2019`\00B4]', '', 'g');
  t := replace(t, U&'\03BF\03C5', 'ou');
  t := replace(t, U&'\03B1\03B9', 'e');
  t := replace(t, U&'\03B5\03B9', 'i');
  t := replace(t, U&'\03BF\03B9', 'i');
  t := replace(t, U&'\03BC\03C0', 'b');
  t := replace(t, U&'\03BD\03C4', 'd');
  t := replace(t, U&'\03B3\03BA', 'g');
  t := replace(t, U&'\03B3\03B3', 'g');
  t := replace(t, U&'\03C4\03C3', 'ts');
  t := replace(t, U&'\03C4\03B6', 'tz');
  t := replace(t, U&'\03B1\03C5', 'av');
  t := replace(t, U&'\03B5\03C5', 'ev');
  t := replace(t, U&'\03B8', 'th');
  t := replace(t, U&'\03C7', 'ch');
  t := replace(t, U&'\03C8', 'ps');
  t := translate(t, U&'\03B1\03B2\03B3\03B4\03B5\03B6\03B7\03B9\03BA\03BB\03BC\03BD\03BE\03BF\03C0\03C1\03C3\03C2\03C4\03C5\03C6\03C9', 'avgdeziiklmnxoprsstyfo');
  t := regexp_replace(t, '[^a-z0-9]+', ' ', 'g');
  return nullif(btrim(t), '');
end $$;

-- Distinctive part of a venue name: generic words (futsal, center, football...)
-- are dropped and doubled letters collapsed so "Wembley Futsal" ~ "wembley".
-- Tokens are compared with doubled letters collapsed ("futsall", "footbal"),
-- so the list below is written in that collapsed form.
create or replace function public.venue_core(p_text text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  n    text;
  core text;
begin
  n := public.venue_norm(p_text);
  if n is null then return null; end if;
  select string_agg(u.tok, ' ' order by u.ord)
    into core
    from unnest(string_to_array(n, ' ')) with ordinality as u(tok, ord)
   where regexp_replace(u.tok, '([a-z0-9])\1+', '\1', 'g') <> all (array[
     'futsal','center','centre','centers','centres','fotbal','socer',
     'mini','sport','sports','court','courts','field','fields','pitch','pitches',
     'complex','club','the','of','and','gym','athletic','athletics','municipal',
     'gipedo','gipeda','kentro','kentron','athlitiko','podosfero']);
  if core is null then core := n; end if;
  return nullif(btrim(regexp_replace(core, '([a-z0-9])\1+', '\1', 'g')), '');
end $$;

-- Why a venue text must be refused: 'links' | 'digits' | 'inappropriate' | null.
-- Works on a compatibility-folded copy (full-width letters/digits become plain
-- ones), tolerates simple obfuscation (f*ck, f u c k, leet digits) and matches
-- short words only as whole words so places like "Sussex" or "Assos" pass.
create or replace function public.venue_blocked_reason(p_text text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_raw   text := lower(normalize(coalesce(p_text, ''), nfkc));
  v_norm  text;
  v_tok   text;
  v_run   text := '';
  -- whole-word matches
  v_words constant text[] := array[
    'ass','arse','cock','dick','tit','tits','sex','rape','nazi','hitler','fag',
    'fuk','fck','fvck','phuck','fuq','sht','btch','wank','wanker','wankers',
    'twat','cunt','cunts','prick','bollocks',
    'skata','mouni','mounia','gamo'];
  -- anywhere inside a word
  v_parts constant text := '(fuck|shit|bitch|bastard|pussy|nigg|faggot|whore|slut|porn|penis|vagina|dildo|blowjob|asshole|dickhead|cocksuck|poutsa|pousta|poutan|pousti|malaka|gamoto|gamiso|gamiol|archidia|arxidia)';
begin
  if v_raw ~ '(https?:|www\.|@)'
     or v_raw ~ '[^\s.]\.(com|org|net|cy|gr|eu|io|me|co|info|biz|ly|gl|app|xyz|tv|uk|ai|dev)([^[:alpha:]]|$)' then
    return 'links';
  end if;
  if char_length(regexp_replace(v_raw, U&'[^0-9\0660-\0669\06F0-\06F9]', '', 'g')) >= 6 then
    return 'digits';
  end if;

  -- leet digits -> letters; punctuation used as a mask inside a word is dropped
  v_norm := public.venue_norm(translate(
              regexp_replace(v_raw, '(?<=[a-z0-9])[*#(){}\[\]^~|]+(?=[a-z0-9])', '', 'g'),
              '0134$', 'oieas'));
  if v_norm is null then return null; end if;

  for v_tok in select unnest(string_to_array(v_norm, ' ')) loop
    if v_tok = any (v_words) or v_tok ~ v_parts then
      return 'inappropriate';
    end if;
    -- letters spelled one by one ("f u c k"): check the joined run
    if char_length(v_tok) = 1 then
      v_run := v_run || v_tok;
    else
      if char_length(v_run) >= 4 and (v_run = any (v_words) or v_run ~ v_parts) then
        return 'inappropriate';
      end if;
      v_run := '';
    end if;
  end loop;
  if char_length(v_run) >= 4 and (v_run = any (v_words) or v_run ~ v_parts) then
    return 'inappropriate';
  end if;
  return null;
end $$;

-- Cleans and validates a venue name; returns the cleaned text (null if blank).
-- Raises bad_venue:<code> for the app to translate into a friendly message.
create or replace function public.venue_validate(p_text text)
returns text
language plpgsql
set search_path = public
as $$
declare
  v_text   text;
  v_reason text;
begin
  v_text := public.venue_clean(p_text);
  if v_text is null then return null; end if;
  if char_length(v_text) < 2 or char_length(v_text) > 60 then
    raise exception 'bad_venue:length';
  end if;
  v_reason := public.venue_blocked_reason(v_text);
  if v_reason in ('links', 'digits') then
    raise exception 'bad_venue:contact';
  end if;
  -- at least two letters in any alphabet (cased scripts, plus Arabic, Hebrew,
  -- Indic, Thai, CJK, Hangul which have no upper/lower case)
  if (select count(*) from regexp_split_to_table(v_text, '') as ch
       where lower(ch) <> upper(ch)
          or ch ~ '[[:alpha:]]'
          or ch ~ U&'[\0590-\08FF\0900-\0DFF\0E00-\0EFF\1000-\109F\3040-\30FF\3400-\4DBF\4E00-\9FFF\AC00-\D7AF]') < 2 then
    raise exception 'bad_venue:letters';
  end if;
  if v_reason is not null then
    raise exception 'bad_venue:inappropriate';
  end if;
  return v_text;
end $$;

-- Best-matching row of the courts table for a typed venue (active or not).
-- Same-city courts get a small bonus. Never exposed to clients.
create or replace function public.venue_best_match(p_text text, p_city text)
returns table (court_id uuid, score numeric, same_city boolean)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  a text;
begin
  a := public.venue_core(p_text);
  if a is null or char_length(a) < 3 then return; end if;
  return query
    select s.id,
           round(least(1.0, s.raw + case when s.same then 0.05 else 0 end)::numeric, 3),
           s.same
      from (
        select c.id,
               coalesce(lower(c.city) = lower(coalesce(p_city, '')), false) as same,
               greatest(
                 similarity(a, public.venue_core(c.name))::float8,
                 word_similarity(a, public.venue_core(c.name))::float8 * 0.95,
                 word_similarity(public.venue_core(c.name), a)::float8 * 0.9,
                 case when a = public.venue_core(c.name) then 1.0::float8 else 0::float8 end
               ) as raw
          from public.courts c
      ) s
     -- A same-city court that clearly matches always wins over a (possibly
     -- higher-scoring) court in another city; otherwise take the best overall.
     order by (s.same and s.raw + 0.05 >= 0.55) desc, 2 desc, 3 desc, s.id
     limit 1;
end $$;

-- Writes the (private) review row for a typed venue: auto-linked when it
-- clearly matches a court in the same city, otherwise flagged for the admin.
drop function if exists public.venue_record_review(uuid, uuid, text, text, uuid, text);
create or replace function public.venue_record_review(
  p_request_id   uuid,
  p_match_id     uuid,
  p_text         text,
  p_city         text,
  p_user         uuid,
  p_force_reason text default null,
  p_proposal_id  uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_court  uuid;
  v_score  numeric;
  v_same   boolean;
  v_status text;
  v_reason text;
begin
  select b.court_id, b.score, b.same_city
    into v_court, v_score, v_same
    from public.venue_best_match(p_text, p_city) b;

  if p_force_reason is not null then
    v_status := 'flagged'; v_reason := p_force_reason;
  elsif v_court is null or v_score < 0.55 then
    v_status := 'flagged'; v_reason := 'no_match';
  elsif not v_same then
    v_status := 'flagged'; v_reason := 'other_city';
  else
    v_status := 'auto';
  end if;

  insert into public.venue_reviews
    (request_id, match_id, proposal_id, venue_text, matched_court_id, match_score, status, reason, created_by)
  values
    (p_request_id, p_match_id, p_proposal_id, p_text,
     case when v_score >= 0.3 then v_court end, v_score, v_status, v_reason, p_user);
end $$;

-- --------------------------------------------------------------- triggers
-- The captain's own text is validated strictly. Rows created on someone else's
-- behalf (cancel / unpaid-fee flows copy the text of an existing match, which
-- was validated when it was typed) must never fail because of the text: if it
-- no longer passes, it is dropped and the row is created without a venue.
create or replace function public.trg_request_venue_validate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.venue_text is null then return new; end if;
  if auth.uid() is not null and auth.uid() = new.captain_id then
    new.venue_text := public.venue_validate(new.venue_text);
  else
    begin
      new.venue_text := public.venue_validate(new.venue_text);
    exception when others then
      new.venue_text := null;
    end;
  end if;
  return new;
end $$;

-- At most 3 requests per captain for the same match day (Cyprus calendar day).
-- Skipped when the row is created on someone else's behalf (cancel flow).
-- Concurrent inserts of the same captain for the same day are serialized with
-- an advisory lock so two parallel requests cannot both slip under the limit.
create or replace function public.enforce_match_request_daily_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_day   date;
begin
  if auth.uid() is null or auth.uid() <> new.captain_id then
    return new;
  end if;
  v_day := (new.scheduled_at at time zone 'Asia/Nicosia')::date;
  perform pg_advisory_xact_lock(
    hashtextextended('match_request_day:' || new.captain_id::text || ':' || v_day::text, 0));
  select count(*) into v_count
    from public.match_requests r
   where r.captain_id = new.captain_id
     and (r.scheduled_at at time zone 'Asia/Nicosia')::date = v_day;
  if v_count >= 3 then
    raise exception 'daily_limit: you can post up to 3 match requests for the same day';
  end if;
  return new;
end $$;

-- A failure of the (best-effort) matcher must never stop a request from being
-- posted: fall back to a flagged review so the admin sees it.
create or replace function public.trg_request_venue_review()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.venue_text is not null then
    begin
      perform public.venue_record_review(new.id, null, new.venue_text, new.city, new.captain_id);
    exception when others then
      raise warning 'venue review failed for request %: %', new.id, sqlerrm;
      begin
        insert into public.venue_reviews (request_id, venue_text, status, reason, created_by)
        values (new.id, new.venue_text, 'flagged', 'review_error', new.captain_id);
      exception when others then
        raise warning 'venue review fallback failed for request %: %', new.id, sqlerrm;
      end;
    end;
  end if;
  return new;
end $$;

drop trigger if exists trg_match_request_daily_limit on public.match_requests;
create trigger trg_match_request_daily_limit
  before insert on public.match_requests
  for each row execute function public.enforce_match_request_daily_limit();

drop trigger if exists trg_match_request_venue_validate on public.match_requests;
create trigger trg_match_request_venue_validate
  before insert on public.match_requests
  for each row execute function public.trg_request_venue_validate();

drop trigger if exists trg_match_request_venue_review on public.match_requests;
create trigger trg_match_request_venue_review
  after insert on public.match_requests
  for each row execute function public.trg_request_venue_review();

-- A request that goes back to "searching" after its match was cancelled keeps
-- the match's venue. Reviews of that venue that belonged to the match are gone
-- with it, so the request gets a review of its own again (idempotent).
create or replace function public.venue_ensure_request_review(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r public.match_requests;
begin
  select * into r from public.match_requests where id = p_request_id;
  if r.id is null or r.venue_text is null then return; end if;
  if exists (select 1 from public.venue_reviews v
              where v.request_id = r.id and v.proposal_id is null
                and v.status in ('auto', 'flagged', 'approved')) then
    return;
  end if;
  begin
    perform public.venue_record_review(r.id, null, r.venue_text, r.city, r.captain_id);
  exception when others then
    raise warning 'venue review failed for request %: %', r.id, sqlerrm;
    begin
      insert into public.venue_reviews (request_id, venue_text, status, reason, created_by)
      values (r.id, r.venue_text, 'flagged', 'review_error', r.captain_id);
    exception when others then
      raise warning 'venue review fallback failed for request %: %', r.id, sqlerrm;
    end;
  end;
end $$;

-- ------------------------------------- match creation: carry the venue over
create or replace function public.accept_match_proposal(p_proposal_id uuid)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_prop public.match_request_proposals;
  v_req public.match_requests;
  v_match_id uuid;
  v_court_id uuid;
  v_home_name text;
  v_away_name text;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_other record;
  v_home_cap uuid;
  v_away_cap uuid;
  v_webhook_token text;
  v_req_rating integer;
  v_prop_rating integer;
  v_max_gap integer;
  v_final_venue text;
  v_rid uuid;
begin
  -- Rows are locked in one fixed order everywhere (match, request, proposal,
  -- venue review), so that two people working on the same request, for
  -- instance a captain accepting and an admin removing its venue, can never
  -- wait for each other.
  select p.request_id into v_rid from public.match_request_proposals p where p.id = p_proposal_id;
  if v_rid is null then raise exception 'Proposal not found'; end if;
  select * into v_req from public.match_requests where id = v_rid for update;
  select * into v_prop from public.match_request_proposals where id = p_proposal_id for update;
  if v_prop.id is null then raise exception 'Proposal not found'; end if;
  if v_prop.status <> 'pending' then raise exception 'This proposal has already been resolved'; end if;
  if v_req.id is null then raise exception 'Match request not found'; end if;
  if not exists (select 1 from public.teams where id = v_req.team_id and captain_id = auth.uid()) then
    raise exception 'Only your team''s captain can accept a proposal';
  end if;
  if v_req.status <> 'searching' then raise exception 'This request is no longer open'; end if;

  if exists (select 1 from public.teams where id = v_req.team_id and disbanded_at is not null) then
    raise exception 'Your team has been disbanded';
  end if;
  if exists (select 1 from public.teams where id = v_prop.proposing_team_id and disbanded_at is not null) then
    raise exception 'The proposing team has been disbanded';
  end if;
  if (select count(*) from public.team_members where team_id = v_req.team_id) < 5 then
    raise exception 'Your team no longer has 5 players, so this match cannot be confirmed';
  end if;
  if (select count(*) from public.team_members where team_id = v_prop.proposing_team_id) < 5 then
    raise exception 'The proposing team no longer has 5 players';
  end if;

  select coalesce(rating, 1500) into v_req_rating from public.teams where id = v_req.team_id;
  select coalesce(rating, 1500) into v_prop_rating from public.teams where id = v_prop.proposing_team_id;
  v_max_gap := public.max_allowed_rating_gap(v_req.id, v_req.team_id, v_req.city, v_req.scheduled_at);
  if abs(v_prop_rating - v_req_rating) > v_max_gap then
    raise exception 'rating_gap_too_large: % vs % (max % right now)',
      v_prop_rating, v_req_rating, v_max_gap;
  end if;

  if exists (
    select 1 from public.matches m
    where m.status = 'confirmed'
      and (m.home_team_id = v_req.team_id or m.away_team_id = v_req.team_id)
      and abs(extract(epoch from (m.scheduled_at - v_req.scheduled_at))) < 90 * 60
  ) then
    raise exception 'Your team already has a confirmed match within 1:30 of that time';
  end if;
  if exists (
    select 1 from public.matches m
    where m.status = 'confirmed'
      and (m.home_team_id = v_prop.proposing_team_id or m.away_team_id = v_prop.proposing_team_id)
      and abs(extract(epoch from (m.scheduled_at - v_req.scheduled_at))) < 90 * 60
  ) then
    raise exception 'The proposing team already has a confirmed match within 1:30 of that time';
  end if;

  select name into v_home_name from public.teams where id = v_req.team_id;
  select name into v_away_name from public.teams where id = v_prop.proposing_team_id;

  -- New flow: the typed venue (the request's, or the one the proposing team
  -- suggested) is copied onto the match verbatim and no court row is exposed.
  -- Legacy requests (no venue text) keep the court-pick path.
  v_final_venue := coalesce(v_prop.venue_text, v_req.venue_text);
  if v_final_venue is null then
    select court_id into v_court_id from public.match_request_court_picks where request_id = v_req.id and rank = 1;
  end if;

  insert into public.matches (request_id, home_team_id, away_team_id, city,
    scheduled_at, match_type, format, status, home_ok, away_ok,
    suggested_court_id, court_booking_status, court_resolved_at, venue_text)
  values (v_req.id, v_req.team_id, v_prop.proposing_team_id, v_req.city,
    v_req.scheduled_at, v_req.match_type, v_req.format, 'confirmed', true, true,
    v_court_id, case when v_court_id is not null then 'pending' else null end,
    case when v_court_id is not null then now() else null end, v_final_venue)
  returning id into v_match_id;

  update public.match_requests set status = 'confirmed' where id = v_req.id;
  update public.match_request_proposals set status = 'accepted', resolved_at = now() where id = p_proposal_id;

  -- The proposing team's venue suggestion was accepted: it replaces the
  -- request's own text everywhere, the old text's reviews and reports are
  -- closed (as when a captain changes the venue), and the suggestion's review
  -- now belongs to the match.
  if v_prop.venue_text is not null then
    update public.match_requests set venue_text = v_prop.venue_text where id = v_req.id;
    update public.venue_reviews set status = 'superseded', reviewed_at = now()
     where request_id = v_req.id and proposal_id is null
       and status in ('auto', 'flagged', 'approved');
    delete from public.venue_reports where request_id = v_req.id and proposal_id is null;
    update public.venue_reviews set match_id = v_match_id, request_id = v_req.id
     where proposal_id = p_proposal_id and status <> 'superseded';
    update public.venue_reports set match_id = v_match_id, request_id = v_req.id
     where proposal_id = p_proposal_id;
  end if;

  for v_other in
    select id, proposing_user_id from public.match_request_proposals
    where request_id = v_req.id and id <> p_proposal_id and status = 'pending'
  loop
    update public.match_request_proposals set status = 'cancelled', resolved_at = now() where id = v_other.id;
    insert into public.notifications (user_id, type, title, body, read, reference_id)
    values (v_other.proposing_user_id, 'match_proposal_declined', 'Another team was picked',
      coalesce(v_home_name, 'The captain') || ' accepted a different proposal for the ' || v_req.city || ' match.',
      false, v_req.id);
  end loop;

  v_day_start := v_req.scheduled_at - interval '90 minutes';
  v_day_end := v_req.scheduled_at + interval '90 minutes';
  for v_other in
    select mrp.id, mrp.proposing_user_id
    from public.match_request_proposals mrp
    join public.match_requests mr on mr.id = mrp.request_id
    where mrp.status = 'pending'
      and mrp.id <> p_proposal_id
      and mr.scheduled_at > v_day_start and mr.scheduled_at < v_day_end
      and (
        mrp.proposing_team_id in (v_req.team_id, v_prop.proposing_team_id)
        or mr.team_id in (v_req.team_id, v_prop.proposing_team_id)
      )
  loop
    update public.match_request_proposals set status = 'cancelled', resolved_at = now() where id = v_other.id;
    insert into public.notifications (user_id, type, title, body, read, reference_id)
    values (v_other.proposing_user_id, 'match_proposal_declined', 'Proposal cancelled',
      'A team in this proposal already confirmed a match within 1:30 of that time.',
      false, v_req.id);
  end loop;

  if v_court_id is not null then
    insert into public.notifications (user_id, type, title, body, read, reference_id)
    select t.captain_id, 'court_suggested', 'Court set for your match',
      co.name || coalesce(U&' \2014 ' || co.address, ''), false, v_match_id
    from public.teams t, public.courts co
    where t.id in (v_req.team_id, v_prop.proposing_team_id) and co.id = v_court_id and t.captain_id is not null;

    select captain_id into v_home_cap from public.teams where id = v_req.team_id;
    select captain_id into v_away_cap from public.teams where id = v_prop.proposing_team_id;

    select decrypted_secret into v_webhook_token
    from vault.decrypted_secrets where name = 'mission_control_webhook_token' limit 1;

    if v_webhook_token is not null and config_flag('mission_control_webhook_enabled', false) then
      perform net.http_post(
        url := 'https://mission-control-psi-puce.vercel.app/api/webhooks/court-resolved',
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_webhook_token),
        body := jsonb_build_object(
          'match_id', v_match_id,
          'city', v_req.city,
          'scheduled_at', v_req.scheduled_at,
          'court_name', (select name from public.courts where id = v_court_id),
          'court_phone', (select phone from public.courts where id = v_court_id),
          'court_address', (select address from public.courts where id = v_court_id),
          'home_team', v_home_name,
          'away_team', v_away_name,
          'home_captain_name', (select u.name from public.users u where u.id = v_home_cap),
          'home_captain_phone', (select uc.phone from public.user_contacts uc where uc.user_id = v_home_cap),
          'home_captain_email', (select au.email from auth.users au where au.id = v_home_cap),
          'away_captain_name', (select u.name from public.users u where u.id = v_away_cap),
          'away_captain_phone', (select uc.phone from public.user_contacts uc where uc.user_id = v_away_cap),
          'away_captain_email', (select au.email from auth.users au where au.id = v_away_cap)
        )
      );
    end if;
  end if;

  if v_req.venue_text is not null and v_prop.venue_text is null then
    insert into public.notifications (user_id, type, title, body, read, reference_id)
    select t.captain_id, 'court_suggested', 'Venue for your match',
      v_req.venue_text || U&' \00B7 ' || v_req.city, false, v_match_id
    from public.teams t
    where t.id = v_prop.proposing_team_id and t.captain_id is not null;
  end if;

  insert into public.notifications (user_id, type, title, body, read, reference_id)
  values (v_prop.proposing_user_id, 'match_accepted', 'Proposal accepted!',
    coalesce(v_home_name, 'The captain') || ' accepted your proposal. Match confirmed!' ||
    case when v_prop.venue_text is not null then ' They agreed to your venue.' else '' end,
    false, v_match_id);

  return v_match_id;
end;
$function$;

-- ------------------------------------ venue suggested on a proposal
-- The old signatures are dropped so that PostgREST never sees two overloads of
-- the same function (a call that omits the new argument would be ambiguous).
-- Calls from older app versions simply use the default.
drop function if exists public.propose_match_with_roster(uuid, uuid, uuid[]);
drop function if exists public.propose_match(uuid, uuid);

create or replace function public.propose_match(
  p_request_id uuid,
  p_team_id    uuid,
  p_venue_text text default null
)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_req public.match_requests;
  v_proposal_id uuid;
  v_team_name text;
  v_req_rating integer;
  v_team_rating integer;
  v_max_gap integer;
  v_venue text;
begin
  if not exists (select 1 from public.team_members tm where tm.team_id = p_team_id and tm.user_id = auth.uid()) then
    raise exception 'Only a member of this team can propose a match';
  end if;

  -- The suggested venue gets the same checks as a request's venue (length,
  -- letters, no links or phone numbers, basic profanity): bad text is refused
  -- with a bad_venue:* error, blank text simply means "no suggestion".
  if p_venue_text is not null then
    v_venue := public.venue_validate(p_venue_text);
  end if;

  select * into v_req from public.match_requests where id = p_request_id for update;
  if v_req.id is null then raise exception 'Match request not found'; end if;
  if v_req.status <> 'searching' then raise exception 'This request is no longer open'; end if;
  if v_req.team_id = p_team_id then raise exception 'Cannot propose against your own request'; end if;

  if exists (select 1 from public.teams where id = v_req.team_id and disbanded_at is not null) then
    raise exception 'The requesting team has been disbanded';
  end if;
  if exists (select 1 from public.teams where id = p_team_id and disbanded_at is not null) then
    raise exception 'Your team has been disbanded';
  end if;

  if (select count(*) from public.team_members where team_id = v_req.team_id) < 5 then
    raise exception 'The requesting team no longer has 5 players';
  end if;
  if (select count(*) from public.team_members where team_id = p_team_id) < 5 then
    raise exception 'Your team needs at least 5 players to propose a match';
  end if;

  select coalesce(rating, 1500) into v_req_rating from public.teams where id = v_req.team_id;
  select coalesce(rating, 1500) into v_team_rating from public.teams where id = p_team_id;
  v_max_gap := public.max_allowed_rating_gap(v_req.id, v_req.team_id, v_req.city, v_req.scheduled_at);
  if abs(v_team_rating - v_req_rating) > v_max_gap then
    raise exception 'rating_gap_too_large: % vs % (max % right now)',
      v_team_rating, v_req_rating, v_max_gap;
  end if;

  if exists (
    select 1 from public.matches m
    where m.status = 'confirmed'
      and (m.home_team_id = p_team_id or m.away_team_id = p_team_id)
      and abs(extract(epoch from (m.scheduled_at - v_req.scheduled_at))) < 90 * 60
  ) then
    raise exception 'Your team already has a confirmed match within 1:30 of that time';
  end if;

  if exists (
    select 1 from public.match_request_proposals
    where request_id = p_request_id and proposing_team_id = p_team_id and status = 'pending'
  ) then
    raise exception 'Your team already has a pending proposal for this request';
  end if;

  -- Suggesting the very venue the captain already typed is not a suggestion.
  if v_venue is not null and v_req.venue_text is not null
     and public.venue_norm(v_venue) = public.venue_norm(v_req.venue_text) then
    v_venue := null;
  end if;

  insert into public.match_request_proposals (request_id, proposing_team_id, proposing_user_id, venue_text)
  values (p_request_id, p_team_id, auth.uid(), v_venue)
  returning id into v_proposal_id;

  -- Best-effort fuzzy match / flag for the admin dashboard, like a request's
  -- venue: a failure of the matcher must never stop the proposal.
  if v_venue is not null then
    begin
      perform public.venue_record_review(null, null, v_venue, v_req.city, auth.uid(), null, v_proposal_id);
    exception when others then
      raise warning 'venue review failed for proposal %: %', v_proposal_id, sqlerrm;
      begin
        insert into public.venue_reviews (proposal_id, venue_text, status, reason, created_by)
        values (v_proposal_id, v_venue, 'flagged', 'review_error', auth.uid());
      exception when others then
        raise warning 'venue review fallback failed for proposal %: %', v_proposal_id, sqlerrm;
      end;
    end;
  end if;

  select name into v_team_name from public.teams where id = p_team_id;

  insert into public.notifications (user_id, type, title, body, read, reference_id)
  values (v_req.captain_id, 'match_proposal', 'New match proposal',
    coalesce(v_team_name, 'A team') || ' wants to play your match in ' || v_req.city ||
    case when v_venue is not null then ' and suggests a different venue' else '' end ||
    '. Review it in Matches.',
    false, p_request_id);

  return v_proposal_id;
end;
$function$;

create or replace function public.propose_match_with_roster(
  p_request_id      uuid,
  p_team_id         uuid,
  p_roster_user_ids uuid[],
  p_venue_text      text default null
)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_id uuid;
begin
  if not exists (
    select 1 from public.team_members tm
     where tm.team_id = p_team_id and tm.user_id = auth.uid()
       and tm.role in ('captain', 'vice_captain')
  ) then
    raise exception 'Only the captain or vice-captain can choose the roster';
  end if;
  v_id := public.propose_match(p_request_id, p_team_id, p_venue_text);
  update public.match_request_proposals
     set roster_user_ids = p_roster_user_ids
   where id = v_id;
  return v_id;
end;
$function$;

-- Same as before, plus a hint for the proposing team when it had suggested a venue.
create or replace function public.reject_match_proposal(p_proposal_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_prop public.match_request_proposals;
  v_req public.match_requests;
  v_team_name text;
begin
  select * into v_prop from public.match_request_proposals where id = p_proposal_id for update;
  if v_prop.id is null then raise exception 'Proposal not found'; end if;
  if v_prop.status <> 'pending' then raise exception 'This proposal has already been resolved'; end if;

  select * into v_req from public.match_requests where id = v_prop.request_id;
  if not exists (select 1 from public.teams where id = v_req.team_id and captain_id = auth.uid()) then
    raise exception 'Only your team''s captain can decline a proposal';
  end if;

  update public.match_request_proposals set status = 'rejected', resolved_at = now() where id = p_proposal_id;

  select name into v_team_name from public.teams where id = v_req.team_id;

  insert into public.notifications (user_id, type, title, body, read, reference_id)
  values (v_prop.proposing_user_id, 'match_proposal_declined', 'Proposal declined',
    coalesce(v_team_name, 'The captain') || ' declined your proposal for the ' || v_req.city || ' match.' ||
    case when v_prop.venue_text is not null then ' You can send a new proposal with a different venue.' else '' end,
    false, v_req.id);
end;
$function$;

create or replace function public.accept_match_request(
  p_request_id uuid,
  p_away_team_id uuid,
  p_my_request_id uuid default null::uuid
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_req public.match_requests;
  v_my_req public.match_requests;
  v_match_id uuid;
  v_away_name text;
  v_home_name text;
  v_away_captain_id uuid;
  v_best_score int := -1;
  v_best_court uuid;
  v_my_first_pick_at timestamptz;
  v_their_first_pick_at timestamptz;
  v_row record;
  v_req_rating integer;
  v_away_rating integer;
  v_max_gap integer;
begin
  if not exists (select 1 from public.team_members tm where tm.team_id=p_away_team_id and tm.user_id=auth.uid()) then
    raise exception 'Only a team member can accept matches';
  end if;
  select * into v_req from public.match_requests where id=p_request_id for update;
  if v_req.id is null then raise exception 'Match request not found'; end if;
  if v_req.status <> 'searching' then raise exception 'Match request is no longer available'; end if;
  if v_req.team_id = p_away_team_id then raise exception 'Cannot accept your own request'; end if;

  if exists (select 1 from public.teams where id = v_req.team_id and disbanded_at is not null) then
    raise exception 'The requesting team has been disbanded';
  end if;
  if exists (select 1 from public.teams where id = p_away_team_id and disbanded_at is not null) then
    raise exception 'Your team has been disbanded';
  end if;

  if (select count(*) from public.team_members where team_id = v_req.team_id) < 5 then
    raise exception 'The requesting team no longer has 5 players, so this match cannot be accepted';
  end if;
  if (select count(*) from public.team_members where team_id = p_away_team_id) < 5 then
    raise exception 'Your team needs at least 5 players to accept a match';
  end if;

  select coalesce(rating, 1500) into v_req_rating from public.teams where id = v_req.team_id;
  select coalesce(rating, 1500) into v_away_rating from public.teams where id = p_away_team_id;
  v_max_gap := public.max_allowed_rating_gap(v_req.id, v_req.team_id, v_req.city, v_req.scheduled_at);
  if abs(v_away_rating - v_req_rating) > v_max_gap then
    raise exception 'rating_gap_too_large: % vs % (max % right now)',
      v_away_rating, v_req_rating, v_max_gap;
  end if;

  if p_my_request_id is not null then
    select * into v_my_req from public.match_requests where id=p_my_request_id;
    if v_my_req.id is null or v_my_req.team_id <> p_away_team_id then
      raise exception 'Your own match request was not found';
    end if;
  end if;

  select name into v_home_name from public.teams where id=v_req.team_id;
  select name, captain_id into v_away_name, v_away_captain_id from public.teams where id=p_away_team_id;

  insert into public.matches (request_id, home_team_id, away_team_id, city,
    scheduled_at, match_type, format, status, away_ok, home_ok, venue_text)
  values (v_req.id, v_req.team_id, p_away_team_id, v_req.city,
    v_req.scheduled_at, v_req.match_type, v_req.format, 'pending', true, false, v_req.venue_text)
  returning id into v_match_id;

  update public.match_requests set status='confirmed' where id=v_req.id;
  update public.match_requests set status='confirmed'
    where team_id=p_away_team_id and status='searching' and city ilike v_req.city
      and scheduled_at between v_req.scheduled_at - interval '30 minutes'
                          and v_req.scheduled_at + interval '30 minutes';

  -- Legacy court-pick resolution only applies to requests with no typed venue.
  if v_req.venue_text is null then
    if p_my_request_id is not null then
      for v_row in
        select mine.court_id, (4 - mine.rank) + (4 - theirs.rank) as score
        from public.match_request_court_picks mine
        join public.match_request_court_picks theirs
          on theirs.court_id = mine.court_id
        where mine.request_id = p_my_request_id and theirs.request_id = p_request_id
      loop
        if v_row.score > v_best_score then
          v_best_score := v_row.score;
          v_best_court := v_row.court_id;
        end if;
      end loop;
    end if;

    if v_best_court is null then
      select min(created_at) into v_my_first_pick_at
        from public.match_request_court_picks where request_id = p_my_request_id;
      select min(created_at) into v_their_first_pick_at
        from public.match_request_court_picks where request_id = p_request_id;
      if v_their_first_pick_at is not null and (v_my_first_pick_at is null or v_their_first_pick_at <= v_my_first_pick_at) then
        select court_id into v_best_court from public.match_request_court_picks
          where request_id = p_request_id and rank = 1;
      else
        select court_id into v_best_court from public.match_request_court_picks
          where request_id = p_my_request_id and rank = 1;
      end if;
    end if;

    if v_best_court is not null then
      update public.matches
        set suggested_court_id = v_best_court, court_booking_status = 'pending', court_resolved_at = now()
        where id = v_match_id;

      insert into public.notifications (user_id, type, title, body, read, reference_id)
      select t.captain_id, 'court_suggested', 'Court suggested for your match',
        co.name || coalesce(U&' \2014 ' || co.address, ''), false, v_match_id
      from public.teams t, public.courts co
      where t.id in (v_req.team_id, p_away_team_id) and co.id = v_best_court;
    end if;
  end if;

  insert into public.notifications (user_id, type, title, body, read, reference_id)
  values (v_req.captain_id, 'match_request', 'Match requested',
    coalesce(v_away_name,'A team')||' wants to play your match in '||v_req.city||'. Confirm it in Matches.', false, v_match_id);

  return v_match_id;
end;
$function$;

-- When the home captain cancels, the opponent's slot reopens as a fresh
-- request; it now carries the venue text as a starting default.
create or replace function public.cancel_confirmed_match(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  m public.matches;
  v_my_team_id uuid;
  v_opp_team_id uuid;
  v_i_am_home boolean;
  v_penalize boolean;
  v_opp_captain uuid;
  v_opp_name text;
  v_my_name text;
  v_new_request_id uuid;
begin
  select * into m from public.matches where id = p_match_id for update;
  if m.id is null then raise exception 'Match not found'; end if;
  if m.status <> 'confirmed' then
    raise exception 'Only a confirmed, upcoming match can be cancelled this way';
  end if;

  if exists (select 1 from public.teams t where t.id = m.home_team_id and t.captain_id = auth.uid()) then
    v_my_team_id := m.home_team_id;
    v_opp_team_id := m.away_team_id;
    v_i_am_home := true;
  elsif exists (select 1 from public.teams t where t.id = m.away_team_id and t.captain_id = auth.uid()) then
    v_my_team_id := m.away_team_id;
    v_opp_team_id := m.home_team_id;
    v_i_am_home := false;
  else
    raise exception 'Only a participating captain can cancel this match';
  end if;

  -- Free to cancel more than 2 hours out; a 200 Pitch Power penalty applies from
  -- the 2-hour mark onward (including after kick-off, if it was never scored).
  v_penalize := now() >= (m.scheduled_at - interval '2 hours');

  select captain_id, name into v_opp_captain, v_opp_name from public.teams where id = v_opp_team_id;
  select name into v_my_name from public.teams where id = v_my_team_id;

  insert into public.match_cancellations
    (match_id, home_team_id, home_team_name, away_team_id, away_team_name,
     city, scheduled_at, match_type, cancelled_by_team_id, cancelled_by_user_id, penalized)
  values
    (m.id, m.home_team_id, coalesce((select name from public.teams where id = m.home_team_id), '?'),
     m.away_team_id, coalesce((select name from public.teams where id = m.away_team_id), '?'),
     m.city, m.scheduled_at, m.match_type, v_my_team_id, auth.uid(), v_penalize);

  -- Delete the match first so the "no overlapping commitment" trigger doesn't
  -- see it and block re-opening the opponent's slot at the very same time.
  perform public.issue_match_fee_credits(p_match_id);
  delete from public.matches where id = p_match_id;

  if v_penalize then
    -- The whole squad broke the commitment, so each member loses 200 Pitch
    -- Power; the team's average therefore drops by the same 200 as before,
    -- but now it sticks instead of being recalculated away.
    update public.users u
       set elo = greatest(0, u.elo - 200)
      from public.team_members tm
     where tm.team_id = v_my_team_id and u.id = tm.user_id;
  end if;

  if v_i_am_home then
    -- Opponent is the away team; there's no stored reference to their original
    -- request, so open a fresh one for them with the same slot/format, carrying
    -- over the home side's venue (and any legacy court picks) as a default.
    insert into public.match_requests (team_id, captain_id, city, scheduled_at, match_type, format, status, venue_text)
    values (v_opp_team_id, v_opp_captain, m.city, m.scheduled_at, m.match_type, m.format, 'searching', m.venue_text)
    returning id into v_new_request_id;

    insert into public.match_request_court_picks (request_id, court_id, rank)
    select v_new_request_id, court_id, rank
    from public.match_request_court_picks
    where request_id = m.request_id;
  else
    -- Opponent is the home team; their original request IS m.request_id -- just reopen it.
    update public.match_requests set status = 'searching'
      where id = m.request_id and status = 'confirmed';
    perform public.venue_ensure_request_review(m.request_id);
  end if;

  insert into public.notifications (user_id, type, title, body, read, reference_id)
  values (v_opp_captain, 'match_cancelled', 'Match cancelled',
    coalesce(v_my_name, 'The opponent') || ' cancelled your match in ' || m.city ||
    '. You''re back in the matchmaking pool to find a new opponent.',
    false, v_new_request_id);

  return jsonb_build_object('penalized', v_penalize);
end;
$function$;

-- Unpaid-fee sweep (service role): when a side held up its end, its reopened
-- request keeps the typed venue, exactly like a cancel by the home captain.
CREATE OR REPLACE FUNCTION public.auto_cancel_unpaid_match(p_match_id uuid, p_home_paid boolean, p_away_paid boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  m public.matches;
  v_home_name text;
  v_away_name text;
  v_home_captain uuid;
  v_away_captain uuid;
  v_new_request_id uuid;
begin
  select * into m from public.matches where id = p_match_id for update;
  if m.id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if m.status <> 'confirmed' then
    -- Already resolved (paid up since, cancelled by a captain, or a retried/
    -- duplicate sweep call) -- nothing to do. Keeps this idempotent.
    return jsonb_build_object('ok', false, 'reason', 'not_confirmed');
  end if;

  select name, captain_id into v_home_name, v_home_captain from public.teams where id = m.home_team_id;
  select name, captain_id into v_away_name, v_away_captain from public.teams where id = m.away_team_id;

  insert into public.match_cancellations
    (match_id, home_team_id, home_team_name, away_team_id, away_team_name,
     city, scheduled_at, match_type, cancelled_by_team_id, cancelled_by_user_id, penalized)
  values
    (m.id, m.home_team_id, coalesce(v_home_name, '?'), m.away_team_id, coalesce(v_away_name, '?'),
     m.city, m.scheduled_at, m.match_type,
     case when not p_home_paid then m.home_team_id else m.away_team_id end,
     case when not p_home_paid then v_home_captain else v_away_captain end,
     -- A one-sided failure gets penalized; a mutual no-show punishes neither.
     (p_home_paid <> p_away_paid));

  perform public.issue_match_fee_credits(p_match_id);
  delete from public.matches where id = p_match_id;

  if not p_home_paid and p_away_paid then
    update public.users u set elo = greatest(0, u.elo - 200)
      from public.team_members tm
     where tm.team_id = m.home_team_id and u.id = tm.user_id;
  elsif not p_away_paid and p_home_paid then
    update public.users u set elo = greatest(0, u.elo - 200)
      from public.team_members tm
     where tm.team_id = m.away_team_id and u.id = tm.user_id;
  end if;

  -- Reopen whichever side(s) held up their end. Away never has a single
  -- stored request to reuse, so it always gets a fresh one; home's ORIGINAL
  -- request (m.request_id) just goes back to 'searching'.
  if p_away_paid then
    insert into public.match_requests (team_id, captain_id, city, scheduled_at, match_type, format, status, venue_text)
    values (m.away_team_id, v_away_captain, m.city, m.scheduled_at, m.match_type, m.format, 'searching', m.venue_text)
    returning id into v_new_request_id;

    insert into public.match_request_court_picks (request_id, court_id, rank)
    select v_new_request_id, court_id, rank
    from public.match_request_court_picks where request_id = m.request_id;

    insert into public.notifications (user_id, type, title, body, read, reference_id)
    values (v_away_captain, 'match_cancelled', 'Match cancelled -- fee unpaid',
      coalesce(v_home_name,'Your opponent') || ' didn''t pay their match fee in time, so the match '
      || 'was cancelled. You''re back in the matchmaking pool.',
      false, v_new_request_id);
  end if;

  if p_home_paid then
    update public.match_requests set status = 'searching'
      where id = m.request_id;
    perform public.venue_ensure_request_review(m.request_id);

    insert into public.notifications (user_id, type, title, body, read, reference_id)
    values (v_home_captain, 'match_cancelled', 'Match cancelled -- fee unpaid',
      coalesce(v_away_name,'Your opponent') || ' didn''t pay their match fee in time, so the match '
      || 'was cancelled. You''re back in the matchmaking pool.',
      false, m.request_id);
  end if;

  if not p_home_paid and not p_away_paid then
    -- Neither side paid -- clean restart for both, no penalty either way.
    update public.match_requests set status = 'searching' where id = m.request_id;
    perform public.venue_ensure_request_review(m.request_id);

    insert into public.match_requests (team_id, captain_id, city, scheduled_at, match_type, format, status, venue_text)
    values (m.away_team_id, v_away_captain, m.city, m.scheduled_at, m.match_type, m.format, 'searching', m.venue_text)
    returning id into v_new_request_id;

    insert into public.match_request_court_picks (request_id, court_id, rank)
    select v_new_request_id, court_id, rank
    from public.match_request_court_picks where request_id = m.request_id;

    insert into public.notifications (user_id, type, title, body, read, reference_id)
    values
      (v_home_captain, 'match_cancelled', 'Match cancelled -- fee unpaid',
       'Neither team paid the match fee in time, so the fixture was cancelled. You''re back in the matchmaking pool.',
       false, m.request_id),
      (v_away_captain, 'match_cancelled', 'Match cancelled -- fee unpaid',
       'Neither team paid the match fee in time, so the fixture was cancelled. You''re back in the matchmaking pool.',
       false, v_new_request_id);
  end if;

  return jsonb_build_object('ok', true, 'penalized_team',
    case when not p_home_paid and p_away_paid then m.home_team_id
         when not p_away_paid and p_home_paid then m.away_team_id
         else null end);
end;
$function$;

-- ------------------------------------------------------ client functions
-- The shared rate limiter creates a user's bucket on first use; two calls of
-- the same user arriving at the very same moment can both try to create it.
-- The loser must not fail (the winner has already counted for both).
create or replace function public.venue_rate_ok(p_key text, p_max integer, p_window integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.check_rate_limit(p_key, p_max, p_window);
exception when unique_violation then
  return true;
end $$;

-- The captain who opened the request (home side) may change the venue of a
-- not-yet-started match; the other captain is notified. The reviews and
-- reports of the old text are closed and the new text is reviewed afresh.
create or replace function public.update_match_venue(p_match_id uuid, p_venue_text text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  m          public.matches;
  v_text     text;
  v_home     text;
  v_away_cap uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;

  select * into m from public.matches where id = p_match_id for update;
  if m.id is null then raise exception 'Match not found'; end if;
  if not exists (select 1 from public.teams t
                  where t.id = m.home_team_id and t.captain_id = auth.uid()) then
    raise exception 'Only the captain who opened the request can change the venue';
  end if;
  if m.status not in ('pending', 'confirmed') then
    raise exception 'This match can no longer be changed';
  end if;
  if m.scheduled_at < now() then raise exception 'The match has already started'; end if;

  v_text := public.venue_validate(p_venue_text);
  if v_text is null then raise exception 'bad_venue:length'; end if;
  if m.venue_text is not distinct from v_text then return; end if;

  if not public.venue_rate_ok('venue_edit:' || auth.uid()::text, 10, 3600) then
    raise exception 'rate_limited: too many venue changes, try again later';
  end if;

  update public.matches set venue_text = v_text where id = p_match_id;
  if m.request_id is not null then
    update public.match_requests set venue_text = v_text where id = m.request_id;
  end if;

  -- Same words, different capitalisation: store the new spelling and stop.
  if lower(coalesce(m.venue_text, '')) = lower(v_text) then
    update public.venue_reviews set venue_text = v_text
     where status in ('auto', 'flagged', 'approved')
       and (match_id = p_match_id or (m.request_id is not null and request_id = m.request_id));
    return;
  end if;

  -- The old text is gone: close its reviews and drop the reports about it.
  update public.venue_reviews set status = 'superseded', reviewed_at = now()
   where status in ('auto', 'flagged', 'approved')
     and (match_id = p_match_id or (m.request_id is not null and request_id = m.request_id));
  delete from public.venue_reports
   where match_id = p_match_id or (m.request_id is not null and request_id = m.request_id);
  perform public.venue_record_review(m.request_id, p_match_id, v_text, m.city, auth.uid());

  select name into v_home from public.teams where id = m.home_team_id;
  select captain_id into v_away_cap from public.teams where id = m.away_team_id;
  if v_away_cap is not null then
    insert into public.notifications (user_id, type, title, body, read, reference_id)
    values (v_away_cap, 'court_suggested', 'Venue changed',
      coalesce(v_home, 'The other captain') || ' moved the match to: ' || v_text ||
      '. Call them if you have questions, or cancel the match if it doesn''t work for you.',
      false, p_match_id);
  end if;
end $$;

drop function if exists public.report_venue(uuid, uuid);

-- Any user who is not on the posting team may report a venue name (the
-- posting team's own members cannot). A venue suggested on a proposal can be
-- reported by the captain who received that proposal. The report flags the
-- entry for the admin dashboard.
create or replace function public.report_venue(
  p_request_id  uuid default null,
  p_match_id    uuid default null,
  p_proposal_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid     uuid := auth.uid();
  v_text    text;
  v_req     uuid;
  v_match   uuid;
  v_prop    uuid;
  r         public.match_requests;
  m         public.matches;
  pr        public.match_request_proposals;
  v_review  public.venue_reviews;
  v_reports integer;
  v_rid     uuid;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if (p_request_id is not null)::int + (p_match_id is not null)::int + (p_proposal_id is not null)::int <> 1 then
    raise exception 'Specify either a request, a match or a proposal';
  end if;
  if not public.venue_rate_ok('venue_report:' || v_uid::text, 10, 3600) then
    raise exception 'rate_limited: too many reports, try again later';
  end if;

  -- The row the report points at is locked (FOR KEY SHARE) before anything is
  -- written, in the order every other function uses (match, request,
  -- proposal): a removal that races with the report either waits for it or is
  -- seen by it as "not found", never as a raw foreign-key error or a deadlock.
  if p_request_id is not null then
    select * into r from public.match_requests where id = p_request_id for key share;
    if r.id is null then raise exception 'Request not found'; end if;
    if r.captain_id = v_uid
       or exists (select 1 from public.team_members tm
                   where tm.team_id = r.team_id and tm.user_id = v_uid) then
      raise exception 'You cannot report your own venue';
    end if;
    v_text := r.venue_text;
    v_req  := r.id;
  elsif p_match_id is not null then
    select * into m from public.matches where id = p_match_id for key share;
    if m.id is null then raise exception 'Match not found'; end if;
    if not exists (select 1 from public.team_members tm
                    where tm.user_id = v_uid
                      and tm.team_id in (m.home_team_id, m.away_team_id)) then
      raise exception 'Only match participants can report the venue';
    end if;
    if exists (select 1 from public.team_members tm
                where tm.user_id = v_uid and tm.team_id = m.home_team_id) then
      raise exception 'You cannot report your own venue';
    end if;
    v_text  := m.venue_text;
    v_match := m.id;
    if m.request_id is not null then
      perform 1 from public.match_requests where id = m.request_id for key share;
      if found then v_req := m.request_id; end if;
    end if;
  else
    -- The proposal is locked FOR SHARE so that a report and the accept of the
    -- same proposal are serialized: either the report is filed first (and
    -- moves with the accepted venue) or it sees the proposal already resolved.
    select p.request_id into v_rid from public.match_request_proposals p where p.id = p_proposal_id;
    if v_rid is null then raise exception 'Proposal not found'; end if;
    select * into r from public.match_requests where id = v_rid for key share;
    select * into pr from public.match_request_proposals where id = p_proposal_id for share;
    if pr.id is null then raise exception 'Proposal not found'; end if;
    if r.id is null
       or not exists (select 1 from public.teams t
                       where t.id = r.team_id and t.captain_id = v_uid) then
      raise exception 'Only the captain who received the proposal can report its venue';
    end if;
    if pr.status <> 'pending' then
      raise exception 'This proposal has already been resolved';
    end if;
    v_text := pr.venue_text;
    v_prop := pr.id;
  end if;
  if v_text is null then return; end if;

  insert into public.venue_reports (reporter_id, request_id, match_id, proposal_id, venue_text)
  values (v_uid, v_req, v_match, v_prop, v_text)
  on conflict do nothing;

  select count(distinct rep.reporter_id) into v_reports
    from public.venue_reports rep
   where (v_req   is not null and rep.request_id  = v_req)
      or (v_match is not null and rep.match_id    = v_match)
      or (v_prop  is not null and rep.proposal_id = v_prop);

  select * into v_review
    from public.venue_reviews v
   where v.status <> 'superseded'
     and ((v_req   is not null and v.request_id  = v_req)
       or (v_match is not null and v.match_id    = v_match)
       or (v_prop  is not null and v.proposal_id = v_prop))
   order by v.created_at desc
   limit 1;

  if v_review.id is null then
    insert into public.venue_reviews (request_id, match_id, proposal_id, venue_text, status, reason, created_by)
    values (v_req, v_match, v_prop, v_text, 'flagged', 'reported', v_uid);
  elsif v_review.status = 'auto'
     or (v_review.status = 'approved' and v_reports >= 2) then
    update public.venue_reviews
       set status = 'flagged', reason = 'reported', reviewed_at = null, reviewed_by = null
     where id = v_review.id;
  end if;
end $$;

-- ------------------------------------------------------- admin functions
-- The count is, by construction, the number of rows the list shows.
create or replace function public.admin_flagged_venue_count()
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.users u where u.id = auth.uid() and u.is_admin = true) then
    raise exception 'Admin only';
  end if;
  return (select count(*)::integer from public.admin_list_flagged_venues());
end $$;

-- team_name / captain_name: who typed the text. For a request that is the team
-- that opened it and its captain; for a venue suggested on a proposal it is the
-- proposing team and the user who proposed (target_team_name is then the team
-- that received the proposal). A suggestion that nobody can see any more (the
-- proposal was declined or cancelled, or the request closed) drops out of the
-- list unless somebody reported it.
-- (the result columns changed since the earlier draft: a function cannot change its
-- return type in place, so it is dropped first; on a clean database this does nothing)
drop function if exists public.admin_list_flagged_venues();
create or replace function public.admin_list_flagged_venues()
returns table (
  review_id            uuid,
  request_id           uuid,
  match_id             uuid,
  proposal_id          uuid,
  venue_text           text,
  reason               text,
  city                 text,
  scheduled_at         timestamptz,
  team_name            text,
  captain_name         text,
  target_team_name     text,
  request_status       text,
  report_count         integer,
  suggested_court_id   uuid,
  suggested_court_name text,
  suggested_court_city text,
  match_score          numeric,
  created_at           timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.users u where u.id = auth.uid() and u.is_admin = true) then
    raise exception 'Admin only';
  end if;
  return query
    select v.id, v.request_id, v.match_id, v.proposal_id, v.venue_text, v.reason,
           coalesce(mt.city, r.city, rq.city),
           coalesce(mt.scheduled_at, r.scheduled_at, rq.scheduled_at),
           t.name, cu.name, tt.name,
           coalesce(r.status, rq.status),
           (select count(distinct rep.reporter_id)::integer
              from public.venue_reports rep
             where (rep.request_id  is not null and rep.request_id  = v.request_id)
                or (rep.match_id    is not null and rep.match_id    = v.match_id)
                or (rep.proposal_id is not null and rep.proposal_id = v.proposal_id)),
           v.matched_court_id, c.name, c.city, v.match_score, v.created_at
      from public.venue_reviews v
      left join public.match_requests r          on r.id  = v.request_id
      left join public.matches mt                on mt.id = v.match_id
      left join public.match_request_proposals p on p.id  = v.proposal_id
      left join public.match_requests rq         on rq.id = p.request_id
      left join public.teams t  on t.id = case when p.id is not null then p.proposing_team_id
                                               else coalesce(mt.home_team_id, r.team_id) end
      left join public.users cu on cu.id = case when p.id is not null then p.proposing_user_id
                                                else t.captain_id end
      left join public.teams tt on tt.id = case when p.id is not null then rq.team_id else null end
      left join public.courts c on c.id = v.matched_court_id
     where v.status = 'flagged'
       and (v.proposal_id is null
            or v.match_id is not null
            or v.reason = 'reported'
            or exists (select 1 from public.venue_reports rp where rp.proposal_id = v.proposal_id)
            or (p.status = 'pending' and rq.status = 'searching'))
     order by v.created_at desc;
end $$;

-- p_action: 'approve' | 'link' (needs p_court_id) | 'remove'
create or replace function public.admin_review_venue(
  p_review_id uuid,
  p_action    text,
  p_court_id  uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v      public.venue_reviews;
  r      public.match_requests;
  pr     public.match_request_proposals;
  v_pid  uuid;
  v_cap  uuid;
  v_city text;
  v_mid  uuid;
  v_mid0 uuid;
  v_rid0 uuid;
  v_rid1 uuid;
begin
  if not exists (select 1 from public.users u where u.id = auth.uid() and u.is_admin = true) then
    raise exception 'Admin only';
  end if;
  if p_action is null or p_action not in ('approve', 'link', 'remove') then
    raise exception 'Unknown action: %', p_action;
  end if;

  -- Rows are locked in the order every other function uses: the match, then
  -- the request, then the proposal, and the review last. A captain accepting,
  -- cancelling or editing and an admin reviewing the same venue can then never
  -- wait for each other.
  select vr.match_id, vr.request_id, vr.proposal_id into v_mid0, v_rid0, v_pid
    from public.venue_reviews vr where vr.id = p_review_id;
  v_rid1 := v_rid0;
  if v_rid1 is null and v_pid is not null then
    select p.request_id into v_rid1 from public.match_request_proposals p where p.id = v_pid;
  end if;
  if v_mid0 is not null or v_rid1 is not null then
    perform 1 from public.matches mm
     where mm.id = v_mid0 or (v_rid1 is not null and mm.request_id = v_rid1)
     order by mm.id for update;
  end if;
  if v_rid1 is not null then
    perform 1 from public.match_requests where id = v_rid1 for update;
  end if;
  if v_pid is not null then
    perform 1 from public.match_request_proposals where id = v_pid for update;
  end if;

  select * into v from public.venue_reviews where id = p_review_id for update;
  if v.id is null then raise exception 'Review not found'; end if;
  -- If the suggestion was accepted between the first look and the locks above,
  -- the review now belongs to a match we did not lock: start over.
  if v.match_id is distinct from v_mid0 or v.request_id is distinct from v_rid0
     or v.proposal_id is distinct from v_pid then
    raise exception 'The venue name was changed in the meantime. Refresh the list.';
  end if;

  -- A review of a text the captain has since replaced must never touch the
  -- new text; a repeated tap on the same action is a no-op.
  if v.status = 'superseded' then
    raise exception 'The venue name was changed in the meantime. Refresh the list.';
  end if;
  if v.status = 'removed' then
    if p_action = 'remove' then return; end if;
    raise exception 'This venue name was already removed';
  end if;
  if v.status = 'approved' and p_action = 'approve' then return; end if;

  if p_action = 'approve' then
    update public.venue_reviews
       set status = 'approved', reviewed_at = now(), reviewed_by = auth.uid()
     where id = v.id;

  elsif p_action = 'link' then
    if p_court_id is null or not exists (select 1 from public.courts where id = p_court_id) then
      raise exception 'Choose a court to link';
    end if;
    update public.venue_reviews
       set status = 'approved', matched_court_id = p_court_id,
           reviewed_at = now(), reviewed_by = auth.uid()
     where id = v.id;

  else -- remove
    if v.match_id is not null then
      select t.captain_id, mt.city into v_cap, v_city
        from public.matches mt join public.teams t on t.id = mt.home_team_id
       where mt.id = v.match_id;
      update public.matches set venue_text = null where id = v.match_id;
      if v.request_id is not null then
        update public.match_requests set venue_text = null where id = v.request_id;
      end if;
      update public.venue_reviews
         set status = 'removed', reviewed_at = now(), reviewed_by = auth.uid()
       where id = v.id;
      if v_cap is not null then
        insert into public.notifications (user_id, type, title, body, read, reference_id)
        values (v_cap, 'court_suggested', 'Venue removed',
          'The venue name for your ' || coalesce(v_city, '') ||
          ' match was removed. Please enter the venue''s real name in the match details.',
          false, v.match_id);
      end if;

    elsif v.request_id is not null then
      select * into r from public.match_requests where id = v.request_id;
      if r.id is not null then
        if r.status = 'searching' then
          -- Open request: delete it (proposals and reviews cascade), tell the captain.
          delete from public.match_requests where id = r.id;
          insert into public.notifications (user_id, type, title, body, read, reference_id)
          values (r.captain_id, 'match_cancelled', 'Match request removed',
            'Your match request in ' || r.city || ' was removed because the venue name could not be accepted. Please post a new request with the venue''s real name.',
            false, r.id);
        else
          -- Already matched: keep the match, clear the name, ask for the real one.
          -- Match-detail notifications must point at the match, not the request.
          select mt.id into v_mid
            from public.matches mt
           where mt.request_id = r.id and mt.status in ('pending', 'confirmed')
           order by mt.created_at desc
           limit 1;
          update public.match_requests set venue_text = null where id = r.id;
          update public.matches set venue_text = null
           where request_id = r.id and status <> 'completed';
          update public.venue_reviews
             set status = 'removed', reviewed_at = now(), reviewed_by = auth.uid()
           where id = v.id;
          if v_mid is not null then
            insert into public.notifications (user_id, type, title, body, read, reference_id)
            values (r.captain_id, 'court_suggested', 'Venue removed',
              'The venue name for your ' || r.city || ' match was removed. Please enter the venue''s real name in the match details.',
              false, v_mid);
          end if;
        end if;
      end if;

    elsif v.proposal_id is not null then
      -- A venue suggested on a proposal that has not been accepted: cancel the
      -- proposal (the team can send a new one with the real name) and tell the
      -- team that made it.
      select * into pr from public.match_request_proposals where id = v.proposal_id;
      if pr.id is not null and pr.status = 'pending' then
        update public.match_request_proposals
           set status = 'cancelled', resolved_at = now()
         where id = pr.id;
        insert into public.notifications (user_id, type, title, body, read, reference_id)
        values (pr.proposing_user_id, 'match_proposal_declined', 'Proposal removed',
          'Your proposal was removed because the venue name could not be accepted. You can send a new one with the venue''s real name.',
          false, pr.request_id);
      end if;
      update public.venue_reviews
         set status = 'removed', reviewed_at = now(), reviewed_by = auth.uid()
       where id = v.id;
    end if;
  end if;
end $$;

-- ----------------------------------------------------------------- grants
revoke all on function public.venue_clean(text)                                  from public, anon, authenticated;
revoke all on function public.venue_norm(text)                                   from public, anon, authenticated;
revoke all on function public.venue_core(text)                                   from public, anon, authenticated;
revoke all on function public.venue_blocked_reason(text)                         from public, anon, authenticated;
revoke all on function public.venue_validate(text)                               from public, anon, authenticated;
revoke all on function public.venue_best_match(text, text)                       from public, anon, authenticated;
revoke all on function public.venue_record_review(uuid, uuid, text, text, uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.venue_ensure_request_review(uuid)                  from public, anon, authenticated;
revoke all on function public.trg_request_venue_validate()                       from public, anon, authenticated;
revoke all on function public.trg_request_venue_review()                         from public, anon, authenticated;
revoke all on function public.enforce_match_request_daily_limit()                from public, anon, authenticated;
revoke all on function public.venue_rate_ok(text, integer, integer)               from public, anon, authenticated;

revoke all on function public.update_match_venue(uuid, text)                     from public, anon;
revoke all on function public.report_venue(uuid, uuid, uuid)                           from public, anon;
revoke all on function public.admin_flagged_venue_count()                        from public, anon;
revoke all on function public.admin_list_flagged_venues()                        from public, anon;
revoke all on function public.admin_review_venue(uuid, text, uuid)               from public, anon;
grant execute on function public.update_match_venue(uuid, text)                  to authenticated;
grant execute on function public.report_venue(uuid, uuid, uuid)                        to authenticated;
grant execute on function public.admin_flagged_venue_count()                     to authenticated;
grant execute on function public.admin_list_flagged_venues()                     to authenticated;
grant execute on function public.admin_review_venue(uuid, text, uuid)            to authenticated;

-- Same grants the original functions had (signed-in users and the service role).
revoke all on function public.propose_match(uuid, uuid, text)                       from public, anon;
revoke all on function public.propose_match_with_roster(uuid, uuid, uuid[], text)   from public, anon;
grant execute on function public.propose_match(uuid, uuid, text)                     to authenticated, service_role;
grant execute on function public.propose_match_with_roster(uuid, uuid, uuid[], text) to authenticated, service_role;

notify pgrst, 'reload schema';
