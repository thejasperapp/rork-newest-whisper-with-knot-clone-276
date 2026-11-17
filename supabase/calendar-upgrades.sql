-- Calendar upgrades: recurring events, reminder tracking, and recruiter territories.
-- Run this in the Supabase SQL editor.

-- 1. Recurring events — each occurrence is a real row sharing a recurrence_group
alter table public.whisper_calendar_events
  add column if not exists recurrence text not null default 'none',
  add column if not exists recurrence_group uuid;

create index if not exists whisper_calendar_events_recurrence_group_idx
  on public.whisper_calendar_events (recurrence_group);

-- 2. Reminder tracking — one row per event once the 15-minute push has gone out
create table if not exists public.whisper_calendar_reminders_sent (
  event_id uuid primary key references public.whisper_calendar_events (id) on delete cascade,
  sent_at timestamptz not null default now()
);

alter table public.whisper_calendar_reminders_sent enable row level security;

-- Only the service role (edge function) writes here; no client policies needed.

-- 3. Recruiter territories — regions a recruiter covers, shown on the territory map
create table if not exists public.whisper_recruiter_territories (
  id uuid primary key default gen_random_uuid(),
  recruiter_id text not null,
  name text not null,
  region text not null default 'other',
  cities text,
  notes text,
  color text,
  created_at timestamptz not null default now()
);

create index if not exists whisper_recruiter_territories_recruiter_idx
  on public.whisper_recruiter_territories (recruiter_id);

alter table public.whisper_recruiter_territories enable row level security;

drop policy if exists "territories readable" on public.whisper_recruiter_territories;
create policy "territories readable"
  on public.whisper_recruiter_territories for select
  using (true);

drop policy if exists "territories insert own" on public.whisper_recruiter_territories;
create policy "territories insert own"
  on public.whisper_recruiter_territories for insert
  with check (true);

drop policy if exists "territories update own" on public.whisper_recruiter_territories;
create policy "territories update own"
  on public.whisper_recruiter_territories for update
  using (true);

drop policy if exists "territories delete own" on public.whisper_recruiter_territories;
create policy "territories delete own"
  on public.whisper_recruiter_territories for delete
  using (true);

-- 4. Schedule the reminder edge function (requires pg_cron + pg_net enabled).
-- Replace YOUR_PROJECT_REF and YOUR_SERVICE_ROLE_KEY, then uncomment:
--
-- select cron.schedule(
--   'whisper-calendar-reminders',
--   '* * * * *',
--   $$
--   select net.http_post(
--     url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/whisper-calendar-reminders',
--     headers := '{"Authorization": "Bearer YOUR_SERVICE_ROLE_KEY", "Content-Type": "application/json"}'::jsonb,
--     body := '{}'::jsonb
--   );
--   $$
-- );
