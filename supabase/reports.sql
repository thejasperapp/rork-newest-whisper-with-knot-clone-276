-- In-app problem reports — apply once in the Supabase SQL Editor (idempotent).
--
-- Settings → "Report a problem" (iOS) writes here instead of opening an email.
-- Reports ABOUT a person keep riding whisper_dating_report (dating-v2.sql);
-- this table is for bugs, content, account, payment, safety, and "other".
--
--   * whisper_reports          — one row per report (self-readable; staff read
--                                via the dashboard/service role)
--   * whisper_submit_report()  — the only write path (security definer)

create table if not exists public.whisper_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  kind text not null default 'problem',      -- bug | content | account | payment | safety | other
  target_username text,
  target_id text,
  reason text not null,
  details text,
  context jsonb not null default '{}'::jsonb, -- app/os/device when the user opts in
  status text not null default 'open',       -- open | reviewing | resolved | dismissed
  created_at timestamptz not null default now()
);

create index if not exists whisper_reports_status_idx
  on public.whisper_reports (status, created_at desc);
create index if not exists whisper_reports_reporter_idx
  on public.whisper_reports (reporter_id, created_at desc);

alter table public.whisper_reports enable row level security;

drop policy if exists "reports_select_self" on public.whisper_reports;
create policy "reports_select_self" on public.whisper_reports
  for select using (auth.uid() = reporter_id);

-- No direct insert/update policies: every write goes through the function.

create or replace function public.whisper_submit_report(
  p_kind text,
  p_reason text,
  p_details text default null,
  p_target_username text default null,
  p_target_id text default null,
  p_context jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  rid uuid;
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  insert into public.whisper_reports (reporter_id, kind, target_username, target_id, reason, details, context)
  values (
    me,
    coalesce(nullif(trim(coalesce(p_kind, '')), ''), 'problem'),
    nullif(lower(trim(coalesce(p_target_username, ''))), ''),
    nullif(trim(coalesce(p_target_id, '')), ''),
    coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'other'),
    nullif(left(trim(coalesce(p_details, '')), 4000), ''),
    coalesce(p_context, '{}'::jsonb)
  )
  returning id into rid;
  return rid;
end $$;

grant execute on function public.whisper_submit_report(text, text, text, text, text, jsonb) to authenticated;
