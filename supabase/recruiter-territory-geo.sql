-- Recruiter territory GPS pins
-- ─────────────────────────────
-- Territories now carry their own coordinates: set from the recruiter's GPS
-- when the territory is claimed, or wherever the admin drops the pin on the
-- claim map. The iOS scout map prefers these over geocoded / regional
-- anchors. The app degrades gracefully when these columns are missing
-- (insert retries without them), but run this to make pins stick.

alter table public.whisper_recruiter_territories
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;
