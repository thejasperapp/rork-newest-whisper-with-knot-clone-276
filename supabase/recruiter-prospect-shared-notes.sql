-- Shared interview notes for recruiter prospects.
-- A recruiter can keep private notes in `notes` and choose to share additional
-- notes with their group in `shared_notes`. Both fields are scoped to the
-- prospect row, so any recruiter who has access to the prospect can read them.

alter table public.whisper_recruiter_prospects
add column if not exists shared_notes text;

-- Index for quickly surfacing prospects that have shared notes.
create index if not exists whisper_recruiter_prospects_shared_notes_idx
  on public.whisper_recruiter_prospects (recruiter_id)
  where shared_notes is not null;
