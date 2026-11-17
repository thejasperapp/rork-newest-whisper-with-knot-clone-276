-- ═══════════════════════════════════════════════════════════════════════
-- Whisper Live + Grid fixes
--
-- Run manually in the Supabase SQL Editor.
-- Safe to re-run: every statement is guarded with IF NOT EXISTS / OR REPLACE.
-- NOTE: PostgreSQL does NOT support CREATE POLICY IF NOT EXISTS — policies
-- are created inside DO $$ blocks that skip them when they already exist.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. Scheduling ────────────────────────────────────────────────────────

ALTER TABLE whisper_live_rooms
  ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_live_rooms_scheduled
  ON whisper_live_rooms(scheduled_at)
  WHERE scheduled_at IS NOT NULL;

ALTER TABLE whisper_live_room_speakers
  ADD COLUMN IF NOT EXISTS can_video BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE whisper_live_room_speakers
  ADD COLUMN IF NOT EXISTS is_cohost BOOLEAN NOT NULL DEFAULT false;

-- ─── 2. Group live invites ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS whisper_live_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES whisper_live_rooms(id) ON DELETE CASCADE,
  inviter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invitee_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','declined')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(room_id, invitee_id)
);

ALTER TABLE whisper_live_invites ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_invites' AND policyname = 'wli_select') THEN
    CREATE POLICY wli_select ON whisper_live_invites FOR SELECT
      USING (auth.uid() = inviter_id OR auth.uid() = invitee_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_invites' AND policyname = 'wli_insert') THEN
    CREATE POLICY wli_insert ON whisper_live_invites FOR INSERT
      WITH CHECK (auth.uid() = inviter_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_invites' AND policyname = 'wli_update') THEN
    CREATE POLICY wli_update ON whisper_live_invites FOR UPDATE
      USING (auth.uid() = invitee_id OR auth.uid() = inviter_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_invites' AND policyname = 'wli_delete') THEN
    CREATE POLICY wli_delete ON whisper_live_invites FOR DELETE
      USING (auth.uid() = inviter_id OR auth.uid() = invitee_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_live_invites_invitee
  ON whisper_live_invites(invitee_id, status);
CREATE INDEX IF NOT EXISTS idx_live_invites_room
  ON whisper_live_invites(room_id);

-- ─── 3. Max 4 broadcasters per live ───────────────────────────────────────

CREATE OR REPLACE FUNCTION whisper_live_speaker_cap()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF (SELECT count(*) FROM whisper_live_room_speakers WHERE room_id = NEW.room_id) >= 4 THEN
    RAISE EXCEPTION 'live room is full (max 4 broadcasters)';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS whisper_live_speaker_cap_trg ON whisper_live_room_speakers;
CREATE TRIGGER whisper_live_speaker_cap_trg
  BEFORE INSERT ON whisper_live_room_speakers
  FOR EACH ROW EXECUTE FUNCTION whisper_live_speaker_cap();

-- ─── 4. Auto-delete ended lives ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION whisper_live_room_autodelete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF OLD.is_live = true AND NEW.is_live = false
     AND (NEW.scheduled_at IS NULL OR NEW.scheduled_at <= now()) THEN
    DELETE FROM whisper_live_rooms WHERE id = NEW.id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS whisper_live_room_autodelete_trg ON whisper_live_rooms;
CREATE TRIGGER whisper_live_room_autodelete_trg
  AFTER UPDATE ON whisper_live_rooms
  FOR EACH ROW EXECUTE FUNCTION whisper_live_room_autodelete();

-- ─── 5. Auto-end when the last broadcaster leaves ─────────────────────────

CREATE OR REPLACE FUNCTION whisper_live_room_autoend()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  remaining INTEGER;
BEGIN
  SELECT count(*) INTO remaining
  FROM whisper_live_room_speakers
  WHERE room_id = OLD.room_id;

  IF remaining = 0 THEN
    UPDATE whisper_live_rooms
    SET is_live = false
    WHERE id = OLD.room_id AND is_live = true;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS whisper_live_room_autoend_trg ON whisper_live_room_speakers;
CREATE TRIGGER whisper_live_room_autoend_trg
  AFTER DELETE ON whisper_live_room_speakers
  FOR EACH ROW EXECUTE FUNCTION whisper_live_room_autoend();

-- ─── 6. Cleanup: purge stale ended lives ──────────────────────────────────

DELETE FROM whisper_live_rooms
WHERE is_live = false
  AND (scheduled_at IS NULL OR scheduled_at <= now());

-- ─── 7. Realtime publication ──────────────────────────────────────────────

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'whisper_live_rooms',
    'whisper_live_room_speakers',
    'whisper_live_room_listeners',
    'whisper_live_speaker_requests',
    'whisper_live_chat_messages',
    'whisper_live_invites'
  ]
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = t)
       AND NOT EXISTS (
         SELECT 1 FROM pg_publication_tables
         WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t
       ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- GRID POSTS — like/comment counts and kind constraint
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 8. Allow 'grid' and 'reel' post kinds ────────────────────────────────

ALTER TABLE public.whisper_posts DROP CONSTRAINT IF EXISTS whisper_posts_kind_check;
ALTER TABLE public.whisper_posts
  ADD CONSTRAINT whisper_posts_kind_check
  CHECK (kind IN ('photo','workout','progress','text','grid','reel'));

-- ─── 9. Count columns + sync triggers ─────────────────────────────────────

ALTER TABLE public.whisper_posts
  ADD COLUMN IF NOT EXISTS likes_count INT NOT NULL DEFAULT 0;
ALTER TABLE public.whisper_posts
  ADD COLUMN IF NOT EXISTS comments_count INT NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.whisper_likes_bump() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF (tg_op = 'INSERT') THEN
    UPDATE public.whisper_posts SET likes_count = likes_count + 1 WHERE id = new.post_id;
  ELSIF (tg_op = 'DELETE') THEN
    UPDATE public.whisper_posts SET likes_count = greatest(likes_count - 1, 0) WHERE id = old.post_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS whisper_likes_bump_trg ON public.whisper_post_likes;
CREATE TRIGGER whisper_likes_bump_trg
  AFTER INSERT OR DELETE ON public.whisper_post_likes
  FOR EACH ROW EXECUTE FUNCTION public.whisper_likes_bump();

CREATE OR REPLACE FUNCTION public.whisper_comments_bump() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF (tg_op = 'INSERT') THEN
    UPDATE public.whisper_posts SET comments_count = comments_count + 1 WHERE id = new.post_id;
  ELSIF (tg_op = 'DELETE') THEN
    UPDATE public.whisper_posts SET comments_count = greatest(comments_count - 1, 0) WHERE id = old.post_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS whisper_comments_bump_trg ON public.whisper_post_comments;
CREATE TRIGGER whisper_comments_bump_trg
  AFTER INSERT OR DELETE ON public.whisper_post_comments
  FOR EACH ROW EXECUTE FUNCTION public.whisper_comments_bump();

-- ─── 10. Backfill counts ──────────────────────────────────────────────────

UPDATE public.whisper_posts p SET
  likes_count = COALESCE((SELECT count(*) FROM public.whisper_post_likes l WHERE l.post_id = p.id), 0),
  comments_count = COALESCE((SELECT count(*) FROM public.whisper_post_comments c WHERE c.post_id = p.id), 0);

-- ─── 11. RLS on speaker_requests: allow users to insert their own ─────────
-- The iOS and web clients insert directly, so RLS must allow self-inserts.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_speaker_requests' AND policyname = 'wlsr_insert_own') THEN
    CREATE POLICY wlsr_insert_own ON whisper_live_speaker_requests
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_speaker_requests' AND policyname = 'wlsr_select') THEN
    CREATE POLICY wlsr_select ON whisper_live_speaker_requests
      FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_speaker_requests' AND policyname = 'wlsr_update') THEN
    CREATE POLICY wlsr_update ON whisper_live_speaker_requests
      FOR UPDATE USING (true);
  END IF;
END $$;

-- ─── 12. RLS on whisper_live_room_speakers: allow self-insert ─────────────

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_room_speakers' AND policyname = 'wlrs_insert') THEN
    CREATE POLICY wlrs_insert ON whisper_live_room_speakers
      FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_room_speakers' AND policyname = 'wlrs_select') THEN
    CREATE POLICY wlrs_select ON whisper_live_room_speakers
      FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_room_speakers' AND policyname = 'wlrs_delete') THEN
    CREATE POLICY wlrs_delete ON whisper_live_room_speakers
      FOR DELETE USING (true);
  END IF;
END $$;
