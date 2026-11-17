-- Whisper applicant questionnaire system
-- Recruiter QR codes → leads scan → fill questionnaire → recruiter sees in real-time
-- Admins can edit questions; applications stored per-recruiter
-- Apply manually via the Supabase SQL Editor (runMigration is not available).
-- NOTE: PostgreSQL does NOT support `CREATE POLICY IF NOT EXISTS`.

-- Admin-editable questions shown to applicants when they sign up via a
-- recruiter's QR code / referral link.
CREATE TABLE IF NOT EXISTS whisper_applicant_questions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  question TEXT NOT NULL,
  question_type TEXT NOT NULL DEFAULT 'text', -- text | textarea | select | number | rating
  options JSONB, -- for select/multi-select: ["Option 1", "Option 2", ...]
  required BOOLEAN NOT NULL DEFAULT true,
  display_order INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Applicant responses — one row per applicant per recruiter
CREATE TABLE IF NOT EXISTS whisper_applicant_responses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recruiter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recruiter_code TEXT, -- the referral code used (denormalized for lookups)
  applicant_email TEXT,
  applicant_name TEXT,
  applicant_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  answers JSONB NOT NULL DEFAULT '{}', -- { question_id: { question: "...", answer: "..." } }
  -- AI-computed match results (filled by the matching engine)
  best_position TEXT, -- coach | athlete | creator
  position_scores JSONB, -- { coach: 78, athlete: 45, creator: 62 }
  potential_score INTEGER, -- 0-100 overall potential
  confidence_score INTEGER, -- 0-100 confidence in the match
  status TEXT NOT NULL DEFAULT 'submitted', -- submitted | reviewed | accepted | rejected
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE whisper_applicant_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE whisper_applicant_responses ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Questions: anyone can read active questions; admins can insert/update/delete
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_applicant_questions' AND policyname = 'applicant_questions_select') THEN
    CREATE POLICY applicant_questions_select ON whisper_applicant_questions FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_applicant_questions' AND policyname = 'applicant_questions_insert') THEN
    CREATE POLICY applicant_questions_insert ON whisper_applicant_questions FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_applicant_questions' AND policyname = 'applicant_questions_update') THEN
    CREATE POLICY applicant_questions_update ON whisper_applicant_questions FOR UPDATE USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_applicant_questions' AND policyname = 'applicant_questions_delete') THEN
    CREATE POLICY applicant_questions_delete ON whisper_applicant_questions FOR DELETE USING (true);
  END IF;

  -- Responses: anyone can submit (leads may not have an account yet);
  -- recruiters can read their own responses; admins can read all.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_applicant_responses' AND policyname = 'applicant_responses_select') THEN
    CREATE POLICY applicant_responses_select ON whisper_applicant_responses FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_applicant_responses' AND policyname = 'applicant_responses_insert') THEN
    CREATE POLICY applicant_responses_insert ON whisper_applicant_responses FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_applicant_responses' AND policyname = 'applicant_responses_update') THEN
    CREATE POLICY applicant_responses_update ON whisper_applicant_responses FOR UPDATE USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_applicant_responses' AND policyname = 'applicant_responses_delete') THEN
    CREATE POLICY applicant_responses_delete ON whisper_applicant_responses FOR DELETE USING (true);
  END IF;
END $$;

-- Index for recruiter lookups
CREATE INDEX IF NOT EXISTS idx_applicant_responses_recruiter ON whisper_applicant_responses(recruiter_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_applicant_questions_order ON whisper_applicant_questions(is_active, display_order);

-- Seed default questions
INSERT INTO whisper_applicant_questions (question, question_type, options, required, display_order, is_active)
SELECT * FROM (VALUES
  ('What is your full name?', 'text', NULL, true, 0, true),
  ('What is your email address?', 'text', NULL, true, 1, true),
  ('What role are you most interested in?', 'select', '["Coach","Athlete","Creator","Not sure yet"]'::jsonb, true, 2, true),
  ('How would you describe your current fitness level?', 'select', '["Beginner","Intermediate","Advanced","Elite/Competitive"]'::jsonb, true, 3, true),
  ('Do you have coaching or training experience?', 'select', '["Yes, professionally","Yes, informally","No, but I want to learn","No"]'::jsonb, false, 4, true),
  ('What is your primary sport or fitness discipline?', 'text', NULL, false, 5, true),
  ('How many years have you been active in fitness/sports?', 'select', '["Less than 1 year","1-3 years","3-5 years","5+ years"]'::jsonb, false, 6, true),
  ('Are you active on social media? If so, share your handles.', 'textarea', NULL, false, 7, true),
  ('What are your goals for the next 12 months?', 'textarea', NULL, false, 8, true),
  ('Why do you want to join Whisper?', 'textarea', NULL, false, 9, true)
) AS t(question, question_type, options, required, display_order, is_active)
WHERE NOT EXISTS (SELECT 1 FROM whisper_applicant_questions);
