-- Consolidated live system fix — apply manually via the Supabase SQL Editor.
-- This ensures all columns exist even if the original tables were created
-- before is_video_enabled or updated_at were added.
-- NOTE: PostgreSQL does NOT support `CREATE POLICY IF NOT EXISTS`. Policies
-- below are created inside `DO $$` blocks that skip them when they already exist.

-- Ensure is_video_enabled column exists on whisper_live_rooms
ALTER TABLE whisper_live_rooms
  ADD COLUMN IF NOT EXISTS is_video_enabled BOOLEAN NOT NULL DEFAULT true;

-- Ensure updated_at column exists on whisper_live_rooms
ALTER TABLE whisper_live_rooms
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Ensure can_video column exists on whisper_live_room_speakers
ALTER TABLE whisper_live_room_speakers
  ADD COLUMN IF NOT EXISTS can_video BOOLEAN NOT NULL DEFAULT false;

-- Auto-update updated_at on room changes
CREATE OR REPLACE FUNCTION whisper_live_rooms_touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS whisper_live_rooms_updated_at_trg ON whisper_live_rooms;
CREATE TRIGGER whisper_live_rooms_updated_at_trg
  BEFORE UPDATE ON whisper_live_rooms
  FOR EACH ROW
  EXECUTE FUNCTION whisper_live_rooms_touch_updated_at();

-- Ensure all tables exist (safe to re-run)
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

CREATE TABLE IF NOT EXISTS whisper_live_room_speakers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES whisper_live_rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  is_host BOOLEAN NOT NULL DEFAULT false,
  is_cohost BOOLEAN NOT NULL DEFAULT false,
  can_video BOOLEAN NOT NULL DEFAULT false,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(room_id, user_id)
);

CREATE TABLE IF NOT EXISTS whisper_live_room_listeners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES whisper_live_rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(room_id, user_id)
);

CREATE TABLE IF NOT EXISTS whisper_live_speaker_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES whisper_live_rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  desired_role TEXT NOT NULL,
  answers JSONB NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'pending',
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  UNIQUE(room_id, user_id)
);

-- RLS
ALTER TABLE whisper_live_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE whisper_live_room_speakers ENABLE ROW LEVEL SECURITY;
ALTER TABLE whisper_live_room_listeners ENABLE ROW LEVEL SECURITY;
ALTER TABLE whisper_live_speaker_requests ENABLE ROW LEVEL SECURITY;

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

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_speaker_requests' AND policyname = 'live_speaker_requests_select') THEN
    CREATE POLICY live_speaker_requests_select ON whisper_live_speaker_requests FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_speaker_requests' AND policyname = 'live_speaker_requests_insert') THEN
    CREATE POLICY live_speaker_requests_insert ON whisper_live_speaker_requests FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_speaker_requests' AND policyname = 'live_speaker_requests_update') THEN
    CREATE POLICY live_speaker_requests_update ON whisper_live_speaker_requests FOR UPDATE USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_speaker_requests' AND policyname = 'live_speaker_requests_delete') THEN
    CREATE POLICY live_speaker_requests_delete ON whisper_live_speaker_requests FOR DELETE USING (auth.uid() = user_id OR auth.uid() IN (SELECT host_id FROM whisper_live_rooms WHERE id = whisper_live_speaker_requests.room_id));
  END IF;
END $$;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_live_rooms_is_live ON whisper_live_rooms(is_live, listener_count DESC);
CREATE INDEX IF NOT EXISTS idx_live_room_speakers_room ON whisper_live_room_speakers(room_id);
CREATE INDEX IF NOT EXISTS idx_live_room_listeners_room ON whisper_live_room_listeners(room_id);
CREATE INDEX IF NOT EXISTS idx_live_speaker_requests_room ON whisper_live_speaker_requests(room_id);
CREATE INDEX IF NOT EXISTS idx_live_speaker_requests_status ON whisper_live_speaker_requests(room_id, status);
