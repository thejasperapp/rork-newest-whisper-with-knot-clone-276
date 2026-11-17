-- ============================================================================
-- Recruitment targets + referral codes
-- (run once in the Supabase SQL editor — safe to re-run)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Recruitment targets — monthly goals per role, tracked by recruiters
-- ---------------------------------------------------------------------------
create table if not exists public.whisper_recruiter_targets (
  id uuid primary key default gen_random_uuid(),
  recruiter_id uuid not null references auth.users(id) on delete cascade,
  -- "2026-07" format
  period text not null,
  -- How many of each role they aim to recruit this month
  target_coach integer not null default 0,
  target_athlete integer not null default 0,
  target_creator integer not null default 0,
  -- Notes / focus area for this month
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(recruiter_id, period)
);

alter table public.whisper_recruiter_targets enable row level security;

drop policy if exists "wrt read own" on public.whisper_recruiter_targets;
create policy "wrt read own" on public.whisper_recruiter_targets
  for select using (auth.uid() = recruiter_id);

drop policy if exists "wrt insert own" on public.whisper_recruiter_targets;
create policy "wrt insert own" on public.whisper_recruiter_targets
  for insert with check (auth.uid() = recruiter_id);

drop policy if exists "wrt update own" on public.whisper_recruiter_targets;
create policy "wrt update own" on public.whisper_recruiter_targets
  for update using (auth.uid() = recruiter_id);

drop policy if exists "wrt delete own" on public.whisper_recruiter_targets;
create policy "wrt delete own" on public.whisper_recruiter_targets
  for delete using (auth.uid() = recruiter_id);

-- ---------------------------------------------------------------------------
-- 2. Referral codes — each recruiter gets a shareable code
-- ---------------------------------------------------------------------------
create table if not exists public.whisper_referral_codes (
  id uuid primary key default gen_random_uuid(),
  recruiter_id uuid not null unique references auth.users(id) on delete cascade,
  code text not null unique,
  -- How many times this code has been used (incremented by app when a prospect signs up)
  uses integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.whisper_referral_codes enable row level security;

drop policy if exists "wrc read all" on public.whisper_referral_codes;
create policy "wrc read all" on public.whisper_referral_codes
  for select using (true);

drop policy if exists "wrc insert own" on public.whisper_referral_codes;
create policy "wrc insert own" on public.whisper_referral_codes
  for insert with check (auth.uid() = recruiter_id);

drop policy if exists "wrc update own" on public.whisper_referral_codes;
create policy "wrc update own" on public.whisper_referral_codes
  for update using (auth.uid() = recruiter_id);

-- Index for lookups
create index if not exists idx_referral_code on public.whisper_referral_codes (code);
create index if not exists idx_referral_recruiter on public.whisper_referral_codes (recruiter_id);
