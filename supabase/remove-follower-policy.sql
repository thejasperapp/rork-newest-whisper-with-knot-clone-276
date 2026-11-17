-- Remove follower support ----------------------------------------------------
-- The iOS follower list now offers "Remove follower" (long-press a row on
-- your own Followers tab). That deletes the whisper_follows row where YOU
-- are the followee. Existing policies only let the follower delete their
-- own edge, so RLS silently blocks the removal (0 rows affected).
--
-- Run this once in the Supabase SQL editor. Permissive policies OR
-- together, so this simply adds the followee-side delete right without
-- touching the existing unfollow policy.

drop policy if exists "whisper_follows_followee_can_remove" on public.whisper_follows;
create policy "whisper_follows_followee_can_remove"
  on public.whisper_follows
  for delete
  using (auth.uid() = followee_id);
