-- A dedicated, read-only database login for Mission Control's agents.
--
-- The agents used to read the live database through the owner's Supabase
-- account token (which can change anything in the whole Supabase account).
-- Now they log in as `mission_control_ro`, which can only SELECT:
--   * schema agent_read: copies of the app tables WITHOUT personal data
--     (no names, usernames, phones, emails, birth dates, photos, free text);
--   * Mission Control's own bookkeeping tables;
--   * the system catalog (table/column/policy definitions) for engineering work.
-- Its search_path starts with agent_read, so `select ... from users` reads the
-- safe copy. The password is set separately (never stored in git).

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'mission_control_ro') then
    create role mission_control_ro login noinherit;
  end if;
end $$;

alter role mission_control_ro set search_path = agent_read, public, pg_catalog;
alter role mission_control_ro set default_transaction_read_only = on;
alter role mission_control_ro set statement_timeout = '15s';
alter role mission_control_ro connection limit 5;

create schema if not exists agent_read;
revoke all on schema agent_read from public;

create or replace view agent_read.users as
  select id, city, position, elo, reliability, behavior_positive, behavior_negative,
         matches_played, dispute_count, flagged, created_at, pwr_assessment_completed_at
    from public.users;
create or replace view agent_read.teams as
  select id, city, captain_id, rating, wins, losses, draws, created_at, disbanded_at
    from public.teams;
create or replace view agent_read.team_members as
  select team_id, user_id, role, joined_at from public.team_members;
create or replace view agent_read.matches as
  select id, request_id, home_team_id, away_team_id, city, scheduled_at, match_type,
         format, status, home_score, away_score, score_disputed, dispute_rounds,
         cancel_reason, confirmed_at, created_at, venue_text, venue_source
    from public.matches;
create or replace view agent_read.match_requests as
  select id, team_id, city, scheduled_at, match_type, format, status, created_at, venue_text
    from public.match_requests;
create or replace view agent_read.match_request_proposals as
  select id, request_id, proposing_team_id, status, created_at, resolved_at
    from public.match_request_proposals;
create or replace view agent_read.match_players as
  select match_id, team_id, user_id, attended from public.match_players;
create or replace view agent_read.behavior_reports as
  select id, match_id, target_user_id, rating, created_at from public.behavior_reports;
create or replace view agent_read.notifications as
  select id, user_id, type, read, created_at from public.notifications;
create or replace view agent_read.match_cancellations as
  select match_id, city, scheduled_at, match_type, cancelled_by_team_id, penalized, created_at
    from public.match_cancellations;
create or replace view agent_read.courts as
  select id, name, city, active, created_at from public.courts;
create or replace view agent_read.push_send_log as
  select ok, http_status, created_at from public.push_send_log;
create or replace view agent_read.security_alerts as
  select source, severity, created_at from public.security_alerts;

grant usage on schema agent_read to mission_control_ro;
grant select on all tables in schema agent_read to mission_control_ro;

-- Mission Control's own tables (no app user data), and the catalog.
grant usage on schema public to mission_control_ro;
do $$
declare t text;
begin
  foreach t in array array['activity_log', 'agent_memory', 'agent_evals', 'agent_locks',
                           'suggestions', 'usage_log', 'approvals', 'content_drafts'] loop
    if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = t) then
      execute format('grant select on public.%I to mission_control_ro', t);
    end if;
  end loop;
end $$;

-- Nothing else: no app tables, no auth, no storage, no vault.
revoke all on schema auth, storage, vault from mission_control_ro;
