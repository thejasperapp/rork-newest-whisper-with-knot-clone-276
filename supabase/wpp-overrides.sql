-- ============================================================================
-- WPP manual access grants — founder-managed tier overrides.
-- Run once in the Supabase SQL editor. Safe to re-run.
--
-- WPP tiers normally come from follower count (Partner 1k+ · Partner+ 10k+ ·
-- Elite 100k+). A row here grants a tier regardless of followers — used for
-- founder testing and hand-picked partners. Only the TIER is granted; views,
-- pool math, and payout rules stay identical.
--
-- The backend also carries a baked-in founder allowlist (@dyl → Partner) so
-- the grant works even before this migration runs; this table is the durable,
-- editable home for it.
-- ============================================================================

create table if not exists public.whisper_wpp_overrides (
  user_id uuid primary key,
  tier_id text not null default 'partner'
    check (tier_id in ('partner', 'partner-plus', 'elite')),
  note text,
  created_at timestamptz not null default now()
);

-- Service-role only: RLS on with NO policies — clients can neither read nor
-- write grants; only the backend (service key) consults this table.
alter table public.whisper_wpp_overrides enable row level security;

-- Founder grant: @dyl gets Partner-tier WPP access for testing.
insert into public.whisper_wpp_overrides (user_id, tier_id, note)
select user_id, 'partner', 'Founder grant — WPP testing'
from public.whisper_profiles
where lower(username) = 'dyl'
on conflict (user_id) do update set tier_id = excluded.tier_id;
