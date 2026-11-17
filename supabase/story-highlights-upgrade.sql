-- Story Highlights fidelity upgrade — run once in the Supabase SQL editor.
--
-- Highlight items are denormalized copies of stories so they outlive the
-- 24h expiry. Until now they only copied the flat image + caption + music
-- title, which meant saved highlights lost their interactive stickers
-- (polls, questions, gifs, text) and their playable music. These columns
-- let the apps copy the full story payload into the highlight:
--
--   metadata       — the story's sticker JSON (rendered live by viewers)
--   music_url      — the 30s preview URL so highlights keep playing music
--   music_artwork  — album art for the music marquee
--
-- Both apps insert with a graceful fallback, so nothing breaks if this
-- migration hasn't run yet — highlights just stay flat until it does.

alter table public.whisper_story_highlight_items
  add column if not exists metadata text,
  add column if not exists music_url text,
  add column if not exists music_artwork text;
