-- Undo 20261102150000_app_update_prompt.sql (kept outside migrations/*.sql so it never runs by itself).
begin;
drop function if exists public.admin_set_app_update_prompt(boolean, text);
drop table if exists public.app_update_prompt;
commit;
