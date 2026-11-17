-- ============================================================================
-- Whisper meeting requests — a visitor (or member) asks a recruiter for a
-- meeting; the recruiter approves/denies; on approval a Whisper-branded email
-- with the Google Meet link is sent to the requester.
--
-- Run once in the Supabase SQL editor — safe to re-run.
-- ============================================================================

create type if not exists public.whisper_meeting_status as enum (
  'pending', 'approved', 'denied', 'cancelled'
);

create table if not exists public.whisper_meeting_requests (
  id uuid primary key default gen_random_uuid(),
  -- The recruiter the request is for (from whisper_featured_profiles.user_id).
  recruiter_id uuid references auth.users(id) on delete cascade,
  recruiter_username text,
  -- The featured profile row that surfaced the "Schedule a call" button,
  -- so we can render context back to the recruiter.
  featured_id uuid,
  -- Requester info — we always capture an email; account is optional.
  requester_user_id uuid references auth.users(id) on delete set null,
  requester_name text not null default '',
  requester_email text not null,
  -- ISO datetime string the requester picked ("preferred time").
  requested_time text not null,
  -- Optional timezone label (e.g. "America/Los_Angeles") for display.
  requester_timezone text,
  -- Free-form message from the requester.
  message text,
  status public.whisper_meeting_status not null default 'pending',
  -- Set by the recruiter on approval — Google Meet link or any video URL.
  meeting_link text,
  -- Optional note the recruiter adds (sent in the approval email).
  recruiter_note text,
  decided_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists whisper_meeting_requests_recruiter_idx
  on public.whisper_meeting_requests (recruiter_id, created_at desc);
create index if not exists whisper_meeting_requests_status_idx
  on public.whisper_meeting_requests (status, created_at desc);
create index if not exists whisper_meeting_requests_requester_idx
  on public.whisper_meeting_requests (requester_user_id, created_at desc);

alter table public.whisper_meeting_requests enable row level security;

-- Public can create requests (the "Schedule a call" button is on a public
-- marketing page). All other access goes through the billing backend with the
-- service role key, which bypasses RLS.
drop policy if exists "wmr public insert" on public.whisper_meeting_requests;
create policy "wmr public insert" on public.whisper_meeting_requests
  for insert with check (true);

-- A signed-in user can read their own submitted requests.
drop policy if exists "wmr requester read own" on public.whisper_meeting_requests;
create policy "wmr requester read own" on public.whisper_meeting_requests
  for select using (
    requester_user_id is not null and auth.uid() = requester_user_id
  );
