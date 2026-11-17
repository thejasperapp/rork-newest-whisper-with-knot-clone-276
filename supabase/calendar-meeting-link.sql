-- ============================================================================
-- Add meeting_link column to calendar events
-- (run once in the Supabase SQL editor — safe to re-run)
-- ============================================================================

alter table public.whisper_calendar_events
  add column if not exists meeting_link text;

-- No RLS change needed — the existing event policies cover this column.
