-- Whisper live speaker requests + video role flag
-- Apply manually via the Supabase SQL Editor.
-- NOTE: PostgreSQL does NOT support `CREATE POLICY IF NOT EXISTS`. Policies
-- below are created inside `DO $$` blocks that skip them when they already exist.

-- Add a `can_video` flag to existing speakers so hosts can decide whether a
-- promoted speaker may also publish their camera.
ALTER TABLE whisper_live_room_speakers
  ADD COLUMN IF NOT EXISTS can_video BOOLEAN NOT NULL DEFAULT false;

-- Speaker requests: any user can ask to speak; host/recruiter accepts/denies.
CREATE TABLE IF NOT EXISTS whisper_live_speaker_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES whisper_live_rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  desired_role TEXT NOT NULL, -- coach | athlete | creator | general
  answers JSONB NOT NULL DEFAULT '{}', -- role-specific questionnaire answers
  status TEXT NOT NULL DEFAULT 'pending', -- pending | accepted | rejected
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  UNIQUE(room_id, user_id)
);

ALTER TABLE whisper_live_speaker_requests ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
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

CREATE INDEX IF NOT EXISTS idx_live_speaker_requests_room ON whisper_live_speaker_requests(room_id);
CREATE INDEX IF NOT EXISTS idx_live_speaker_requests_status ON whisper_live_speaker_requests(room_id, status);
