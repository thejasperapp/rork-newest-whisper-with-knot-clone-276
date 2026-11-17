-- Add cta_url column to featured profiles.
-- Lets creators (and athletes) link their button to an external outlet
-- (personal website, portfolio, booking page, etc.) instead of only
-- linking to a Whisper profile.

alter table public.whisper_featured_profiles
  add column if not exists cta_url text;
