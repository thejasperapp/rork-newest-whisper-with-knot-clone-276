-- Live room polls + auto-end trigger + left_at column
-- Apply manually via the Supabase SQL Editor (runMigration is not available).
-- NOTE: PostgreSQL does NOT support `CREATE POLICY IF NOT EXISTS`. Policies
-- below are created inside `DO $$` blocks that skip them when they already exist.

-- ─── Chat polls ──────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS whisper_live_chat_polls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES whisper_live_rooms(id) ON DELETE CASCADE,
  question TEXT NOT NULL,
  options JSONB NOT NULL, -- array of strings: ["Option A", "Option B", ...]
  creator_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  creator_username TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS whisper_live_chat_poll_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id UUID NOT NULL REFERENCES whisper_live_chat_polls(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  option_index INTEGER NOT NULL,
  voted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(poll_id, user_id)
);

ALTER TABLE whisper_live_chat_polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE whisper_live_chat_poll_votes ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Polls: anyone can read, any auth user in the room can create, creator can close
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_chat_polls' AND policyname = 'live_polls_select') THEN
    CREATE POLICY live_polls_select ON whisper_live_chat_polls FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_chat_polls' AND policyname = 'live_polls_insert') THEN
    CREATE POLICY live_polls_insert ON whisper_live_chat_polls FOR INSERT WITH CHECK (auth.uid() = creator_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_chat_polls' AND policyname = 'live_polls_update') THEN
    CREATE POLICY live_polls_update ON whisper_live_chat_polls FOR UPDATE USING (auth.uid() = creator_id);
  END IF;

  -- Votes: anyone can read, auth user can vote once (unique constraint enforces)
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_chat_poll_votes' AND policyname = 'live_poll_votes_select') THEN
    CREATE POLICY live_poll_votes_select ON whisper_live_chat_poll_votes FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_chat_poll_votes' AND policyname = 'live_poll_votes_insert') THEN
    CREATE POLICY live_poll_votes_insert ON whisper_live_chat_poll_votes FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_chat_poll_votes' AND policyname = 'live_poll_votes_delete') THEN
    CREATE POLICY live_poll_votes_delete ON whisper_live_chat_poll_votes FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_live_polls_room ON whisper_live_chat_polls(room_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_live_poll_votes_poll ON whisper_live_chat_poll_votes(poll_id);

-- Add polls + votes to realtime publication
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'whisper_live_chat_polls'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE whisper_live_chat_polls;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'whisper_live_chat_poll_votes'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE whisper_live_chat_poll_votes;
  END IF;
END $$;

-- ─── Auto-end when all speakers leave ────────────────────────────────────────

-- Track when a speaker left (for group auto-end logic)
ALTER TABLE whisper_live_room_speakers
  ADD COLUMN IF NOT EXISTS left_at TIMESTAMPTZ;

-- SECURITY DEFINER function that flips is_live=false when no speakers remain.
-- Must be SECURITY DEFINER because the room's RLS only allows the host to UPDATE,
-- but any speaker can DELETE their own row.
CREATE OR REPLACE FUNCTION public.whisper_live_auto_end()
RETURNS TRIGGER AS $$
DECLARE
  remaining_count INTEGER;
BEGIN
  -- Count remaining speakers for this room (excluding the one who just left)
  SELECT COUNT(*) INTO remaining_count
  FROM whisper_live_room_speakers
  WHERE room_id = OLD.room_id;

  -- If no speakers remain, end the room
  IF remaining_count = 0 THEN
    UPDATE whisper_live_rooms
    SET is_live = false, updated_at = now()
    WHERE id = OLD.room_id AND is_live = true;
  END IF;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS whisper_live_auto_end_trg ON whisper_live_room_speakers;
CREATE TRIGGER whisper_live_auto_end_trg
  AFTER DELETE ON whisper_live_room_speakers
  FOR EACH ROW
  EXECUTE FUNCTION public.whisper_live_auto_end();
