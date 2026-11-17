-- Brand accounts + creator sponsorship pipeline.
-- Run this in the Supabase SQL editor.
--
-- Tables:
--   whisper_brand_profiles           — one row per brand account (signup form)
--   whisper_sponsorship_applications — creator → brand sponsorship requests
--   whisper_sponsorship_deals        — accepted applications become deals
--   whisper_sponsorship_posts        — creator posts tracked against a deal
--   whisper_sponsorship_payments     — escrow ledger (pending until obligations met)
--   whisper_dm_blocks                — denied brands can't DM the creator

create table if not exists public.whisper_brand_profiles (
  user_id uuid primary key,
  company_name text not null,
  username text,
  website text,
  industry text,
  about text,
  logo_url text,
  -- Amenities the brand wants (analytics, creator discovery, etc.)
  amenities text[] not null default '{}',
  -- Sponsorship requirements — gate who can apply.
  min_followers integer not null default 0,
  min_age integer not null default 18,
  min_posts integer not null default 0,
  -- Payment transparency — what this brand typically pays.
  pay_basis text not null default 'per_post', -- per_post | per_month | per_year
  typical_pay_min_cents integer,
  typical_pay_max_cents integer,
  payment_terms text,
  published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.whisper_brand_profiles enable row level security;

drop policy if exists "brands public read" on public.whisper_brand_profiles;
create policy "brands public read"
  on public.whisper_brand_profiles for select
  using (published = true);

create table if not exists public.whisper_sponsorship_applications (
  id uuid primary key default gen_random_uuid(),
  brand_user_id uuid not null,
  brand_company text,
  creator_user_id uuid not null,
  creator_username text,
  creator_age integer,
  creator_followers integer,
  -- What the creator asked for.
  desired_basis text not null,            -- per_post | per_month | per_year
  desired_amount_cents integer not null,
  message text,
  -- Current standing terms (editable by the brand when countering).
  terms_basis text,
  terms_amount_cents integer,
  terms_notes text,
  status text not null default 'pending', -- pending | countered | accepted | denied | withdrawn
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_sponsor_apps_brand
  on public.whisper_sponsorship_applications (brand_user_id, created_at desc);
create index if not exists idx_sponsor_apps_creator
  on public.whisper_sponsorship_applications (creator_user_id, created_at desc);

alter table public.whisper_sponsorship_applications enable row level security;

drop policy if exists "sponsor apps own read" on public.whisper_sponsorship_applications;
create policy "sponsor apps own read"
  on public.whisper_sponsorship_applications for select
  to authenticated
  using (auth.uid() = brand_user_id or auth.uid() = creator_user_id);

create table if not exists public.whisper_sponsorship_deals (
  id uuid primary key default gen_random_uuid(),
  application_id uuid,
  brand_user_id uuid not null,
  brand_company text,
  creator_user_id uuid not null,
  creator_username text,
  basis text not null,                    -- per_post | per_month | per_year
  amount_cents integer not null,
  notes text,
  status text not null default 'active',  -- active | completed | cancelled
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_sponsor_deals_brand
  on public.whisper_sponsorship_deals (brand_user_id, created_at desc);
create index if not exists idx_sponsor_deals_creator
  on public.whisper_sponsorship_deals (creator_user_id, created_at desc);

alter table public.whisper_sponsorship_deals enable row level security;

drop policy if exists "sponsor deals own read" on public.whisper_sponsorship_deals;
create policy "sponsor deals own read"
  on public.whisper_sponsorship_deals for select
  to authenticated
  using (auth.uid() = brand_user_id or auth.uid() = creator_user_id);

create table if not exists public.whisper_sponsorship_posts (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null,
  post_id text not null,
  creator_user_id uuid,
  brand_user_id uuid,
  created_at timestamptz not null default now(),
  unique (deal_id, post_id)
);

alter table public.whisper_sponsorship_posts enable row level security;

drop policy if exists "sponsor posts own read" on public.whisper_sponsorship_posts;
create policy "sponsor posts own read"
  on public.whisper_sponsorship_posts for select
  to authenticated
  using (auth.uid() = brand_user_id or auth.uid() = creator_user_id);

create table if not exists public.whisper_sponsorship_payments (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null,
  brand_user_id uuid,
  creator_user_id uuid,
  gross_cents integer not null,
  fee_cents integer not null default 0,
  net_cents integer not null,
  status text not null default 'pending',  -- pending | released | failed
  -- per_post payments release when a tracked post lands; time-based
  -- payments release after hold_until (end of the week).
  requires_post boolean not null default false,
  hold_until timestamptz,
  stripe_session_id text unique,
  stripe_transfer_id text,
  released_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_sponsor_payments_deal
  on public.whisper_sponsorship_payments (deal_id, created_at desc);

alter table public.whisper_sponsorship_payments enable row level security;

drop policy if exists "sponsor payments own read" on public.whisper_sponsorship_payments;
create policy "sponsor payments own read"
  on public.whisper_sponsorship_payments for select
  to authenticated
  using (auth.uid() = brand_user_id or auth.uid() = creator_user_id);

-- A brand denied a creator's application: the brand can no longer DM them.
create table if not exists public.whisper_dm_blocks (
  id uuid primary key default gen_random_uuid(),
  blocked_sender_id uuid not null,   -- the brand
  protected_user_id uuid not null,   -- the creator
  reason text,
  created_at timestamptz not null default now(),
  unique (blocked_sender_id, protected_user_id)
);

alter table public.whisper_dm_blocks enable row level security;

drop policy if exists "dm blocks own read" on public.whisper_dm_blocks;
create policy "dm blocks own read"
  on public.whisper_dm_blocks for select
  to authenticated
  using (auth.uid() = blocked_sender_id or auth.uid() = protected_user_id);

-- ---------------------------------------------------------------------------
-- v2 — Ember brand verification, richer terms, disputes, and reach metrics.
-- Safe to re-run (idempotent).
-- ---------------------------------------------------------------------------

-- Ember Instagram verification on brand profiles.
alter table public.whisper_brand_profiles
  add column if not exists instagram text,
  add column if not exists ember_verified boolean not null default false,
  add column if not exists ember_score integer,
  add column if not exists ember_summary text,
  add column if not exists ember_checked_at timestamptz;

-- Richer editable terms: deliverables brief, exclusivity, offer deadline.
alter table public.whisper_sponsorship_applications
  add column if not exists terms_deliverables text,
  add column if not exists terms_exclusive boolean not null default false,
  add column if not exists terms_expires_at timestamptz;

alter table public.whisper_sponsorship_deals
  add column if not exists deliverables text,
  add column if not exists exclusive boolean not null default false;

-- Verified reach metrics snapshotted when a creator links a post.
alter table public.whisper_sponsorship_posts
  add column if not exists likes_count integer not null default 0,
  add column if not exists comments_count integer not null default 0;

-- Disputes + refunds on escrow payments (status gains 'refunded').
alter table public.whisper_sponsorship_payments
  add column if not exists stripe_payment_intent text,
  add column if not exists dispute_reason text,
  add column if not exists refunded_at timestamptz,
  add column if not exists stripe_refund_id text;
