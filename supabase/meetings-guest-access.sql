-- Guest access for Whisper Meetings — apply in the Supabase SQL Editor.
--
-- Meeting links are unguessable UUIDs, and invite emails promise "join as a
-- guest". This grants ANON (signed-out) visitors read access to the meeting
-- row itself so the /meet/{id} page can load the title, status, and the
-- post-meeting AI notes. Everything else stays account-only:
--   * participants  — guests are never written to whisper_meeting_participants
--   * transcripts   — INSERT/SELECT remain authenticated-only
--   * host controls — start/end remain host-only via existing policies
--
-- Live audio/video runs over the realtime signaling channel, which the anon
-- key can already use; this file only unlocks the meeting metadata read.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'whisper_meetings'
      AND policyname = 'wm_select_anon'
  ) THEN
    CREATE POLICY wm_select_anon
      ON public.whisper_meetings
      FOR SELECT
      TO anon
      USING (true);
  END IF;
END $$;
