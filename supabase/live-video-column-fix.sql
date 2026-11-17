-- Fix: ensure `whisper_live_rooms` has the `is_video_enabled` column so the
-- LiveKit room view can read it without hitting the PostgREST schema-cache error.
-- Run this in the Supabase SQL Editor if you see:
--   "Could not find the 'is_video_enabled' column of 'whisper_live_rooms' in the schema cache"
--
-- `runMigration` is not available, so this must be applied manually.

-- Add the column if the table exists but the column is missing.
-- Default true so existing rooms remain video-capable.
ALTER TABLE IF EXISTS whisper_live_rooms
  ADD COLUMN IF NOT EXISTS is_video_enabled BOOLEAN NOT NULL DEFAULT true;

-- Refresh the PostgREST schema cache so the new column is available immediately.
NOTIFY pgrst, 'reload schema';
