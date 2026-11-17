-- ─────────────────────────────────────────────────────────────────────────────
-- Jasper Brain — ONE shared intelligence config for iOS + web Jasper.
--
-- Admins and the owner edit the sections at /jasper-brain on the website;
-- BOTH apps fold the composed block into every Jasper system prompt (chat,
-- meetings, helpers) with a 5-minute client cache. Empty sections change
-- nothing, so Jasper behaves exactly as before until the team writes rules.
--
-- Run once in the Supabase SQL editor.
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.jasper_brain (
  section text primary key,
  title text not null default '',
  content text not null default '',
  updated_by text,
  updated_at timestamptz not null default now()
);

alter table public.jasper_brain enable row level security;

-- Everyone (both apps, signed in or not) can READ the rules — they contain
-- product voice guidance, never secrets.
drop policy if exists "jasper brain readable" on public.jasper_brain;
create policy "jasper brain readable" on public.jasper_brain
  for select using (true);

-- Only admins / the owner can WRITE (profiles.id = auth.uid() carries the
-- badge flags, kept in sync by the whisper_admins trigger).
drop policy if exists "jasper brain admin write" on public.jasper_brain;
create policy "jasper brain admin write" on public.jasper_brain
  for all
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (coalesce(p.is_admin, false) or coalesce(p.is_owner, false))
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (coalesce(p.is_admin, false) or coalesce(p.is_owner, false))
    )
  );

-- Seed the four sections EMPTY — inert until the team writes something.
insert into public.jasper_brain (section, title, content) values
  ('voice',      'Voice & grammar',   ''),
  ('formatting', 'Formatting & cards', ''),
  ('knowledge',  'Whisper knowledge',  ''),
  ('guardrails', 'Guardrails',         '')
on conflict (section) do nothing;
