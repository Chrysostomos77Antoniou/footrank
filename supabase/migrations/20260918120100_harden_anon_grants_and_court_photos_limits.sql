-- #2: match_payment_summary doesn't need to be callable while logged out;
-- it already fails closed for anon (auth.uid() is null -> "not a participant"),
-- but there's no legitimate anon use case, so revoke as defense-in-depth.
revoke execute on function public.match_payment_summary(uuid) from public;
revoke execute on function public.match_payment_summary(uuid) from anon;

-- #6: court-photos had no file_size_limit/allowed_mime_types, unlike avatars.
-- Writes are already admin-only via storage RLS, but this closes the gap so
-- an admin session (or a script hitting the REST API directly) can't push an
-- arbitrarily large or non-image file into a public bucket.
update storage.buckets
set file_size_limit = 5242880, -- 5MB
    allowed_mime_types = array['image/jpeg','image/png','image/webp']
where id = 'court-photos';
