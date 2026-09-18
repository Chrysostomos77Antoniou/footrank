-- #3: delete_my_account() used to DELETE FROM auth.users directly, bypassing
-- GoTrue's own account-deletion path (session/refresh-token cleanup, MFA
-- factor removal, deleted-user webhooks). It now only cleans up public-schema
-- data; the actual auth.users removal is done by the new delete-account Edge
-- Function via supabase.auth.admin.deleteUser(), which is the supported way
-- to delete a user through GoTrue.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_phone text;
  v_u public.users;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  select email into v_email from auth.users where id = v_uid;
  select phone into v_phone from public.user_contacts where user_id = v_uid;
  select * into v_u from public.users where id = v_uid;

  -- Remember the competitive record against a hash of the identity, so the
  -- same person can't launder a penalty by re-registering.
  if v_u.id is not null then
    insert into public.account_tombstones (
      email_hash, phone_hash, elo, reliability, dispute_count, flagged,
      behavior_positive, behavior_negative, matches_played)
    values (
      public.identity_hash(public.normalize_email(v_email)),
      public.identity_hash(public.normalize_phone(v_phone)),
      v_u.elo, v_u.reliability, v_u.dispute_count, v_u.flagged,
      v_u.behavior_positive, v_u.behavior_negative, v_u.matches_played);
  end if;

  -- Soft-disband (not delete) any team this user captains, so the team's
  -- match history and the opponents' win/loss records survive intact.
  update public.teams set disbanded_at = now() where captain_id = v_uid and disbanded_at is null;

  -- Clear NO ACTION references so the user row can be removed.
  update public.matches set score_proposed_by = null where score_proposed_by = v_uid;
  update public.match_players set marked_by = null where marked_by = v_uid;
  -- Deleting the profile no longer cascades teams they captain (soft-disbanded
  -- above); memberships, requests, notifications, invites for this user still cascade.
  delete from public.users where id = v_uid;

  -- auth.users is intentionally NOT deleted here anymore -- the calling
  -- delete-account Edge Function does that via the Auth Admin API after this
  -- RPC returns successfully, so GoTrue's own revocation logic runs too.
end;
$function$;
