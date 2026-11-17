-- ============================================================================
-- Calendar event notes + recruiter prospect pipeline
-- (run once in the Supabase SQL editor — safe to re-run)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Calendar event notes — mini notes left by tagged/RSVP'd users
-- ---------------------------------------------------------------------------
create table if not exists public.whisper_calendar_notes (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.whisper_calendar_events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  username text,
  body text not null,
  created_at timestamptz not null default now()
);

alter table public.whisper_calendar_notes enable row level security;

drop policy if exists "wcn select all" on public.whisper_calendar_notes;
create policy "wcn select all" on public.whisper_calendar_notes
  for select using (true);

drop policy if exists "wcn insert own" on public.whisper_calendar_notes;
create policy "wcn insert own" on public.whisper_calendar_notes
  for insert with check (auth.uid() = user_id);

drop policy if exists "wcn delete own" on public.whisper_calendar_notes;
create policy "wcn delete own" on public.whisper_calendar_notes
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 2. Recruiter prospect pipeline — track scouting leads before promoting
-- ---------------------------------------------------------------------------
create type public.whisper_prospect_status as enum (
  'discovered','contacted','interested','meeting','ready','passed'
);

create table if not exists public.whisper_recruiter_prospects (
  id uuid primary key default gen_random_uuid(),
  recruiter_id uuid not null references auth.users(id) on delete cascade,
  -- The prospect may or may not have a Whisper account yet
  prospect_user_id uuid references auth.users(id) on delete set null,
  prospect_username text,
  prospect_display_name text,
  prospect_image_url text,
  -- Where the recruiter found them
  source text,
  -- City / region where the prospect is
  location text,
  -- Sport or niche (e.g. "Powerlifting", "Bodybuilding", "Running")
  niche text,
  -- Social media handles
  instagram text,
  tiktok text,
  -- What role the recruiter thinks they'd be good for
  suggested_role text check (suggested_role in ('coach','athlete','creator')),
  status public.whisper_prospect_status not null default 'discovered',
  -- Free-form scouting notes
  notes text,
  -- Star rating 1-5 for internal ranking
  rating integer check (rating >= 1 and rating <= 5),
  -- Contact log: array of {date, method, note} — stored as jsonb
  contact_log jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(recruiter_id, prospect_username)
);

alter table public.whisper_recruiter_prospects enable row level security;

drop policy if exists "wrp_recruiter read own" on public.whisper_recruiter_prospects;
create policy "wrp_recruiter read own" on public.whisper_recruiter_prospects
  for select using (auth.uid() = recruiter_id);

drop policy if exists "wrp_recruiter insert own" on public.whisper_recruiter_prospects;
create policy "wrp_recruiter insert own" on public.whisper_recruiter_prospects
  for insert with check (auth.uid() = recruiter_id);

drop policy if exists "wrp_recruiter update own" on public.whisper_recruiter_prospects;
create policy "wrp_recruiter update own" on public.whisper_recruiter_prospects
  for update using (auth.uid() = recruiter_id);

drop policy if exists "wrp_recruiter delete own" on public.whisper_recruiter_prospects;
create policy "wrp_recruiter delete own" on public.whisper_recruiter_prospects
  for delete using (auth.uid() = recruiter_id);

-- Index for recruiter's pipeline list
create index if not exists idx_prospects_recruiter
  on public.whisper_recruiter_prospects (recruiter_id, updated_at desc);
