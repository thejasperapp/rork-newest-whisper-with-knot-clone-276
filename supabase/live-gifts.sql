-- Live gifts — Phase 2 of the live system: gifts on the wallet rails +
-- per-session analytics support.
--   • whisper_gift_wallets   — prepaid gift-credit balance per user
--                              (service-role writes only; owner reads).
--   • whisper_gift_topups    — Stripe checkout credits, deduped by the
--                              unique session id (strict insert = the
--                              webhook can never double-credit).
--   • whisper_live_gifts     — every gift sent in a live room (public
--                              read like live chat, realtime for the
--                              on-screen banners; service-role insert).
--   • whisper_gift_cashouts  — host cash-out ledger (same Stripe rail
--                              as WPP / coach payouts).
-- Safe to re-run.

create table if not exists public.whisper_gift_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance_cents integer not null default 0 check (balance_cents >= 0),
  updated_at timestamptz not null default now()
);

alter table public.whisper_gift_wallets enable row level security;

drop policy if exists "gift_wallet_own_read" on public.whisper_gift_wallets;
create policy "gift_wallet_own_read" on public.whisper_gift_wallets
  for select using (auth.uid() = user_id);
-- No insert/update/delete policies: the backend's service role is the
-- only writer (compare-and-swap balance updates).

create table if not exists public.whisper_gift_topups (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_cents integer not null,
  stripe_session_id text unique,
  created_at timestamptz not null default now()
);

alter table public.whisper_gift_topups enable row level security;

drop policy if exists "gift_topups_own_read" on public.whisper_gift_topups;
create policy "gift_topups_own_read" on public.whisper_gift_topups
  for select using (auth.uid() = user_id);

create table if not exists public.whisper_live_gifts (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null,
  host_id uuid not null,
  sender_id uuid not null,
  sender_username text,
  gift_id text not null,
  gift_label text not null,
  gift_emoji text not null,
  qty integer not null default 1 check (qty between 1 and 100),
  amount_cents integer not null,
  net_cents integer not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_live_gifts_room
  on public.whisper_live_gifts(room_id, created_at desc);
create index if not exists idx_live_gifts_host
  on public.whisper_live_gifts(host_id, created_at desc);

alter table public.whisper_live_gifts enable row level security;

drop policy if exists "live_gifts_public_read" on public.whisper_live_gifts;
create policy "live_gifts_public_read" on public.whisper_live_gifts
  for select using (true);
-- Inserts are service-role only — the backend validates the room, the
-- catalog price, and the sender's balance before writing.

-- Realtime for the on-screen gift banners.
do $$
begin
  alter publication supabase_realtime add table public.whisper_live_gifts;
exception
  when duplicate_object then null;
end $$;

create table if not exists public.whisper_gift_cashouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_cents integer not null,
  created_at timestamptz not null default now()
);

alter table public.whisper_gift_cashouts enable row level security;

drop policy if exists "gift_cashouts_own_read" on public.whisper_gift_cashouts;
create policy "gift_cashouts_own_read" on public.whisper_gift_cashouts
  for select using (auth.uid() = user_id);
