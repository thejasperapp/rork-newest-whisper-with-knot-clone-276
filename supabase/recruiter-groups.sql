-- Recruiter groups — lets a recruiter define their group identity and group photo
-- used on the interactive globe pins. Apply via the Supabase SQL Editor.
-- NOTE: PostgreSQL does NOT support `CREATE POLICY IF NOT EXISTS`. Policies
-- below are created inside a `DO $$` block that skips them when they already exist.

-- The territory foreign key is optional; if your territories table doesn't exist
-- yet, you can either run the territories migration first or the row will set
-- territory_id to NULL when its referenced territory is deleted.
CREATE TABLE IF NOT EXISTS whisper_recruiter_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recruiter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  photo_url TEXT,
  territory_id UUID REFERENCES whisper_recruiter_territories(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(recruiter_id)
);

ALTER TABLE whisper_recruiter_groups ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_recruiter_groups' AND policyname = 'whisper_recruiter_groups_select') THEN
    CREATE POLICY whisper_recruiter_groups_select ON whisper_recruiter_groups FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_recruiter_groups' AND policyname = 'whisper_recruiter_groups_insert') THEN
    CREATE POLICY whisper_recruiter_groups_insert ON whisper_recruiter_groups FOR INSERT WITH CHECK (auth.uid() = recruiter_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_recruiter_groups' AND policyname = 'whisper_recruiter_groups_update') THEN
    CREATE POLICY whisper_recruiter_groups_update ON whisper_recruiter_groups FOR UPDATE USING (auth.uid() = recruiter_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_recruiter_groups' AND policyname = 'whisper_recruiter_groups_delete') THEN
    CREATE POLICY whisper_recruiter_groups_delete ON whisper_recruiter_groups FOR DELETE USING (auth.uid() = recruiter_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_recruiter_groups_recruiter
  ON whisper_recruiter_groups(recruiter_id);
