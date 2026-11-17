-- ============================================================================
-- Refund system — self-serve requests with human review.
--
-- Policy windows (published at /policies): Whisper One + badge fees are
-- refundable within 14 days of the charge, coaching subscriptions within
-- 7 days of the billing-cycle start, program purchases within 14 days.
-- Users file requests from Settings → Billing on both apps; admins decide
-- in the web admin console; approval executes the Stripe refund server-side
-- (reversing the coach transfer + platform fee on destination charges) and
-- immediately ends the underlying subscription.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================================

create table if not exists public.whisper_refund_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  email text,
  kind text not null,                       -- one | badge | coach-hire | program
  reference text,                           -- sub_… or cs_… behind the purchase
  coach_user_id uuid,
  amount_cents integer,
  reason text,
  status text not null default 'pending',   -- pending | processed | denied | failed
  eligible_auto boolean not null default false,
  decided_by uuid,
  decided_at timestamptz,
  admin_note text,
  stripe_refund_id text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists whisper_refund_requests_user_idx
  on public.whisper_refund_requests (user_id, created_at desc);
create index if not exists whisper_refund_requests_status_idx
  on public.whisper_refund_requests (status, created_at desc);

alter table public.whisper_refund_requests enable row level security;

-- Users see their own requests; all writes go through the backend (service
-- role) so ownership, dedupe, and refund windows are enforced server-side.
drop policy if exists "refunds_read_own" on public.whisper_refund_requests;
create policy "refunds_read_own"
  on public.whisper_refund_requests for select
  using (auth.uid() = user_id);

-- Refunded coaching charges stop counting toward the client's "paid" status
-- and program access — the backend filters on this flag.
alter table public.whisper_coach_earnings
  add column if not exists refunded boolean not null default false;
