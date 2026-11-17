-- Whisper sample data seed — 12 users, 28 posts, follows, likes, comments.
-- Run via Supabase SQL Editor. Fully idempotent (safe to run multiple times).
-- All seed users use @whisper.seed emails and password: WhisperSeed2026!

BEGIN;

-- ─── Cleanup (idempotent) ───────────────────────────────────────────────────
DELETE FROM whisper_post_comments
  WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@whisper.seed');
DELETE FROM whisper_post_likes
  WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@whisper.seed');
DELETE FROM whisper_posts
  WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@whisper.seed');
DELETE FROM whisper_follows
  WHERE follower_id IN (SELECT id FROM auth.users WHERE email LIKE '%@whisper.seed')
     OR followee_id IN (SELECT id FROM auth.users WHERE email LIKE '%@whisper.seed');
DELETE FROM whisper_profiles
  WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@whisper.seed');
-- auth.users are kept (re-running reuses them via ON CONFLICT).

-- ─── Temp table: user definitions ──────────────────────────────────────────
CREATE TEMP TABLE _s (
  idx         int,
  username    text,
  email       text,
  display_name text,
  bio         text,
  avatar_url  text,
  is_coach    boolean,
  is_athlete  boolean,
  interests   text[]
);

INSERT INTO _s VALUES
  (1,  'maya_runs',      'maya_runs@whisper.seed',      'Maya Chen',         'Marathoner. 2x Boston finisher. Chasing sub-3.',                 'https://i.pravatar.cc/300?img=5',  false, true,  ARRAY['running','fitness']),
  (2,  'dev_walsh',      'dev_walsh@whisper.seed',      'Devin Walsh',       'Pickup basketball enthusiast. Knee braces are my best friend.',  'https://i.pravatar.cc/300?img=12', false, false, ARRAY['basketball','sports']),
  (3,  'sarakicks',      'sarakicks@whisper.seed',      'Sara Okonkwo',      'Soccer. Free kicks. Teaching my little sister the beautiful game.', 'https://i.pravatar.cc/300?img=9',  false, true,  ARRAY['soccer','fitness']),
  (4,  'marcus_bell',    'marcus_bell@whisper.seed',    'Marcus Bell',       'Strength coach and competitive lifter. Iron therapy.',          'https://i.pravatar.cc/300?img=15', true,  false, ARRAY['lifting','strength']),
  (5,  'jenna_park',     'jenna_park@whisper.seed',     'Jenna Park',        'Yoga instructor. Breath first, movement second.',               'https://i.pravatar.cc/300?img=20', true,  false, ARRAY['yoga','mindfulness']),
  (6,  'ryantorres',     'ryantorres@whisper.seed',     'Ryan Torres',       'Cyclist. Climber of hills, drinker of espresso.',               'https://i.pravatar.cc/300?img=8',  false, false, ARRAY['cycling','outdoors']),
  (7,  'coach_nate',     'coach_nate@whisper.seed',     'Nate Sullivan',     'S&C coach. I program so you do not have to guess.',             'https://i.pravatar.cc/300?img=11', true,  false, ARRAY['strength','coaching']),
  (8,  'bendasilva',     'bendasilva@whisper.seed',     'Ben Da Silva',      'Swimmer. 5am pool sessions are my therapy.',                    'https://i.pravatar.cc/300?img=14', false, true,  ARRAY['swimming','fitness']),
  (9,  'kam_07',         'kam_07@whisper.seed',         'Kam Akinwale',      'Football is life. Lineman by trade, filmmaker by heart.',       'https://i.pravatar.cc/300?img=16', false, true,  ARRAY['football','sports']),
  (10, 'leo_marchetti',  'leo_marchetti@whisper.seed',  'Leo Marchetti',     'Baseball. Pitcher. The curveball is my love language.',         'https://i.pravatar.cc/300?img=18', false, true,  ARRAY['baseball','sports']),
  (11, 'taylormade',     'taylormade@whisper.seed',     'Taylor Brooks',     'Tennis. USTA 4.5. Come to the net or stay home.',               'https://i.pravatar.cc/300?img=23', false, true,  ARRAY['tennis','fitness']),
  (12, 'ash_lifts',      'ash_lifts@whisper.seed',      'Ashley Nguyen',     'Powerlifter. 315 deadlift PR. Consistency over intensity.',     'https://i.pravatar.cc/300?img=25', false, true,  ARRAY['powerlifting','strength']);

-- ─── Create auth users (idempotent) ─────────────────────────────────────────
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
    crypt('WhisperSeed2026!', gen_salt('bf')),
    now(),
    '00000000-0000-0000-0000-000000000000',
    now(),
    now(),
    '{}'::jsonb,
    '{}'::jsonb
FROM _s
ON CONFLICT (email) DO NOTHING;

-- Populate user_id from auth.users
ALTER TABLE _s ADD COLUMN IF NOT EXISTS user_id uuid;
UPDATE _s s SET user_id = au.id FROM auth.users au WHERE au.email = s.email;

-- ─── Create whisper_profiles ────────────────────────────────────────────────
INSERT INTO whisper_profiles (
    user_id, username, display_name, bio, profile_image_url,
    account_type, is_coach, is_athlete, is_recruiter, is_director,
    ghost_enabled, is_private, is_liar, verified_athlete,
    interests, current_streak, longest_streak,
    total_workouts, total_volume_kg, banner_offset_y,
    onboarded_at, created_at, updated_at
)
SELECT
    s.user_id, s.username, s.display_name, s.bio, s.avatar_url,
    CASE WHEN s.is_coach THEN 'coach' WHEN s.is_athlete THEN 'athlete' ELSE 'user' END,
    s.is_coach, s.is_athlete, false, false,
    false, false, false, s.is_athlete,
    s.interests,
    (random() * 20 + 3)::int,
    (random() * 40 + 10)::int,
    (random() * 200 + 20)::int,
    (random() * 50000 + 5000)::int,
    0,
    now() - (random() * 90 + 30) * interval '1 day',
    now() - (random() * 90 + 30) * interval '1 day',
    now()
FROM _s s
ON CONFLICT (user_id) DO NOTHING;

-- ─── Temp table: post definitions ──────────────────────────────────────────
CREATE TEMP TABLE _p (
  idx         int,
  author_idx  int,
  caption     text,
  kind        text,
  media_urls  text[],
  media_count int,
  media_kind  text,
  location    text,
  hours_ago   int
);

INSERT INTO _p VALUES
  -- Text posts (10)
  (1,  1, 'Morning 6 miles before the sun came up. There is something about empty streets and your own footsteps that just hits different.', 'text', ARRAY[]::text[], 0, 'text', NULL, 3),
  (2,  2, 'Pickup game at the rec center went into OT. Love when strangers play like it is game 7.', 'text', ARRAY[]::text[], 0, 'text', NULL, 7),
  (3,  3, 'Free kicks in the backyard with my little sister. She has got a better left foot than half my team.', 'text', ARRAY[]::text[], 0, 'text', NULL, 14),
  (4,  5, '10 minutes of breathwork before you check your phone. That is the whole tip. Game changer.', 'text', ARRAY[]::text[], 0, 'text', NULL, 20),
  (5,  6, 'Road bike season is back. Climbed 2,300 ft today and my legs are writing letters of complaint.', 'text', ARRAY[]::text[], 0, 'text', NULL, 26),
  (6,  7, 'Progressive overload is not complicated. Add 5 lbs, do the reps, repeat for a year. Stop overthinking it.', 'text', ARRAY[]::text[], 0, 'text', NULL, 30),
  (7,  8, 'Pool was 78 degrees today. Perfect. Swam 3k and felt like I could have kept going.', 'text', ARRAY[]::text[], 0, 'text', NULL, 34),
  (8,  9, 'Film session then practice then more film. The grind is not sexy but it is necessary.', 'text', ARRAY[]::text[], 0, 'text', NULL, 38),
  (9,  11, 'Match point down, came back to win in three sets. Tennis teaches you to never count yourself out.', 'text', ARRAY[]::text[], 0, 'text', NULL, 44),
  (10, 12, 'Deadlift PR today: 315 lbs. Two years ago I could not deadlift 135. Consistency beats motivation every single time.', 'text', ARRAY[]::text[], 0, 'text', NULL, 48),

  -- Image posts (10)
  (11, 1, 'Golden hour run along the river. Swipe to the end for the view from the bridge.', 'photo',
       ARRAY['https://picsum.photos/seed/wh-river1/800/1000','https://picsum.photos/seed/wh-river2/800/1000','https://picsum.photos/seed/wh-bridge/800/1000'],
       3, 'image', 'Riverfront Trail', 5),
  (12, 4, 'Leg day aftermath. The stairs are now my enemy.', 'photo',
       ARRAY['https://picsum.photos/seed/wh-legday/800/800'],
       1, 'image', 'Iron Temple Gym', 9),
  (13, 5, 'Studio setup for tomorrow morning flow. Bringing blocks, straps, and good vibes.', 'photo',
       ARRAY['https://picsum.photos/seed/wh-yoga1/800/1000','https://picsum.photos/seed/wh-yoga2/800/1000'],
       2, 'image', 'Stillness Studio', 15),
  (14, 3, 'New cleats arrived. First touch felt incredible.', 'photo',
       ARRAY['https://picsum.photos/seed/wh-cleats/800/800'],
       1, 'image', NULL, 21),
  (15, 6, 'Climbing crew at the top of the ridge. Worth every pedal stroke.', 'photo',
       ARRAY['https://picsum.photos/seed/wh-ridge1/800/1000','https://picsum.photos/seed/wh-ridge2/800/1000'],
       2, 'image', 'Mount Diablo', 27),
  (16, 7, 'Programmed a full-body session for my new client. Sheets are ready, let us build.', 'photo',
       ARRAY['https://picsum.photos/seed/wh-program/800/1000'],
       1, 'image', NULL, 33),
  (17, 10, 'Batting practice. Found the barrel on every swing today.', 'photo',
       ARRAY['https://picsum.photos/seed/wh-batting/800/800'],
       1, 'image', 'Indoor Facility', 39),
  (18, 12, 'Home gym setup is finally complete. Squat rack, deadlift platform, and a mirror for form checks.', 'photo',
       ARRAY['https://picsum.photos/seed/wh-gym1/800/1000','https://picsum.photos/seed/wh-gym2/800/1000','https://picsum.photos/seed/wh-gym3/800/1000'],
       3, 'image', 'Home', 45),
  (19, 2, 'Court time. Nothing beats the sound of a clean swish.', 'photo',
       ARRAY['https://picsum.photos/seed/wh-court/800/800'],
       1, 'image', 'Riverside Rec', 50),
  (20, 8, 'Sunrise swim. Lane to myself, water like glass.', 'photo',
       ARRAY['https://picsum.photos/seed/wh-pool/800/1000'],
       1, 'image', 'City Aquatic Center', 54),

  -- Workout embed posts (5)
  (21, 4, '::whisper-workout-v1::{"id":"wk-001","displayName":"Push Day","focus":"Strength","durationSeconds":3240,"calories":380,"exerciseNames":["Bench Press","Overhead Press","Weighted Dips","Lateral Raises"],"totalSets":18,"date":1723100000000}
Hit every set with intent today. Bench felt smooth at 185.', 'workout', ARRAY[]::text[], 0, 'text', NULL, 6),
  (22, 7, '::whisper-workout-v1::{"id":"wk-002","displayName":"Hypertrophy Block W3D2","focus":"Hypertrophy","durationSeconds":3600,"calories":420,"exerciseNames":["Squat","RDL","Leg Press","Calf Raises","Ab Wheel"],"totalSets":22,"date":1723200000000}
Client session. She is getting strong fast. Back squat up 15 lbs in 3 weeks.', 'workout', ARRAY[]::text[], 0, 'text', NULL, 12),
  (23, 12, '::whisper-workout-v1::{"id":"wk-003","displayName":"Sumo Deadlift + Accessories","focus":"Posterior Chain","durationSeconds":2880,"calories":290,"exerciseNames":["Sumo Deadlift","Romanian Deadlift","Hip Thrusts","Hamstring Curls"],"totalSets":16,"date":1723300000000}
The posterior chain is angry but growing. That is the point.', 'workout', ARRAY[]::text[], 0, 'text', NULL, 28),
  (24, 9, '::whisper-workout-v1::{"id":"wk-004","displayName":"Conditioning Day","focus":"Conditioning","durationSeconds":2700,"calories":510,"exerciseNames":["Sled Pushes","Hill Sprints","Box Jumps","Battle Ropes"],"totalSets":12,"date":1723400000000}
Conditioning day. A lot of sweating. A lot of mental reps.', 'workout', ARRAY[]::text[], 0, 'text', NULL, 36),
  (25, 10, '::whisper-workout-v1::{"id":"wk-005","displayName":"Off-Season Strength","focus":"Strength","durationSeconds":3420,"calories":340,"exerciseNames":["Trap Bar Deadlift","Bulgarian Split Squat","Lat Pulldown","Pallof Press","Face Pulls"],"totalSets":20,"date":1723500000000}
Building the foundation for spring. Pitching velocity starts in the legs.', 'workout', ARRAY[]::text[], 0, 'text', NULL, 42),

  -- Grid posts (3)
  (26, 1, 'Race weekend in photos. From packet pickup to the finish line.', 'grid',
       ARRAY['https://picsum.photos/seed/wh-race1/800/1000','https://picsum.photos/seed/wh-race2/800/1000','https://picsum.photos/seed/wh-race3/800/1000','https://picsum.photos/seed/wh-race4/800/1000'],
       4, 'image', 'Chicago Marathon', 16),
  (27, 5, 'Retreat recap. Three days of yoga, hiking, and community.', 'grid',
       ARRAY['https://picsum.photos/seed/wh-retreat1/800/1000','https://picsum.photos/seed/wh-retreat2/800/1000','https://picsum.photos/seed/wh-retreat3/800/1000','https://picsum.photos/seed/wh-retreat4/800/1000'],
       4, 'image', 'Big Sur', 22),
  (28, 11, 'Tournament highlights. Semis, finals, and the trophy.', 'grid',
       ARRAY['https://picsum.photos/seed/wh-tennis1/800/1000','https://picsum.photos/seed/wh-tennis2/800/1000','https://picsum.photos/seed/wh-tennis3/800/1000'],
       3, 'image', 'Sectional Championship', 52);

-- Generate deterministic post IDs
ALTER TABLE _p ADD COLUMN IF NOT EXISTS post_id uuid DEFAULT gen_random_uuid();
UPDATE _p SET post_id = gen_random_uuid();

-- ─── Insert posts ───────────────────────────────────────────────────────────
INSERT INTO whisper_posts (
    id, user_id, kind, caption,
    media_urls, media_count, media_kind,
    is_ghost, is_reel, likes_count, comments_count,
    created_at, location
)
SELECT
    p.post_id,
    s.user_id,
    p.kind,
    p.caption,
    p.media_urls,
    p.media_count,
    p.media_kind,
    false,
    false,
    0,
    0,
    now() - (p.hours_ago || ' hours')::interval,
    p.location
FROM _p p
JOIN _s s ON s.idx = p.author_idx;

-- ─── Insert follows (each user follows 5-10 others) ─────────────────────────
-- whisper_follows unique constraint is (follower_id, followee_id)
INSERT INTO whisper_follows (follower_id, followee_id, followee_username, created_at)
SELECT
  f.user_id,
  t.user_id,
  t.username,
  now() - (random() * 60 + 1) * interval '1 day'
FROM _s f
JOIN _s t ON t.idx != f.idx
WHERE (f.idx * 13 + t.idx * 7) % 11 < 7  -- deterministic-ish: ~63% follow rate
ON CONFLICT (follower_id, followee_id) DO NOTHING;

-- Make sure the coaches (4, 5, 7) are followed by most users
INSERT INTO whisper_follows (follower_id, followee_id, followee_username, created_at)
SELECT
  s.user_id,
  c.user_id,
  c.username,
  now() - (random() * 60 + 1) * interval '1 day'
FROM _s s
JOIN _s c ON c.idx IN (4, 5, 7) AND s.idx != c.idx
ON CONFLICT (follower_id, followee_id) DO NOTHING;

-- ─── Insert likes (3-12 per post) ───────────────────────────────────────────
INSERT INTO whisper_post_likes (post_id, user_id, created_at)
SELECT
  p.post_id,
  s.user_id,
  now() - (random() * p.hours_ago + 1) * interval '1 hour'
FROM _p p
JOIN _s s ON s.idx != p.author_idx
WHERE (p.idx * 17 + s.idx * 11) % 13 < 8  -- ~62% like rate from non-authors
ON CONFLICT (post_id, user_id) DO NOTHING;

-- Extra likes on popular posts (PR posts, race posts)
INSERT INTO whisper_post_likes (post_id, user_id, created_at)
SELECT
  p.post_id,
  s.user_id,
  now() - (random() * 12 + 1) * interval '1 hour'
FROM _p p
JOIN _s s ON s.idx != p.author_idx
WHERE p.idx IN (10, 26, 18, 21)  -- PR post, race weekend, home gym, push day
ON CONFLICT (post_id, user_id) DO NOTHING;

-- ─── Insert comments ────────────────────────────────────────────────────────
INSERT INTO whisper_post_comments (post_id, user_id, username, body, created_at, updated_at)
SELECT
  p.post_id,
  s.user_id,
  s.username,
  c.body,
  now() - (random() * p.hours_ago + 1) * interval '1 hour',
  now()
FROM (VALUES
  -- Post 1 (maya_runs morning run)
  (1,  3,  'This is why you are the fastest person I know.'),
  (1,  6,  'Empty streets hit different. Great energy.'),
  (1,  5,  'Breathwork and a morning run. You get it.'),
  -- Post 2 (dev_walsh pickup basketball)
  (2,  9,  'Game 7 energy is the only energy.'),
  (2,  12, 'Need to find a rec league near me. This looks fun.'),
  -- Post 3 (sarakicks free kicks with sister)
  (3,  1,  'Future World Cup star right there.'),
  (3,  11, 'The left foot is a weapon. Keep coaching her.'),
  -- Post 4 (jenna_park breathwork tip)
  (4,  5,  'Preach. I have been doing this for a month and it changed my mornings.'),
  (4,  8,  'Tried this today before the pool. Felt locked in.'),
  -- Post 5 (ryantorres climbing + cycling)
  (5,  6,  'The letters of complaint are how you know it worked.'),
  (5,  1,  '2,300 ft on a road bike is no joke. Respect.'),
  -- Post 6 (coach_nate progressive overload)
  (6,  12, 'This is the post I needed today. Been overcomplicating things.'),
  (6,  4,  'Preach. The basics work. Always have.'),
  (6,  10, 'Saving this for my whole team.'),
  -- Post 7 (bendasilva swim)
  (7,  8,  'Nothing beats the perfect temperature pool.'),
  (7,  1,  '3k is no joke. You are built different.'),
  -- Post 8 (kam_07 film + practice)
  (8,  9,  'The grind behind the glory. Nobody sees the film sessions.'),
  (8,  10, 'Same energy in baseball. Film is half the work.'),
  -- Post 9 (taylormade tennis comeback)
  (9,  11, 'Match point down and you still pulled it out. Mental toughness.'),
  (9,  3,  'Never count yourself out. Love this.'),
  -- Post 10 (ash_lifts deadlift PR)
  (10, 12, '315 is a milestone. Next stop 405.'),
  (10, 4,  'From 135 to 315 in two years. That is how it is done.'),
  (10, 7,  'Consistency over intensity. Could not agree more.'),
  (10, 1,  'This is so inspiring. Might start lifting again.'),
  -- Post 11 (maya_runs golden hour images)
  (11, 6, 'That bridge shot is wallpaper material.'),
  (11, 3, 'Golden hour runs are the best runs.'),
  -- Post 12 (marcus_bell leg day image)
  (12, 4, 'Stairs after leg day should count as cardio.'),
  (12, 12, 'I feel this in my soul.'),
  -- Post 13 (jenna_park studio setup)
  (13, 5, 'That setup is so inviting. Wish I could make the 7am flow.'),
  (13, 1, 'Good vibes indeed. Need to try yoga again.'),
  -- Post 16 (coach_nate program sheet)
  (16, 7, 'Full-body is the way. She is going to be unstoppable.'),
  (16, 4, 'Clean programming. Wish my first coach had been this organized.'),
  -- Post 18 (ash_lifts home gym)
  (18, 12, 'Home gym goals. That deadlift platform though.'),
  (18, 4, 'The mirror for form checks is the pro move.'),
  (18, 7, 'This is how you build consistency. Remove every excuse to skip.'),
  -- Post 19 (dev_walsh court)
  (19, 2, 'That swish sound is addictive.'),
  (19, 9, 'Need to get back on a court. This looks clean.'),
  -- Post 20 (bendasilva sunrise swim)
  (20, 8, 'Lane to yourself and water like glass. Perfect morning.'),
  (20, 6, 'Sunrise + swim = best way to start the day.'),
  -- Post 21 (marcus_bell push day workout)
  (21, 4, 'Bench at 185 looking smooth. Keep pushing.'),
  (21, 12, 'How long have you been on this program? Seeing great progress.'),
  -- Post 22 (coach_nate client hypertrophy)
  (22, 7, '15 lbs on back squat in 3 weeks is real progress. Great coaching.'),
  (22, 5, 'This is why I send my yoga students to you for strength work.'),
  -- Post 26 (maya_runs race weekend grid)
  (26, 1, 'Race weekend always feels like a mini vacation. Great photos.'),
  (26, 6, 'The finish line shot. Best feeling in the world.'),
  (26, 3, 'You make me want to sign up for a marathon. Inspiring.'),
  -- Post 27 (jenna_park retreat grid)
  (27, 5, 'Best retreat yet. Already planning the next one.'),
  (27, 1, 'Three days of yoga and hiking sounds like heaven.'),
  -- Post 28 (taylormade tournament grid)
  (28, 11, 'That trophy photo is going on the wall.'),
  (28, 3, 'Semis to finals to trophy. What a run.')
) AS c(post_idx, user_idx, body)
JOIN _p p ON p.idx = c.post_idx
JOIN _s s ON s.idx = c.user_idx;

-- ─── Done ───────────────────────────────────────────────────────────────────
COMMIT;

-- Verification (run separately to check results):
-- SELECT count(*) FROM whisper_profiles WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@whisper.seed');
-- SELECT count(*) FROM whisper_posts WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@whisper.seed');
-- SELECT count(*) FROM whisper_follows WHERE follower_id IN (SELECT id FROM auth.users WHERE email LIKE '%@whisper.seed');
-- SELECT count(*) FROM whisper_post_likes WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@whisper.seed');
-- SELECT count(*) FROM whisper_post_comments WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@whisper.seed');
