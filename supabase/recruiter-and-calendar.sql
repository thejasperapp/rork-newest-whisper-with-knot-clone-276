-- ============================================================================
-- Talent Recruiter role + Shared Calendar tables
-- (run once in the Supabase SQL editor — safe to re-run)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Recruiter flag on profiles + recruiter applications table
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists is_recruiter boolean not null default false;
alter table public.whisper_profiles add column if not exists is_recruiter boolean not null default false;

create table if not exists public.whisper_recruiter_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  username text not null,
  email text,
  full_name text not null default '',
  region text,
  experience text,
  bio text,
  social text,
  status public.whisper_application_status not null default 'pending',
  created_at timestamptz not null default now()
);

alter table public.whisper_recruiter_applications enable row level security;

drop policy if exists "wra insert own" on public.whisper_recruiter_applications;
create policy "wra insert own" on public.whisper_recruiter_applications
  for insert with check (auth.uid() = user_id);
drop policy if exists "wra read own" on public.whisper_recruiter_applications;
create policy "wra read own" on public.whisper_recruiter_applications
  for select using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 1. Recruiter promotions log — tracks who a recruiter has promoted
-- ---------------------------------------------------------------------------
create table if not exists public.whisper_recruiter_promotions (
  id uuid primary key default gen_random_uuid(),
  recruiter_id uuid not null references auth.users(id) on delete cascade,
  recruiter_username text,
  promoted_id uuid not null references auth.users(id) on delete cascade,
  promoted_username text not null,
  role text not null check (role in ('coach','athlete','creator')),
  notes text,
  created_at timestamptz not null default now(),
  unique(promoted_id, role)
);

alter table public.whisper_recruiter_promotions enable row level security;

drop policy if exists "wrp recruiter read" on public.whisper_recruiter_promotions;
create policy "wrp recruiter read" on public.whisper_recruiter_promotions
  for select using (auth.uid() = recruiter_id or auth.uid() = promoted_id);

drop policy if exists "wrp recruiter insert" on public.whisper_recruiter_promotions;
create policy "wrp recruiter insert" on public.whisper_recruiter_promotions
  for insert with check (auth.uid() = recruiter_id);

drop policy if exists "wrp recruiter delete" on public.whisper_recruiter_promotions;
create policy "wrp recruiter delete" on public.whisper_recruiter_promotions
  for delete using (auth.uid() = recruiter_id);

-- ---------------------------------------------------------------------------
-- 2. Shared Calendar — events for badged role users
-- ---------------------------------------------------------------------------
create type public.whisper_calendar_event_type as enum (
  'meet','content_collab','training','event','deadline','other'
);

create table if not exists public.whisper_calendar_events (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_by_username text,
  title text not null,
  description text,
  event_type public.whisper_calendar_event_type not null default 'meet',
  start_time timestamptz not null,
  end_time timestamptz,
  location text,
  -- Tagged users (array of user IDs)
  tagged_user_ids uuid[] not null default '{}',
  -- Tagged usernames for display
  tagged_usernames text[] not null default '{}',
  created_at timestamptz not null default now()
);

alter table public.whisper_calendar_events enable row level security;

-- Any authenticated user can see calendar events (it's a shared calendar
-- for badged role users, but visibility is open to all authenticated users).
drop policy if exists "wce select all" on public.whisper_calendar_events;
create policy "wce select all" on public.whisper_calendar_events
  for select using (true);

drop policy if exists "wce insert own" on public.whisper_calendar_events;
create policy "wce insert own" on public.whisper_calendar_events
  for insert with check (auth.uid() = created_by);

drop policy if exists "wce update own" on public.whisper_calendar_events;
create policy "wce update own" on public.whisper_calendar_events
  for update using (auth.uid() = created_by);

drop policy if exists "wce delete own" on public.whisper_calendar_events;
create policy "wce delete own" on public.whisper_calendar_events
  for delete using (auth.uid() = created_by);

-- ---------------------------------------------------------------------------
-- 3. Calendar RSVPs — who is attending
-- ---------------------------------------------------------------------------
create table if not exists public.whisper_calendar_rsvps (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.whisper_calendar_events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  username text,
  status text not null check (status in ('going','maybe','declined')),
  created_at timestamptz not null default now(),
  unique(event_id, user_id)
);

alter table public.whisper_calendar_rsvps enable row level security;

drop policy if exists "wcr select all" on public.whisper_calendar_rsvps;
create policy "wcr select all" on public.whisper_calendar_rsvps
  for select using (true);

drop policy if exists "wcr insert own" on public.whisper_calendar_rsvps;
create policy "wcr insert own" on public.whisper_calendar_rsvps
  for insert with check (auth.uid() = user_id);

drop policy if exists "wcr update own" on public.whisper_calendar_rsvps;
create policy "wcr update own" on public.whisper_calendar_rsvps
  for update using (auth.uid() = user_id);

drop policy if exists "wcr delete own" on public.whisper_calendar_rsvps;
create policy "wcr delete own" on public.whisper_calendar_rsvps
  for delete using (auth.uid() = user_id);
