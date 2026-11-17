-- ============================================================================
-- Whisper Notebook — per-user preferences over meeting notes:
-- favorites (pin to top) + custom titles (rename), without ever touching
-- the shared whisper_meetings rows.
-- Run once in the Supabase SQL editor — safe to re-run.
-- ============================================================================

create table if not exists public.whisper_notebook_prefs (
  user_id uuid not null references auth.users(id) on delete cascade,
  meeting_id uuid not null references public.whisper_meetings(id) on delete cascade,
  custom_title text,
  is_favorite boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, meeting_id)
);

create index if not exists whisper_notebook_prefs_user_idx
  on public.whisper_notebook_prefs (user_id, is_favorite desc, updated_at desc);

alter table public.whisper_notebook_prefs enable row level security;

drop policy if exists "wnp_select_own" on public.whisper_notebook_prefs;
create policy "wnp_select_own" on public.whisper_notebook_prefs
  for select using (auth.uid() = user_id);

drop policy if exists "wnp_insert_own" on public.whisper_notebook_prefs;
create policy "wnp_insert_own" on public.whisper_notebook_prefs
  for insert with check (auth.uid() = user_id);

drop policy if exists "wnp_update_own" on public.whisper_notebook_prefs;
create policy "wnp_update_own" on public.whisper_notebook_prefs
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "wnp_delete_own" on public.whisper_notebook_prefs;
create policy "wnp_delete_own" on public.whisper_notebook_prefs
  for delete using (auth.uid() = user_id);
