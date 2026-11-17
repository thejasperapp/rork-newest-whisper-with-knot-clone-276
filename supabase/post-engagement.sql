-- Whisper post engagement tables — likes, comments, reposts, bookmarks, pins.
-- Apply manually via the Supabase SQL Editor (runMigration is not available).
-- NOTE: PostgreSQL does NOT support `CREATE POLICY IF NOT EXISTS`. Policies
-- below are created inside `DO $$` blocks that skip them when they already exist.

-- Likes ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS whisper_post_likes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES whisper_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(post_id, user_id)
);

-- Comments -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS whisper_post_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES whisper_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT NOT NULL,
  body TEXT NOT NULL,
  parent_comment_id UUID REFERENCES whisper_post_comments(id) ON DELETE CASCADE,
  likes_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Comment likes --------------------------------------------------------------
CREATE TABLE IF NOT EXISTS whisper_comment_likes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  comment_id UUID NOT NULL REFERENCES whisper_post_comments(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(comment_id, user_id)
);

-- Reposts --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS whisper_reposts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES whisper_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(post_id, user_id)
);

-- Bookmarks ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS whisper_bookmarks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES whisper_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(post_id, user_id)
);

-- Pinned posts ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS whisper_pinned_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES whisper_posts(id) ON DELETE CASCADE,
  position INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, post_id)
);

-- RLS ------------------------------------------------------------------------
ALTER TABLE whisper_post_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE whisper_post_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE whisper_comment_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE whisper_reposts ENABLE ROW LEVEL SECURITY;
ALTER TABLE whisper_bookmarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE whisper_pinned_posts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Likes: everyone can read counts; users can only insert/delete their own likes.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_post_likes' AND policyname = 'whisper_post_likes_select') THEN
    CREATE POLICY whisper_post_likes_select ON whisper_post_likes FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_post_likes' AND policyname = 'whisper_post_likes_insert') THEN
    CREATE POLICY whisper_post_likes_insert ON whisper_post_likes FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_post_likes' AND policyname = 'whisper_post_likes_delete') THEN
    CREATE POLICY whisper_post_likes_delete ON whisper_post_likes FOR DELETE USING (auth.uid() = user_id);
  END IF;

  -- Comments: everyone can read; users can only insert/delete their own comments.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_post_comments' AND policyname = 'whisper_post_comments_select') THEN
    CREATE POLICY whisper_post_comments_select ON whisper_post_comments FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_post_comments' AND policyname = 'whisper_post_comments_insert') THEN
    CREATE POLICY whisper_post_comments_insert ON whisper_post_comments FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_post_comments' AND policyname = 'whisper_post_comments_delete') THEN
    CREATE POLICY whisper_post_comments_delete ON whisper_post_comments FOR DELETE USING (auth.uid() = user_id);
  END IF;

  -- Comment likes
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_comment_likes' AND policyname = 'whisper_comment_likes_select') THEN
    CREATE POLICY whisper_comment_likes_select ON whisper_comment_likes FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_comment_likes' AND policyname = 'whisper_comment_likes_insert') THEN
    CREATE POLICY whisper_comment_likes_insert ON whisper_comment_likes FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_comment_likes' AND policyname = 'whisper_comment_likes_delete') THEN
    CREATE POLICY whisper_comment_likes_delete ON whisper_comment_likes FOR DELETE USING (auth.uid() = user_id);
  END IF;

  -- Reposts
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_reposts' AND policyname = 'whisper_reposts_select') THEN
    CREATE POLICY whisper_reposts_select ON whisper_reposts FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_reposts' AND policyname = 'whisper_reposts_insert') THEN
    CREATE POLICY whisper_reposts_insert ON whisper_reposts FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_reposts' AND policyname = 'whisper_reposts_delete') THEN
    CREATE POLICY whisper_reposts_delete ON whisper_reposts FOR DELETE USING (auth.uid() = user_id);
  END IF;

  -- Bookmarks
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_bookmarks' AND policyname = 'whisper_bookmarks_select') THEN
    CREATE POLICY whisper_bookmarks_select ON whisper_bookmarks FOR SELECT USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_bookmarks' AND policyname = 'whisper_bookmarks_insert') THEN
    CREATE POLICY whisper_bookmarks_insert ON whisper_bookmarks FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_bookmarks' AND policyname = 'whisper_bookmarks_delete') THEN
    CREATE POLICY whisper_bookmarks_delete ON whisper_bookmarks FOR DELETE USING (auth.uid() = user_id);
  END IF;

  -- Pinned posts
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_pinned_posts' AND policyname = 'whisper_pinned_posts_select') THEN
    CREATE POLICY whisper_pinned_posts_select ON whisper_pinned_posts FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_pinned_posts' AND policyname = 'whisper_pinned_posts_insert') THEN
    CREATE POLICY whisper_pinned_posts_insert ON whisper_pinned_posts FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_pinned_posts' AND policyname = 'whisper_pinned_posts_delete') THEN
    CREATE POLICY whisper_pinned_posts_delete ON whisper_pinned_posts FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

-- Indexes --------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_post_likes_post ON whisper_post_likes(post_id);
CREATE INDEX IF NOT EXISTS idx_post_likes_user ON whisper_post_likes(user_id);
CREATE INDEX IF NOT EXISTS idx_post_comments_post ON whisper_post_comments(post_id, created_at);
CREATE INDEX IF NOT EXISTS idx_comment_likes_comment ON whisper_comment_likes(comment_id);
CREATE INDEX IF NOT EXISTS idx_reposts_post ON whisper_reposts(post_id);
CREATE INDEX IF NOT EXISTS idx_reposts_user ON whisper_reposts(user_id);
CREATE INDEX IF NOT EXISTS idx_bookmarks_user ON whisper_bookmarks(user_id);
CREATE INDEX IF NOT EXISTS idx_pinned_posts_user ON whisper_pinned_posts(user_id, position);

-- Triggers to keep whisper_posts.likes_count and comments_count in sync -------
CREATE OR REPLACE FUNCTION sync_post_likes_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE whisper_posts SET likes_count = COALESCE(likes_count, 0) + 1 WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE whisper_posts SET likes_count = GREATEST(COALESCE(likes_count, 0) - 1, 0) WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS whisper_post_likes_count ON whisper_post_likes;
CREATE TRIGGER whisper_post_likes_count
AFTER INSERT OR DELETE ON whisper_post_likes
FOR EACH ROW EXECUTE FUNCTION sync_post_likes_count();

CREATE OR REPLACE FUNCTION sync_post_comments_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE whisper_posts SET comments_count = COALESCE(comments_count, 0) + 1 WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE whisper_posts SET comments_count = GREATEST(COALESCE(comments_count, 0) - 1, 0) WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS whisper_post_comments_count ON whisper_post_comments;
CREATE TRIGGER whisper_post_comments_count
AFTER INSERT OR DELETE ON whisper_post_comments
FOR EACH ROW EXECUTE FUNCTION sync_post_comments_count();
