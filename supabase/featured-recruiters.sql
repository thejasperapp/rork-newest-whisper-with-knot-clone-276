-- Allow 'recruiter' spotlights on whisper_featured_profiles.
-- Run once in the Supabase SQL editor (safe to re-run). Needed only if the
-- table was created before recruiters were added; fresh installs of
-- featured-profiles.sql already include it.

alter table public.whisper_featured_profiles
  drop constraint if exists whisper_featured_profiles_kind_check;

alter table public.whisper_featured_profiles
  add constraint whisper_featured_profiles_kind_check
  check (kind in ('coach', 'athlete', 'creator', 'recruiter'));
