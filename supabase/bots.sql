-- ============================================================================
-- Whisper bot crew — 18 believable accounts that post and engage on a
-- schedule. Content and engagement waves run through the billing backend
-- (`POST /bots/run`), which reads this registry with the service role.
--
-- Run once in the Supabase SQL editor — safe to re-run.
-- Bot emails end in @whisper.bot; password is random (never used to log in).
-- ============================================================================

BEGIN;

-- Registry + config -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.whisper_bots (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username text NOT NULL,
  persona text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.whisper_bot_config (
  id int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  paused boolean NOT NULL DEFAULT false,
  -- calm | normal | lively — how many bots act per wave.
  intensity text NOT NULL DEFAULT 'normal' CHECK (intensity IN ('calm','normal','lively')),
  last_run_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.whisper_bot_config (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- Service-role only (RLS on, no policies).
ALTER TABLE public.whisper_bots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whisper_bot_config ENABLE ROW LEVEL SECURITY;

-- Bot definitions --------------------------------------------------------------
CREATE TEMP TABLE _b (
  idx int,
  username text,
  email text,
  display_name text,
  bio text,
  avatar_url text,
  persona text,
  interests text[]
);

INSERT INTO _b VALUES
  (1,  'runwithlena',    'runwithlena@whisper.bot',    'Lena Fischer',    'Trail and road. Chasing golden hours and negative splits.',        'https://i.pravatar.cc/300?img=32', 'runner',      ARRAY['running','outdoors']),
  (2,  'tommy_lifts',    'tommy_lifts@whisper.bot',    'Tommy Vargas',    'Powerbuilding. If the bar bends, we are friends.',                 'https://i.pravatar.cc/300?img=53', 'lifter',      ARRAY['lifting','strength']),
  (3,  'yogawithpri',    'yogawithpri@whisper.bot',    'Priya Raman',     'Vinyasa teacher. Breath is the best pre-workout.',                 'https://i.pravatar.cc/300?img=44', 'yoga',        ARRAY['yoga','mindfulness']),
  (4,  'courtside_kev',  'courtside_kev@whisper.bot',  'Kevin Boateng',   'Hoops junkie. League Pass is my second rent.',                     'https://i.pravatar.cc/300?img=59', 'sportsfan',   ARRAY['basketball','sports']),
  (5,  'mia_moves',      'mia_moves@whisper.bot',      'Mia Castellano',  'Dance cardio + kettlebells. Movement should feel like joy.',       'https://i.pravatar.cc/300?img=48', 'crosstrain',  ARRAY['fitness','dance']),
  (6,  'ironoaks',       'ironoaks@whisper.bot',       'Oakley Grant',    'Strongman-ish. Carrying heavy things since 2016.',                 'https://i.pravatar.cc/300?img=61', 'lifter',      ARRAY['strength','strongman']),
  (7,  'swimtaro',       'swimtaro@whisper.bot',       'Taro Ishida',     'Masters swimmer. The black line and I have an understanding.',     'https://i.pravatar.cc/300?img=68', 'swimmer',     ARRAY['swimming','fitness']),
  (8,  'gridiron_gaby',  'gridiron_gaby@whisper.bot',  'Gaby Herrera',    'Flag football + film breakdowns. Route trees are art.',            'https://i.pravatar.cc/300?img=45', 'sportsfan',   ARRAY['football','sports']),
  (9,  'peakpete',       'peakpete@whisper.bot',       'Pete Lindqvist',  'Hiker and hill runner. The view is the rep.',                      'https://i.pravatar.cc/300?img=52', 'runner',      ARRAY['hiking','running']),
  (10, 'nourish_nat',    'nourish_nat@whisper.bot',    'Natalie Brooks',  'Meal prep obsessive. Protein first, always.',                      'https://i.pravatar.cc/300?img=47', 'nutrition',   ARRAY['nutrition','fitness']),
  (11, 'cyclesam',       'cyclesam@whisper.bot',       'Sam Okafor',      'Crit racer. Watts are temporary, coffee is forever.',              'https://i.pravatar.cc/300?img=56', 'cyclist',     ARRAY['cycling','outdoors']),
  (12, 'boxfit_bee',     'boxfit_bee@whisper.bot',     'Bianca Silva',    'Boxing conditioning. Hands up, spirits higher.',                   'https://i.pravatar.cc/300?img=41', 'crosstrain',  ARRAY['boxing','fitness']),
  (13, 'marathon_marc',  'marathon_marc@whisper.bot',  'Marc Dubois',     '3:02 marathoner hunting 2:59. Carbs are teammates.',               'https://i.pravatar.cc/300?img=54', 'runner',      ARRAY['running','endurance']),
  (14, 'flexfrida',      'flexfrida@whisper.bot',      'Frida Jensen',    'Physique athlete in the improvement season. Delts before dawn.',   'https://i.pravatar.cc/300?img=49', 'lifter',      ARRAY['bodybuilding','strength']),
  (15, 'thecourtreport', 'thecourtreport@whisper.bot', 'Jordan Ellis',    'Daily hoops takes. Occasionally right about the playoffs.',        'https://i.pravatar.cc/300?img=60', 'sportsfan',   ARRAY['basketball','sports']),
  (16, 'stretch_theo',   'stretch_theo@whisper.bot',   'Theo Martins',    'Mobility coach mindset. Touch your toes, change your life.',       'https://i.pravatar.cc/300?img=57', 'yoga',        ARRAY['mobility','recovery']),
  (17, 'wattsupwren',    'wattsupwren@whisper.bot',    'Wren Kowalski',   'Indoor cycling + data nerd. FTP is a personality trait.',          'https://i.pravatar.cc/300?img=43', 'cyclist',     ARRAY['cycling','fitness']),
  (18, 'coastalcarly',   'coastalcarly@whisper.bot',   'Carly Nguyen',    'Beach runs and open water swims. Salt water fixes most things.',   'https://i.pravatar.cc/300?img=38', 'swimmer',     ARRAY['swimming','running']);

-- Create auth users (idempotent) -----------------------------------------------
INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    instance_id, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
)
SELECT
    gen_random_uuid(),
    'authenticated',
    'authenticated',
    email,
    crypt(gen_random_uuid()::text, gen_salt('bf')),
    now(),
    '00000000-0000-0000-0000-000000000000',
    now(),
    now(),
    '{}'::jsonb,
    '{}'::jsonb
FROM _b
ON CONFLICT (email) DO NOTHING;

ALTER TABLE _b ADD COLUMN IF NOT EXISTS user_id uuid;
UPDATE _b b SET user_id = au.id FROM auth.users au WHERE au.email = b.email;

-- Profiles ----------------------------------------------------------------------
INSERT INTO whisper_profiles (
    user_id, username, display_name, bio, profile_image_url,
    account_type, is_coach, is_athlete, is_recruiter, is_director,
    ghost_enabled, is_private, is_liar, verified_athlete,
    interests, current_streak, longest_streak,
    total_workouts, total_volume_kg, banner_offset_y,
    onboarded_at, created_at, updated_at
)
SELECT
    b.user_id, b.username, b.display_name, b.bio, b.avatar_url,
    'user', false, false, false, false,
    false, false, false, false,
    b.interests,
    (random() * 15 + 2)::int,
    (random() * 30 + 8)::int,
    (random() * 150 + 15)::int,
    (random() * 40000 + 4000)::int,
    0,
    now() - (random() * 120 + 20) * interval '1 day',
    now() - (random() * 120 + 20) * interval '1 day',
    now()
FROM _b b
ON CONFLICT (user_id) DO NOTHING;

-- Registry ------------------------------------------------------------------------
INSERT INTO public.whisper_bots (user_id, username, persona)
SELECT b.user_id, b.username, b.persona FROM _b b
ON CONFLICT (user_id) DO NOTHING;

-- Bots follow each other + will follow real users organically over time -------------
INSERT INTO whisper_follows (follower_id, followee_id, followee_username, created_at)
SELECT f.user_id, t.user_id, t.username,
       now() - (random() * 40 + 1) * interval '1 day'
FROM _b f
JOIN _b t ON t.idx != f.idx
WHERE (f.idx * 7 + t.idx * 3) % 9 < 5
ON CONFLICT (follower_id, followee_id) DO NOTHING;

COMMIT;

-- Verification:
-- SELECT count(*) FROM whisper_bots;
-- SELECT * FROM whisper_bot_config;
