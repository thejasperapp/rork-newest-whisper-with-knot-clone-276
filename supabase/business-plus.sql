-- Whisper Business+ — team roles, hiring with auto-match, private HQ,
-- group chats in DMs, and the internal team calendar.
-- Run once in the Supabase SQL editor. Safe to re-run.

-- ── 1. The plan ledger (written by the Stripe webhook) ─────────────────────
create table if not exists public.whisper_business_plus (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  email text,
  plan text not null default 'business-plus-monthly',
  status text not null default 'active',
  company_name text,
  stripe_customer_id text,
  stripe_subscription_id text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists whisper_business_plus_user_idx
  on public.whisper_business_plus (user_id);

alter table public.whisper_business_plus enable row level security;

-- Team membership check without policy recursion.
create or replace function public.whisper_is_business_member(business uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.whisper_business_team
    where business_id = business
      and user_id = auth.uid()
  );
$$;

drop policy if exists "business plus read" on public.whisper_business_plus;
create policy "business plus read" on public.whisper_business_plus
  for select using (
    user_id = auth.uid()
    or public.whisper_is_business_member(user_id)
  );

-- The owner may name their company (webhook writes ride the service role).
drop policy if exists "business plus owner update" on public.whisper_business_plus;
create policy "business plus owner update" on public.whisper_business_plus
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ── 2. Team roles ───────────────────────────────────────────────────────────
create table if not exists public.whisper_business_team (
  business_id uuid not null,            -- the owner's user_id
  user_id uuid not null,
  username text not null default '',
  role_title text not null default 'Team member',
  accent text not null default '#5A5FE8',
  added_at timestamptz not null default now(),
  primary key (business_id, user_id)
);

alter table public.whisper_business_team enable row level security;

drop policy if exists "team read" on public.whisper_business_team;
create policy "team read" on public.whisper_business_team
  for select using (
    business_id = auth.uid()
    or user_id = auth.uid()
    or public.whisper_is_business_member(business_id)
  );

drop policy if exists "team owner insert" on public.whisper_business_team;
create policy "team owner insert" on public.whisper_business_team
  for insert with check (business_id = auth.uid());

drop policy if exists "team owner update" on public.whisper_business_team;
create policy "team owner update" on public.whisper_business_team
  for update using (business_id = auth.uid())
  with check (business_id = auth.uid());

drop policy if exists "team owner or self delete" on public.whisper_business_team;
create policy "team owner or self delete" on public.whisper_business_team
  for delete using (business_id = auth.uid() or user_id = auth.uid());

-- ── 3. Open positions (public read powers the apply page + auto-match) ─────
create table if not exists public.whisper_business_positions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  title text not null,
  blurb text not null default '',
  keywords text[] not null default '{}',
  is_open boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists whisper_business_positions_biz_idx
  on public.whisper_business_positions (business_id);

alter table public.whisper_business_positions enable row level security;

drop policy if exists "positions public read" on public.whisper_business_positions;
create policy "positions public read" on public.whisper_business_positions
  for select using (true);

drop policy if exists "positions owner write" on public.whisper_business_positions;
create policy "positions owner write" on public.whisper_business_positions
  for all using (business_id = auth.uid())
  with check (business_id = auth.uid());

-- ── 4. Custom application questions ────────────────────────────────────────
create table if not exists public.whisper_business_questions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  prompt text not null,
  kind text not null default 'text',        -- 'text' | 'textarea' | 'select'
  options text[] not null default '{}',
  display_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists whisper_business_questions_biz_idx
  on public.whisper_business_questions (business_id);

alter table public.whisper_business_questions enable row level security;

drop policy if exists "questions public read" on public.whisper_business_questions;
create policy "questions public read" on public.whisper_business_questions
  for select using (true);

drop policy if exists "questions owner write" on public.whisper_business_questions;
create policy "questions owner write" on public.whisper_business_questions
  for all using (business_id = auth.uid())
  with check (business_id = auth.uid());

-- ── 5. Applications (answers + auto-match scores) ──────────────────────────
create table if not exists public.whisper_business_applications (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  applicant_id uuid not null,
  applicant_username text not null default '',
  answers jsonb not null default '[]',
  best_position text,
  position_scores jsonb not null default '{}',
  match_score int not null default 0,
  status text not null default 'new',       -- 'new' | 'shortlist' | 'passed'
  created_at timestamptz not null default now()
);
create index if not exists whisper_business_applications_biz_idx
  on public.whisper_business_applications (business_id);

alter table public.whisper_business_applications enable row level security;

drop policy if exists "applications insert self" on public.whisper_business_applications;
create policy "applications insert self" on public.whisper_business_applications
  for insert with check (applicant_id = auth.uid());

drop policy if exists "applications read own or business" on public.whisper_business_applications;
create policy "applications read own or business" on public.whisper_business_applications
  for select using (
    applicant_id = auth.uid()
    or business_id = auth.uid()
    or public.whisper_is_business_member(business_id)
  );

drop policy if exists "applications business update" on public.whisper_business_applications;
create policy "applications business update" on public.whisper_business_applications
  for update using (business_id = auth.uid())
  with check (business_id = auth.uid());

-- ── 6. Group chats in DMs (registry; messages ride whisper_messages) ───────
create table if not exists public.whisper_group_threads (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null,
  member_ids uuid[] not null default '{}',
  member_usernames text[] not null default '{}',
  business_id uuid,
  created_at timestamptz not null default now()
);

alter table public.whisper_group_threads enable row level security;

drop policy if exists "group threads read" on public.whisper_group_threads;
create policy "group threads read" on public.whisper_group_threads
  for select using (
    owner_id = auth.uid()
    or auth.uid() = any(member_ids)
  );

drop policy if exists "group threads insert" on public.whisper_group_threads;
create policy "group threads insert" on public.whisper_group_threads
  for insert with check (owner_id = auth.uid());

drop policy if exists "group threads owner update" on public.whisper_group_threads;
create policy "group threads owner update" on public.whisper_group_threads
  for update using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists "group threads owner delete" on public.whisper_group_threads;
create policy "group threads owner delete" on public.whisper_group_threads
  for delete using (owner_id = auth.uid());

-- ── 7. Internal team calendar ───────────────────────────────────────────────
alter table public.whisper_calendar_events
  add column if not exists business_id uuid;
create index if not exists whisper_calendar_events_business_idx
  on public.whisper_calendar_events (business_id)
  where business_id is not null;
