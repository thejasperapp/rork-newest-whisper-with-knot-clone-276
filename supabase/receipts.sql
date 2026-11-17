-- Whisper receipts ledger (v1) — one row per successful charge.
-- Run once in the Supabase SQL editor. Safe to re-run.
--
-- Written ONLY by the backend (service role) from the Stripe webhook:
--   · checkout.session.completed  → first payment for every product
--   · invoice.paid / payment_succeeded → each renewal cycle
-- Marked refunded by the refund queue approval AND by direct admin refunds.
-- Users read their own rows via GET /billing/receipts; the admin console
-- reads everything via GET /admin/receipts.

create table if not exists public.whisper_receipts (
  id uuid primary key default gen_random_uuid(),
  receipt_no text not null unique,
  user_id uuid,
  email text,
  -- one | badge | coach-hire | program | sponsorship
  kind text not null default 'one',
  description text not null default '',
  amount_cents bigint not null default 0,
  currency text not null default 'usd',
  status text not null default 'paid' check (status in ('paid','refunded')),
  -- Dedupe anchors: unique so webhook retries can never double-insert.
  -- (Postgres allows many NULLs in a unique column, so mixed rows are fine.)
  stripe_session_id text unique,
  stripe_invoice_id text unique,
  stripe_payment_intent text,
  stripe_subscription_id text,
  coach_user_id uuid,
  refund_note text,
  refunded_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists whisper_receipts_user_idx
  on public.whisper_receipts (user_id, created_at desc);
create index if not exists whisper_receipts_sub_idx
  on public.whisper_receipts (stripe_subscription_id);

alter table public.whisper_receipts enable row level security;

-- Users see their own purchase history; nobody writes from the client.
drop policy if exists "receipts_select_own" on public.whisper_receipts;
create policy "receipts_select_own"
  on public.whisper_receipts for select
  using (auth.uid() = user_id);
