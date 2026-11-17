-- =============================================================================
-- Coach payments — Stripe Connect Express
--
-- Run this in Supabase → SQL Editor. Creates the three tables behind
-- coach self-pricing, the earnings ledger, and bank-account (Connect) links.
-- All writes come from the Cloudflare backend using the service-role key;
-- coaches can only READ their own rows from the web/app.
-- =============================================================================

-- 1) Connected Stripe accounts (one per coach)
create table if not exists public.whisper_coach_connect (
  user_id uuid primary key references auth.users (id) on delete cascade,
  stripe_account_id text not null,
  charges_enabled boolean not null default false,
  payouts_enabled boolean not null default false,
  details_submitted boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.whisper_coach_connect enable row level security;

drop policy if exists "coach reads own connect row" on public.whisper_coach_connect;
create policy "coach reads own connect row"
  on public.whisper_coach_connect for select
  using (auth.uid() = user_id);

-- 2) Coach pricing (the rate a coach charges clients per month)
create table if not exists public.whisper_coach_pricing (
  user_id uuid primary key references auth.users (id) on delete cascade,
  monthly_price_cents integer not null check (monthly_price_cents between 500 and 200000),
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.whisper_coach_pricing enable row level security;

-- Pricing is public so hire pages can show the rate.
drop policy if exists "pricing is readable" on public.whisper_coach_pricing;
create policy "pricing is readable"
  on public.whisper_coach_pricing for select
  using (true);

-- 3) Earnings ledger (one row per successful client payment)
create table if not exists public.whisper_coach_earnings (
  id bigint generated always as identity primary key,
  coach_user_id uuid not null references auth.users (id) on delete cascade,
  client_user_id uuid,
  client_email text,
  gross_cents integer not null default 0,
  fee_cents integer not null default 0,
  net_cents integer not null default 0,
  description text,
  stripe_session_id text unique,
  created_at timestamptz not null default now()
);

create index if not exists whisper_coach_earnings_coach_idx
  on public.whisper_coach_earnings (coach_user_id, created_at desc);

alter table public.whisper_coach_earnings enable row level security;

drop policy if exists "coach reads own earnings" on public.whisper_coach_earnings;
create policy "coach reads own earnings"
  on public.whisper_coach_earnings for select
  using (auth.uid() = coach_user_id);

-- No insert/update/delete policies on purpose: only the backend
-- (service role) writes to these tables.
