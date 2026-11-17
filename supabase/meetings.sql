-- ============================================================================
-- Whisper Meetings — private video meetings with AI-generated notes.
-- Reuses the live-room WebRTC engine (signaling channel `live-signal:meeting:{id}`).
-- After the call ends, per-participant speech transcripts are summarized into
-- meeting notes (key points, decisions, action items) — like Gemini notes.
--
-- Run once in the Supabase SQL editor — safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.whisper_meetings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  host_username text NOT NULL DEFAULT '',
  title text NOT NULL DEFAULT 'Meeting',
  status text NOT NULL DEFAULT 'live' CHECK (status IN ('scheduled','live','ended')),
  scheduled_at timestamptz,
  started_at timestamptz,
  ended_at timestamptz,
  -- Email invites: who was invited by email (for guest tracking).
  invited_emails text[] DEFAULT '{}',
  -- AI-generated notes (markdown) + generation stamp.
  summary text,
  summary_generated_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS whisper_meetings_host_idx
  ON public.whisper_meetings (host_id, created_at DESC);
CREATE INDEX IF NOT EXISTS whisper_meetings_status_idx
  ON public.whisper_meetings (status, created_at DESC);

-- Participants — who joined (for notes delivery + "my meetings" lists).
CREATE TABLE IF NOT EXISTS public.whisper_meeting_participants (
  meeting_id uuid NOT NULL REFERENCES public.whisper_meetings(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  username text NOT NULL DEFAULT '',
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (meeting_id, user_id)
);

CREATE INDEX IF NOT EXISTS whisper_meeting_participants_user_idx
  ON public.whisper_meeting_participants (user_id, joined_at DESC);

-- Transcript segments — each client records ITS OWN speech locally
-- (SpeechRecognition on web, SFSpeechRecognizer on iOS) and inserts finished
-- utterances here. The summary generator reads them back in order.
CREATE TABLE IF NOT EXISTS public.whisper_meeting_transcripts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id uuid NOT NULL REFERENCES public.whisper_meetings(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  username text NOT NULL DEFAULT '',
  text text NOT NULL,
  spoken_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS whisper_meeting_transcripts_meeting_idx
  ON public.whisper_meeting_transcripts (meeting_id, spoken_at);

-- ─── ALTER: make started_at nullable if the original constraint was NOT NULL ──
-- The original meetings.sql shipped with `started_at timestamptz NOT NULL DEFAULT now()`
-- which broke scheduled meetings (started_at must be null until the host joins).
-- This is safe to re-run: it only drops the NOT NULL if present.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'whisper_meetings'
      AND column_name = 'started_at'
      AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE public.whisper_meetings ALTER COLUMN started_at DROP NOT NULL;
  END IF;
END $$;

-- Add invited_emails column if it doesn't exist yet.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'whisper_meetings'
      AND column_name = 'invited_emails'
  ) THEN
    ALTER TABLE public.whisper_meetings ADD COLUMN invited_emails text[] DEFAULT '{}';
  END IF;
END $$;

-- RLS ------------------------------------------------------------------------
ALTER TABLE public.whisper_meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whisper_meeting_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whisper_meeting_transcripts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Meetings: any signed-in user can read by id (join-by-link), host manages.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_meetings' AND policyname = 'wm_select') THEN
    CREATE POLICY wm_select ON public.whisper_meetings FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_meetings' AND policyname = 'wm_insert') THEN
    CREATE POLICY wm_insert ON public.whisper_meetings FOR INSERT TO authenticated WITH CHECK (auth.uid() = host_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_meetings' AND policyname = 'wm_update') THEN
    CREATE POLICY wm_update ON public.whisper_meetings FOR UPDATE TO authenticated USING (auth.uid() = host_id) WITH CHECK (auth.uid() = host_id);
  END IF;

  -- Participants: read for anyone in the meeting, self-insert.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_meeting_participants' AND policyname = 'wmp_select') THEN
    CREATE POLICY wmp_select ON public.whisper_meeting_participants FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_meeting_participants' AND policyname = 'wmp_insert') THEN
    CREATE POLICY wmp_insert ON public.whisper_meeting_participants FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
  END IF;

  -- Transcripts: participants read; each user inserts only their own speech.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_meeting_transcripts' AND policyname = 'wmt_select') THEN
    CREATE POLICY wmt_select ON public.whisper_meeting_transcripts FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_meeting_transcripts' AND policyname = 'wmt_insert') THEN
    CREATE POLICY wmt_insert ON public.whisper_meeting_transcripts FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;
