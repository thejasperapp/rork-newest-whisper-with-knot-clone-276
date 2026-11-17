-- ─────────────────────────────────────────────────────────────────────────
-- Whisper meeting backdrops — the shared library of Jasper-generated
-- virtual backgrounds. One row per generated backdrop; the same list
-- appears in the web meeting Backgrounds sheet AND the iOS effects sheet,
-- so a backdrop painted on one device is instantly available on the other.
--
-- Run once in the Supabase SQL editor. Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.whisper_meeting_backdrops (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  url text not null,
  prompt text,
  created_at timestamptz not null default now()
);

create index if not exists whisper_meeting_backdrops_user_idx
  on public.whisper_meeting_backdrops (user_id, created_at desc);

alter table public.whisper_meeting_backdrops enable row level security;

do $$ begin
  create policy "backdrops owner select" on public.whisper_meeting_backdrops
    for select to authenticated using (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "backdrops owner insert" on public.whisper_meeting_backdrops
    for insert to authenticated with check (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "backdrops owner delete" on public.whisper_meeting_backdrops
    for delete to authenticated using (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

-- Storage bucket for the actual images (web generations arrive as data
-- URLs and need a hosted home so iOS can load them).
insert into storage.buckets (id, name, public)
values ('meeting-backdrops', 'meeting-backdrops', true)
on conflict (id) do nothing;

do $$ begin
  create policy "meeting backdrops public read" on storage.objects
    for select using (bucket_id = 'meeting-backdrops');
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "meeting backdrops owner upload" on storage.objects
    for insert to authenticated
    with check (
      bucket_id = 'meeting-backdrops'
      and (storage.foldername(name))[1] = auth.uid()::text
    );
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "meeting backdrops owner delete" on storage.objects
    for delete to authenticated
    using (
      bucket_id = 'meeting-backdrops'
      and (storage.foldername(name))[1] = auth.uid()::text
    );
exception when duplicate_object then null; end $$;
