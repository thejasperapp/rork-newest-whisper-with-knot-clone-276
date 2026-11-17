-- Speed dating — saved dating cards (Round 74).
-- The card (what I'm looking for, interests, non-negotiables, ideal first
-- date, fun fact) travels over the meeting wire during speed dates; this
-- table makes it durable across devices. Self-only RLS: nobody reads
-- another person's card from the database — sharing happens live in the
-- room, on the wire, by choice.

create table if not exists public.whisper_dating_cards (
  user_id uuid primary key references auth.users(id) on delete cascade,
  answers jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.whisper_dating_cards enable row level security;

drop policy if exists "dating_cards_select_self" on public.whisper_dating_cards;
create policy "dating_cards_select_self"
  on public.whisper_dating_cards for select
  using (auth.uid() = user_id);

drop policy if exists "dating_cards_insert_self" on public.whisper_dating_cards;
create policy "dating_cards_insert_self"
  on public.whisper_dating_cards for insert
  with check (auth.uid() = user_id);

drop policy if exists "dating_cards_update_self" on public.whisper_dating_cards;
create policy "dating_cards_update_self"
  on public.whisper_dating_cards for update
  using (auth.uid() = user_id);

drop policy if exists "dating_cards_delete_self" on public.whisper_dating_cards;
create policy "dating_cards_delete_self"
  on public.whisper_dating_cards for delete
  using (auth.uid() = user_id);
