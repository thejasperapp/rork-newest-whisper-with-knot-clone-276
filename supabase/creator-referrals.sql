-- ============================================================================
-- Creator links & codes — every user gets a shareable invite code, and
-- signups that arrive through a code are credited to the code's owner.
-- (run once in the Supabase SQL editor — safe to re-run)
--
-- Builds on `whisper_referral_codes` from recruiter-targets-and-referrals.sql.
-- If that file hasn't been run yet, this one creates the codes table too.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Codes table (idempotent copy so this file stands alone)
-- ---------------------------------------------------------------------------
create table if not exists public.whisper_referral_codes (
  id uuid primary key default gen_random_uuid(),
  recruiter_id uuid not null unique references auth.users(id) on delete cascade,
  code text not null unique,
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

create index if not exists idx_referral_code on public.whisper_referral_codes (code);
create index if not exists idx_referral_recruiter on public.whisper_referral_codes (recruiter_id);

-- ---------------------------------------------------------------------------
-- 2. Signups credited to a code. One row per NEW user (a user can only be
--    referred once), written by the backend with the service role.
-- ---------------------------------------------------------------------------
create table if not exists public.whisper_referral_signups (
  id uuid primary key default gen_random_uuid(),
  code_id uuid not null references public.whisper_referral_codes(id) on delete cascade,
  recruiter_id uuid not null references auth.users(id) on delete cascade,
  new_user_id uuid not null unique references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.whisper_referral_signups enable row level security;

-- Owners can see who signed up with their code.
drop policy if exists "wrs read own" on public.whisper_referral_signups;
create policy "wrs read own" on public.whisper_referral_signups
  for select using (auth.uid() = recruiter_id or auth.uid() = new_user_id);

-- Inserts happen through the backend (service role bypasses RLS); no
-- client-side insert policy on purpose so counters can't be gamed.

create index if not exists idx_referral_signups_recruiter
  on public.whisper_referral_signups (recruiter_id, created_at desc);
