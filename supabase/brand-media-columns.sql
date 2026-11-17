-- Brand profile media columns — the marketplace showcase.
-- The backend writes cover_url / media_urls / video_url on every save, but
-- these columns were never added to the live table, so every brand profile
-- upsert silently failed (Postgres rejects unknown columns). This migration
-- adds them and is safe to re-run (idempotent).

alter table public.whisper_brand_profiles
  add column if not exists cover_url text,
  add column if not exists media_urls text[] not null default '{}',
  add column if not exists video_url text;
