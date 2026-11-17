-- Live chat messages table + realtime publication.
-- Apply manually via the Supabase SQL Editor (runMigration is not available).
-- NOTE: PostgreSQL does NOT support `CREATE POLICY IF NOT EXISTS`. Policies
-- below are created inside `DO $$` blocks that skip them when they already exist.

-- Chat messages table --------------------------------------------------------
CREATE TABLE IF NOT EXISTS whisper_live_chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES whisper_live_rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT NOT NULL,
  body TEXT NOT NULL,
  is_host BOOLEAN NOT NULL DEFAULT false,
  is_pinned BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes --------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_live_chat_room ON whisper_live_chat_messages(room_id, created_at);

-- RLS ------------------------------------------------------------------------
ALTER TABLE whisper_live_chat_messages ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Everyone can read chat messages (it's a live room — chat is public).
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_chat_messages' AND policyname = 'whisper_live_chat_select') THEN
    CREATE POLICY whisper_live_chat_select ON whisper_live_chat_messages FOR SELECT USING (true);
  END IF;
  -- Users can only insert their own messages.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_chat_messages' AND policyname = 'whisper_live_chat_insert') THEN
    CREATE POLICY whisper_live_chat_insert ON whisper_live_chat_messages FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  -- Host can pin/unpin messages.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_chat_messages' AND policyname = 'whisper_live_chat_update') THEN
    CREATE POLICY whisper_live_chat_update ON whisper_live_chat_messages FOR UPDATE
      USING (auth.uid() = user_id OR auth.uid() IN (SELECT host_id FROM whisper_live_rooms WHERE id = room_id));
  END IF;
  -- Users can delete their own messages; hosts can delete any.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'whisper_live_chat_messages' AND policyname = 'whisper_live_chat_delete') THEN
    CREATE POLICY whisper_live_chat_delete ON whisper_live_chat_messages FOR DELETE
      USING (auth.uid() = user_id OR auth.uid() IN (SELECT host_id FROM whisper_live_rooms WHERE id = room_id));
  END IF;
END $$;

-- Add tables to the Supabase Realtime publication so postgres_changes work.
-- Without this, realtime subscriptions on these tables silently never fire.
DO $$
BEGIN
  -- Live chat messages
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'whisper_live_chat_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE whisper_live_chat_messages;
  END IF;

  -- Speaker requests (ensure this is in the publication for auto-refresh)
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'whisper_live_speaker_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE whisper_live_speaker_requests;
  END IF;

  -- Speakers table (for auto-refresh when speakers are added/removed)
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'whisper_live_room_speakers'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE whisper_live_room_speakers;
  END IF;

  -- Listeners table
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'whisper_live_room_listeners'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE whisper_live_room_listeners;
  END IF;

  -- Rooms table
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'whisper_live_rooms'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE whisper_live_rooms;
  END IF;
END $$;
