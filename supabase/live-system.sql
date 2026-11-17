-- Whisper live system — rooms, speakers, and listener presence
-- Apply manually via the Supabase SQL Editor (runMigration is not available).
-- NOTE: PostgreSQL does NOT support `CREATE POLICY IF NOT EXISTS`. Policies
-- below are created inside `DO $$` blocks that skip them when they already exist.

-- Live rooms / Spaces (audio-only broadcast rooms)
CREATE TABLE IF NOT EXISTS whisper_live_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  topic TEXT,
  host_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  is_live BOOLEAN NOT NULL DEFAULT true,
  is_video_enabled BOOLEAN NOT NULL DEFAULT true,
  listener_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Speakers in a room (host + co-hosts + invited speakers)
CREATE TABLE IF NOT EXISTS whisper_live_room_speakers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES whisper_live_rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  is_host BOOLEAN NOT NULL DEFAULT false,
  is_cohost BOOLEAN NOT NULL DEFAULT false,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(room_id, user_id)
);

-- Listener presence for real-time counts
CREATE TABLE IF NOT EXISTS whisper_live_room_listeners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES whisper_live_rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(room_id, user_id)
);

-- RLS: anon can read live rooms; only hosts can update their rooms; auth users can join listeners
ALTER TABLE whisper_live_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE whisper_live_room_speakers ENABLE ROW LEVEL SECURITY;
ALTER TABLE whisper_live_room_listeners ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_rooms' AND policyname = 'whisper_live_rooms_select') THEN
    CREATE POLICY whisper_live_rooms_select ON whisper_live_rooms FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_rooms' AND policyname = 'whisper_live_rooms_insert') THEN
    CREATE POLICY whisper_live_rooms_insert ON whisper_live_rooms FOR INSERT WITH CHECK (auth.uid() = host_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_rooms' AND policyname = 'whisper_live_rooms_update') THEN
    CREATE POLICY whisper_live_rooms_update ON whisper_live_rooms FOR UPDATE USING (auth.uid() = host_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_rooms' AND policyname = 'whisper_live_rooms_delete') THEN
    CREATE POLICY whisper_live_rooms_delete ON whisper_live_rooms FOR DELETE USING (auth.uid() = host_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_room_speakers' AND policyname = 'whisper_live_room_speakers_select') THEN
    CREATE POLICY whisper_live_room_speakers_select ON whisper_live_room_speakers FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_room_speakers' AND policyname = 'whisper_live_room_speakers_insert') THEN
    CREATE POLICY whisper_live_room_speakers_insert ON whisper_live_room_speakers FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_room_speakers' AND policyname = 'whisper_live_room_speakers_delete') THEN
    CREATE POLICY whisper_live_room_speakers_delete ON whisper_live_room_speakers FOR DELETE USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_room_listeners' AND policyname = 'whisper_live_room_listeners_select') THEN
    CREATE POLICY whisper_live_room_listeners_select ON whisper_live_room_listeners FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_room_listeners' AND policyname = 'whisper_live_room_listeners_insert') THEN
    CREATE POLICY whisper_live_room_listeners_insert ON whisper_live_room_listeners FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_room_listeners' AND policyname = 'whisper_live_room_listeners_delete') THEN
    CREATE POLICY whisper_live_room_listeners_delete ON whisper_live_room_listeners FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

-- Indexes for the live queries
CREATE INDEX IF NOT EXISTS idx_live_rooms_is_live ON whisper_live_rooms(is_live, listener_count DESC);
CREATE INDEX IF NOT EXISTS idx_live_room_speakers_room ON whisper_live_room_speakers(room_id);
CREATE INDEX IF NOT EXISTS idx_live_room_listeners_room ON whisper_live_room_listeners(room_id);
