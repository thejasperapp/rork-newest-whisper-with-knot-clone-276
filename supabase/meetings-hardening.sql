-- ============================================================================
-- SUPERSEDED — do not apply this file.
--
-- The policies that used to live here referenced each other across tables
-- (whisper_meetings ↔ whisper_meeting_participants), which Postgres rejects
-- at query time with "infinite recursion detected in policy" (42P17). That
-- broke creating, scheduling, and reading meetings.
--
-- Apply supabase/meetings-recovery.sql instead. It keeps the exact same
-- privacy model (meetings, rosters, and transcripts are private to the host
-- and link members; joining goes through the guarded join_whisper_meeting
-- RPC) but implements the checks with SECURITY DEFINER functions that do not
-- recurse.
-- ============================================================================

select 'superseded — run meetings-recovery.sql instead' as notice;
