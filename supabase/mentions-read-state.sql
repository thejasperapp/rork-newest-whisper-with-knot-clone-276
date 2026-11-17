-- Mentions read receipts
-- The iOS Activity tab stamps whisper_mentions.read_at when the user opens
-- Activity (or taps "Mark all as read"). The column was never added to the
-- live database, so every "tagged you in a post" row stayed unread forever.
-- Run this in the Supabase SQL editor.

alter table if exists public.whisper_mentions
  add column if not exists read_at timestamptz;

-- Helpful index for the unread badge query (mentioned_user_id + unread).
create index if not exists whisper_mentions_unread_idx
  on public.whisper_mentions (mentioned_user_id)
  where read_at is null;
