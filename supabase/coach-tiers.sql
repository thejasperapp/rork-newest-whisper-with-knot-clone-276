-- ============================================================================
-- Coach plan tiers — coaches define up to 3 plans (name, monthly price,
-- perks, optional client cap); clients pick one on the hire page. The legacy
-- single rate in whisper_coach_pricing stays as the fallback for coaches who
-- haven't created tiers. Run this once in the Supabase SQL editor.
-- ============================================================================

create table if not exists public.whisper_coach_plans (
  id uuid primary key default gen_random_uuid(),
  coach_user_id uuid not null,
  name text not null,
  tagline text,
  monthly_price_cents integer not null,
  perks jsonb not null default '[]'::jsonb,
  max_clients integer,
  active boolean not null default true,
  sort integer not null default 0,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists whisper_coach_plans_coach_idx
  on public.whisper_coach_plans (coach_user_id, active, sort);

alter table public.whisper_coach_plans enable row level security;

-- Everyone can read tiers (the hire page is public).
drop policy if exists "coach_plans_public_read" on public.whisper_coach_plans;
create policy "coach_plans_public_read"
  on public.whisper_coach_plans for select
  using (true);

-- No insert/update/delete policies on purpose: every write goes through the
-- Whisper backend (service role) so prices stay clamped ($5–$2,000/mo),
-- tier counts capped at 3, and only approved coaches can publish plans.
