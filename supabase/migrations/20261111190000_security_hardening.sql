-- Security, privacy and operations hardening (audit of 11 Nov 2026).
-- Safe for app versions already in the field: no column or table the app
-- reads is removed or hidden.

-- ---------------------------------------------------------------------------
-- 1. Payments are gone: stop the leftover fee pushes and payment sweep.
--    (Tables are kept: they are financial records.)
-- ---------------------------------------------------------------------------
update public.app_config set bool_value = false, updated_at = now()
 where key = 'match_fee_enabled';
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job
     where jobname in ('payment-deadline-sweep', 'fee-payment-reminders');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. No service-role key inside the database. Telegram alerts now use the
--    internal push secret (the notify-telegram function accepts it).
-- ---------------------------------------------------------------------------
create or replace function public.send_match_telegram(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_secret text;
begin
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'push_secret' limit 1;
  if v_secret is null then return; end if;
  perform net.http_post(
    url := 'https://yspccychuwvlrjgioqss.supabase.co/functions/v1/notify-telegram',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-internal-secret', v_secret),
    body := jsonb_build_object('match_id', p_match_id, 'kind', 'fixture_confirmed'));
end $$;
revoke all on function public.send_match_telegram(uuid) from public, anon, authenticated;

delete from vault.secrets where name = 'service_role_key';

-- ---------------------------------------------------------------------------
-- 3. Least privilege on tables and functions.
-- ---------------------------------------------------------------------------
-- Signed-out visitors only need the update prompt; RLS stays the gate for the
-- rest, but nothing else should even be grantable to them.
revoke all on all tables in schema public from anon;
grant select on public.app_update_prompt to anon;
alter default privileges in schema public revoke all on tables from anon;

-- Signed-in users never need these.
revoke truncate, references, trigger on all tables in schema public from authenticated;

-- Trigger functions are not API endpoints.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prorettype = 'trigger'::regtype
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;

-- Fixed search_path on the functions the linter flagged; drop debug leftovers.
alter function public.venue_location_check(text, double precision, double precision, text) set search_path = public;
alter function public.trg_venue_location_stamp() set search_path = public;
alter function public.trg_venue_clear_stale_location() set search_path = public;
drop function if exists public.zz_probe();

-- ---------------------------------------------------------------------------
-- 4. Integrity fixes
-- ---------------------------------------------------------------------------
-- Behaviour ratings: the 72-hour edit window can't be stretched by writing
-- created_at from the app.
create or replace function public.trg_behavior_reports_lock_created()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
  else
    new.created_at := old.created_at;
  end if;
  return new;
end $$;
drop trigger if exists trg_behavior_reports_lock_created on public.behavior_reports;
create trigger trg_behavior_reports_lock_created
  before insert or update on public.behavior_reports
  for each row execute function public.trg_behavior_reports_lock_created();
revoke all on function public.trg_behavior_reports_lock_created() from public, anon, authenticated;

-- Google venue coordinates: the 29-day clock can't be reset from the app.
create or replace function public.trg_venue_location_stamp()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if tg_table_name in ('match_requests', 'match_request_proposals') then
      -- Rows the app writes directly: the server owns the timestamp.
      new.venue_location_at :=
        case when new.venue_lat is not null or new.venue_place_id is not null
             then now() else null end;
    elsif (new.venue_lat is not null or new.venue_place_id is not null)
          and new.venue_location_at is null then
      new.venue_location_at := now();
    end if;
  elsif (new.venue_lat is distinct from old.venue_lat
         or new.venue_lng is distinct from old.venue_lng
         or new.venue_place_id is distinct from old.venue_place_id)
        and new.venue_location_at is not distinct from old.venue_location_at then
    new.venue_location_at :=
      case when new.venue_lat is null and new.venue_place_id is null
           then null else now() end;
  end if;
  return new;
end $$;

-- Reminder pushes showed kick-off in UTC; show Cyprus time.
create or replace function public.send_match_reminders()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare m record;
begin
  for m in
    select id, home_team_id, away_team_id, city, scheduled_at
      from public.matches
     where status = 'confirmed'
       and reminder_sent = false
       and scheduled_at between now() and now() + interval '60 minutes'
  loop
    insert into public.notifications(user_id, type, title, body, reference_id)
    select t.captain_id, 'match_reminder', 'Match starting soon',
           'Your match in ' || m.city || ' starts at ' ||
           to_char(m.scheduled_at at time zone 'Asia/Nicosia', 'HH24:MI'), m.id
      from public.teams t
     where t.id in (m.home_team_id, m.away_team_id) and t.captain_id is not null;
    update public.matches set reminder_sent = true where id = m.id;
  end loop;
end $$;
revoke all on function public.send_match_reminders() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Rating farming: the same two teams playing again within 30 days earn
--    less each time (100%, 50%, 25%, then nothing), and repeats are flagged.
-- ---------------------------------------------------------------------------
create or replace function public.repeat_pairing_factor(p_home uuid, p_away uuid, p_match uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare n int;
begin
  select count(*) into n from public.matches m
   where m.id <> p_match and m.status = 'completed'
     and m.scheduled_at > now() - interval '30 days'
     and ((m.home_team_id = p_home and m.away_team_id = p_away)
       or (m.home_team_id = p_away and m.away_team_id = p_home));
  if n >= 2 then
    perform public.log_security_alert('rating', 'warning',
      jsonb_build_object('reason', 'repeat_pairing', 'match_id', p_match,
                         'teams', jsonb_build_array(p_home, p_away), 'previous_30d', n));
  end if;
  return case when n = 0 then 1 when n = 1 then 0.5 when n = 2 then 0.25 else 0 end;
end $$;
revoke all on function public.repeat_pairing_factor(uuid, uuid, uuid) from public, anon, authenticated;

do $$
declare d text; v_old text := 'k := case when new.match_type = ''ranked'' then 40 else 20 end;';
begin
  d := pg_get_functiondef('public.apply_elo_on_completion'::regproc);
  if position('repeat_pairing_factor' in d) = 0 then
    if position(v_old in d) = 0 then
      raise exception 'apply_elo_on_completion changed; anti-collusion patch not applied';
    end if;
    d := replace(d, v_old, v_old ||
      E'\n    -- Same two teams again within 30 days: smaller rating moves.\n' ||
      '    k := round(k * public.repeat_pairing_factor(new.home_team_id, new.away_team_id, new.id));');
    execute d;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Admin audit log: who did what to whom, and who read private data.
-- ---------------------------------------------------------------------------
create table if not exists public.admin_audit (
  id         bigint generated always as identity primary key,
  actor_id   uuid,
  action     text not null,
  details    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.admin_audit enable row level security;
drop policy if exists "admins read audit" on public.admin_audit;
create policy "admins read audit" on public.admin_audit for select to authenticated
  using (exists (select 1 from public.users u where u.id = (select auth.uid()) and u.is_admin));
revoke all on public.admin_audit from anon, authenticated;
grant select on public.admin_audit to authenticated;

create or replace function public.admin_audit_log(p_action text, p_details jsonb)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.admin_audit (actor_id, action, details)
  values (auth.uid(), p_action, coalesce(p_details, '{}'::jsonb));
$$;
revoke all on function public.admin_audit_log(text, jsonb) from public, anon, authenticated;

-- Add a log line to every admin function that reads private data or changes
-- something, right after its BEGIN (a refused non-admin call rolls it back).
do $$
declare f record; d text; v_args text; i int; j int; body_start int;
begin
  for f in
    select p.oid, p.proname, p.proargnames, p.proargmodes, p.pronargs
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('admin_force_cancel_match', 'admin_get_user_contact',
         'admin_get_user_email', 'admin_get_user_private', 'admin_resolve_dispute',
         'admin_review_venue', 'admin_set_app_update_prompt',
         'admin_set_user_moderation', 'admin_upsert_court')
  loop
    d := pg_get_functiondef(f.oid);
    continue when position('admin_audit_log' in d) > 0;
    v_args := '';
    if f.proargnames is not null then
      for i in 1 .. f.pronargs loop
        v_args := v_args || case when v_args = '' then '' else ', ' end ||
          quote_literal(f.proargnames[i]) || ', ' || f.proargnames[i];
      end loop;
    end if;
    v_args := case when v_args = '' then '''{}''::jsonb'
                   else 'jsonb_build_object(' || v_args || ')' end;
    body_start := position('$function$' in d);
    j := position(E'\nbegin' in lower(substr(d, body_start)));
    if j = 0 then raise exception 'no BEGIN found in %', f.proname; end if;
    j := body_start + j - 1 + length(E'\nbegin');
    d := substr(d, 1, j) || E'\n  perform public.admin_audit_log(' ||
         quote_literal(f.proname) || ', ' || v_args || ');' || substr(d, j + 1);
    execute d;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 7. Alerting: failed cron jobs and critical security alerts reach the admin
--    as a push notification. Runs every 30 minutes.
-- ---------------------------------------------------------------------------
create or replace function public.ops_health_check()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v_failed text; v_crit int; v_body text; n int := 0;
begin
  select string_agg(distinct j.jobname, ', ') into v_failed
    from cron.job_run_details r join cron.job j on j.jobid = r.jobid
   where r.status = 'failed' and r.start_time > now() - interval '30 minutes';
  if v_failed is not null then
    perform public.log_security_alert('cron', 'critical',
      jsonb_build_object('reason', 'job_failed', 'jobs', v_failed));
  end if;

  select count(*) into v_crit from public.security_alerts
   where severity = 'critical' and created_at > now() - interval '30 minutes';

  if v_failed is not null or v_crit > 0 then
    v_body := concat_ws(' ',
      case when v_failed is not null then 'Failed jobs: ' || v_failed || '.' end,
      case when v_crit > 0 then v_crit || ' critical security alert(s).' end);
    insert into public.notifications (user_id, type, title, body, read)
    select u.id, 'ops_alert', 'FootRank alert', v_body, false
      from public.users u where u.is_admin;
    get diagnostics n = row_count;
  end if;
  return n;
end $$;
revoke all on function public.ops_health_check() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. Retention: logs are not kept forever.
-- ---------------------------------------------------------------------------
create or replace function public.purge_operational_logs()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.push_send_log  where created_at < now() - interval '30 days';
  delete from public.push_debug_log where created_at < now() - interval '30 days';
  delete from public.activity_log   where created_at < now() - interval '90 days';
  delete from public.agent_memory   where created_at < now() - interval '90 days';
  delete from public.security_alerts where created_at < now() - interval '365 days';
  delete from public.notifications  where read and created_at < now() - interval '180 days';
  delete from public.admin_audit    where created_at < now() - interval '2 years';
end $$;
revoke all on function public.purge_operational_logs() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 9. Right of access: a user can download everything stored about them.
-- ---------------------------------------------------------------------------
create or replace function public.export_my_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  return jsonb_build_object(
    'exported_at', now(),
    'account', (select jsonb_build_object('id', au.id, 'email', au.email,
                  'created_at', au.created_at, 'last_sign_in_at', au.last_sign_in_at)
                  from auth.users au where au.id = v_uid),
    'profile', (select to_jsonb(u) from public.users u where u.id = v_uid),
    'phone', (select c.phone from public.user_contacts c where c.user_id = v_uid),
    'date_of_birth', (select b.date_of_birth from public.user_birthdates b where b.user_id = v_uid),
    'consents', (select coalesce(jsonb_agg(to_jsonb(c)), '[]') from public.user_consents c where c.user_id = v_uid),
    'teams', (select coalesce(jsonb_agg(jsonb_build_object('team', t.name, 'role', tm.role,
                  'joined_at', tm.joined_at, 'captain', t.captain_id = v_uid)), '[]')
                from public.team_members tm join public.teams t on t.id = tm.team_id
               where tm.user_id = v_uid),
    'matches_played', (select coalesce(jsonb_agg(jsonb_build_object('match_id', mp.match_id,
                  'attended', mp.attended, 'scheduled_at', m.scheduled_at, 'city', m.city,
                  'home_score', m.home_score, 'away_score', m.away_score)), '[]')
                from public.match_players mp join public.matches m on m.id = mp.match_id
               where mp.user_id = v_uid),
    'behavior_ratings_given', (select coalesce(jsonb_agg(jsonb_build_object('match_id', b.match_id,
                  'rating', b.rating, 'reason', b.reason, 'created_at', b.created_at)), '[]')
                from public.behavior_reports b where b.rater_id = v_uid),
    'behavior_ratings_received', (select coalesce(jsonb_agg(jsonb_build_object('match_id', b.match_id,
                  'rating', b.rating, 'created_at', b.created_at)), '[]')
                from public.behavior_reports b where b.target_user_id = v_uid),
    'skill_assessments', (select coalesce(jsonb_agg(to_jsonb(p) - 'user_id'), '[]')
                from public.pwr_assessments p where p.user_id = v_uid),
    'invitations', (select coalesce(jsonb_agg(to_jsonb(i)), '[]') from public.team_invitations i where i.user_id = v_uid),
    'join_requests', (select coalesce(jsonb_agg(to_jsonb(r)), '[]') from public.team_join_requests r where r.user_id = v_uid),
    'notifications', (select coalesce(jsonb_agg(jsonb_build_object('type', n.type, 'title', n.title,
                  'body', n.body, 'created_at', n.created_at)), '[]')
                from public.notifications n where n.user_id = v_uid),
    'push_devices', (select count(*) from public.fcm_tokens f where f.user_id = v_uid)
  );
end $$;
revoke all on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Performance: index foreign keys, evaluate auth.uid() once per query.
-- ---------------------------------------------------------------------------
do $$
declare r record;
begin
  -- Only where the column exists (the test project's schema lags production).
  for r in select * from (values
    ('match_cancellations_away_team_idx', 'match_cancellations', 'away_team_id'),
    ('match_cancellations_cancelled_by_team_idx', 'match_cancellations', 'cancelled_by_team_id'),
    ('match_cancellations_cancelled_by_user_idx', 'match_cancellations', 'cancelled_by_user_id'),
    ('match_cancellations_home_team_idx', 'match_cancellations', 'home_team_id'),
    ('match_fee_reminders_team_idx', 'match_fee_reminders', 'team_id'),
    ('match_payments_captain_idx', 'match_payments', 'captain_id'),
    ('match_payments_team_idx', 'match_payments', 'team_id'),
    ('match_request_court_picks_court_idx', 'match_request_court_picks', 'court_id'),
    ('match_request_proposals_captain_idx', 'match_request_proposals', 'proposing_captain_id'),
    ('match_request_proposals_team_idx', 'match_request_proposals', 'proposing_team_id'),
    ('matches_suggested_court_idx', 'matches', 'suggested_court_id'),
    ('push_debug_log_user_idx', 'push_debug_log', 'user_id'),
    ('pwr_assessments_user_idx', 'pwr_assessments', 'user_id'),
    ('team_members_user_idx', 'team_members', 'user_id'),
    ('venue_reports_match_idx', 'venue_reports', 'match_id'),
    ('venue_reports_proposal_idx', 'venue_reports', 'proposal_id'),
    ('venue_reports_request_idx', 'venue_reports', 'request_id'),
    ('venue_reviews_matched_court_idx', 'venue_reviews', 'matched_court_id')
  ) v(idx, tbl, col) loop
    if exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = r.tbl and column_name = r.col) then
      execute format('create index if not exists %I on public.%I(%I)', r.idx, r.tbl, r.col);
    end if;
  end loop;
end $$;

do $$
begin
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'push_debug_log' and policyname = 'insert own debug log') then
    execute 'alter policy "insert own debug log" on public.push_debug_log
  with check (user_id = (select auth.uid()))';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'pwr_assessments' and policyname = 'own assessment select') then
    execute 'alter policy "own assessment select" on public.pwr_assessments
  using (user_id = (select auth.uid()))';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'teams' and policyname = 'Captain can update own team') then
    execute 'alter policy "Captain can update own team" on public.teams
  using ((select auth.uid()) = captain_id) with check ((select auth.uid()) = captain_id)';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'match_cancellations' and policyname = 'Admins view match cancellations') then
    execute 'alter policy "Admins view match cancellations" on public.match_cancellations
  using (exists (select 1 from public.users where users.id = (select auth.uid()) and users.is_admin = true))';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'match_request_proposals' and policyname = 'match_request_proposals_select') then
    execute 'alter policy match_request_proposals_select on public.match_request_proposals
  using (exists (select 1 from public.team_members tm
                  where tm.team_id = match_request_proposals.proposing_team_id
                    and tm.user_id = (select auth.uid()))
      or exists (select 1 from public.match_requests mr
                   join public.team_members tm on tm.team_id = mr.team_id
                  where mr.id = match_request_proposals.request_id
                    and tm.user_id = (select auth.uid())))';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 11. Schedules
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job
     where jobname in ('ops-health-check', 'purge-operational-logs');
    perform cron.schedule('ops-health-check', '*/30 * * * *', 'select public.ops_health_check()');
    perform cron.schedule('purge-operational-logs', '40 3 * * *', 'select public.purge_operational_logs()');
  end if;
end $$;
