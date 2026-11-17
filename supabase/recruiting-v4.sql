-- ============================================================================
-- Recruiting OS v4 — the researched talent-CRM upgrade:
--   · next-action discipline (every active person carries a next step + due)
--   · tags for talent pools
--   · structured scorecards (talent / drive / coachability / audience, 1–5)
--   · a real activity timeline table (stage moves, calls, DMs, notes…)
-- Statuses are unchanged (discovered/contacted/interested/meeting/ready/
-- passed); "signed" stays evidenced by whisper_recruiter_promotions.
-- Run once in the Supabase SQL editor — safe to re-run.
-- ============================================================================

alter table public.whisper_recruiter_prospects
  add column if not exists tags text[] not null default '{}';
alter table public.whisper_recruiter_prospects
  add column if not exists next_action text;
alter table public.whisper_recruiter_prospects
  add column if not exists next_action_due date;
alter table public.whisper_recruiter_prospects
  add column if not exists last_touch_at timestamptz;
alter table public.whisper_recruiter_prospects
  add column if not exists scorecard jsonb not null default '{}'::jsonb;

create index if not exists idx_prospects_next_due
  on public.whisper_recruiter_prospects (recruiter_id, next_action_due)
  where next_action_due is not null;

-- ---------------------------------------------------------------------------
-- Activity timeline — one row per touchpoint, auto-logged stage moves
-- included. The old contact_log jsonb keeps working; the UI merges both.
-- ---------------------------------------------------------------------------
create table if not exists public.whisper_prospect_activities (
  id uuid primary key default gen_random_uuid(),
  prospect_id uuid not null references public.whisper_recruiter_prospects(id) on delete cascade,
  recruiter_id uuid not null references auth.users(id) on delete cascade,
  kind text not null default 'note'
    check (kind in ('note','call','dm','email','meeting','stage','task')),
  body text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists idx_prospect_activities_prospect
  on public.whisper_prospect_activities (prospect_id, created_at desc);
create index if not exists idx_prospect_activities_recruiter
  on public.whisper_prospect_activities (recruiter_id, created_at desc);

alter table public.whisper_prospect_activities enable row level security;

drop policy if exists "wpa_select_own" on public.whisper_prospect_activities;
create policy "wpa_select_own" on public.whisper_prospect_activities
  for select using (auth.uid() = recruiter_id);

drop policy if exists "wpa_insert_own" on public.whisper_prospect_activities;
create policy "wpa_insert_own" on public.whisper_prospect_activities
  for insert with check (auth.uid() = recruiter_id);

drop policy if exists "wpa_delete_own" on public.whisper_prospect_activities;
create policy "wpa_delete_own" on public.whisper_prospect_activities
  for delete using (auth.uid() = recruiter_id);
