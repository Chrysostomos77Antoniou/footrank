-- #9: confirm_match_score is unreachable in practice -- submit_match_score
-- always sets home_score/away_score together with both *_confirmed flags
-- (either on mutual agreement or after the 2-round dispute auto-resolve), so
-- confirm_match_score's guard (home_score/away_score is null) never passes
-- with anything left to confirm. It also had no caller anywhere in the
-- Flutter client. Dropping it removes an unused, easy-to-misread RPC rather
-- than leaving dead surface area around.
drop function if exists public.confirm_match_score(uuid);
