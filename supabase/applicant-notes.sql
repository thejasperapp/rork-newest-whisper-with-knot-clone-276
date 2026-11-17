-- Whisper applicant per-question recruiter notes
-- Apply manually via the Supabase SQL Editor.
-- NOTE: PostgreSQL does NOT support `CREATE POLICY IF NOT EXISTS`. Policies
-- below are created inside `DO $$` blocks that skip them when they already exist.

-- Recruiters can leave notes on individual question answers so the review feels
-- like a conversation, not just a form. Each note is tied to a response + question.
CREATE TABLE IF NOT EXISTS whisper_applicant_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  response_id UUID NOT NULL REFERENCES whisper_applicant_responses(id) ON DELETE CASCADE,
  question_id UUID NOT NULL REFERENCES whisper_applicant_questions(id) ON DELETE CASCADE,
  recruiter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  note TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE whisper_applicant_notes ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_applicant_notes' AND policyname = 'applicant_notes_select') THEN
    CREATE POLICY applicant_notes_select ON whisper_applicant_notes FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_applicant_notes' AND policyname = 'applicant_notes_insert') THEN
    CREATE POLICY applicant_notes_insert ON whisper_applicant_notes FOR INSERT WITH CHECK (auth.uid() = recruiter_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_applicant_notes' AND policyname = 'applicant_notes_update') THEN
    CREATE POLICY applicant_notes_update ON whisper_applicant_notes FOR UPDATE USING (auth.uid() = recruiter_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_applicant_notes' AND policyname = 'applicant_notes_delete') THEN
    CREATE POLICY applicant_notes_delete ON whisper_applicant_notes FOR DELETE USING (auth.uid() = recruiter_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_applicant_notes_response ON whisper_applicant_notes(response_id);
CREATE INDEX IF NOT EXISTS idx_applicant_notes_question ON whisper_applicant_notes(response_id, question_id);
