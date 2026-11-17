-- ============================================================================
-- Jasper pitch decks — the recruiter's close plan built from a meeting
-- transcript. One deck per (meeting, recruiter); the deck itself is the
-- shared JSON shape both apps read (web lib/pitchDeck.ts · iOS
-- WhisperPitchDeck.swift). Decks also cache locally on each device, so the
-- feature works before this runs — this table makes decks durable and
-- cross-device. Run once in the Supabase SQL editor — safe to re-run.
-- ============================================================================

create table if not exists public.whisper_meeting_decks (
  meeting_id uuid not null references public.whisper_meetings(id) on delete cascade,
  recruiter_id uuid not null references auth.users(id) on delete cascade,
  prospect_name text,
  deck jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (meeting_id, recruiter_id)
);

create index if not exists whisper_meeting_decks_recruiter_idx
  on public.whisper_meeting_decks (recruiter_id, updated_at desc);

alter table public.whisper_meeting_decks enable row level security;

-- Decks are the recruiter's private working notes — owner-only everything.
drop policy if exists "wmd_select_own" on public.whisper_meeting_decks;
create policy "wmd_select_own" on public.whisper_meeting_decks
  for select using (auth.uid() = recruiter_id);

drop policy if exists "wmd_insert_own" on public.whisper_meeting_decks;
create policy "wmd_insert_own" on public.whisper_meeting_decks
  for insert with check (auth.uid() = recruiter_id);

drop policy if exists "wmd_update_own" on public.whisper_meeting_decks;
create policy "wmd_update_own" on public.whisper_meeting_decks
  for update using (auth.uid() = recruiter_id) with check (auth.uid() = recruiter_id);

drop policy if exists "wmd_delete_own" on public.whisper_meeting_decks;
create policy "wmd_delete_own" on public.whisper_meeting_decks
  for delete using (auth.uid() = recruiter_id);
