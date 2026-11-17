-- ============================================================================
-- Recruiter reviews — users who signed up via a recruiter's referral code can
-- rate the recruiter 1–5 stars and leave a short review. The founder/admin
-- sees aggregate ratings so they know which recruiters are performing well.
-- (run once in the Supabase SQL editor — safe to re-run)
-- ============================================================================

create table if not exists public.whisper_recruiter_reviews (
  id uuid primary key default gen_random_uuid(),
  -- The recruiter being reviewed.
  recruiter_id uuid not null references auth.users(id) on delete cascade,
  -- The user who left the review (must have signed up via the recruiter's code).
  reviewer_id uuid not null references auth.users(id) on delete cascade,
  -- 1–5 star rating.
  rating integer not null check (rating >= 1 and rating <= 5),
  -- Optional free-text review.
  review text,
  created_at timestamptz not null default now(),
  -- One review per (recruiter, reviewer) pair — updating replaces the old one.
  unique(recruiter_id, reviewer_id)
);

alter table public.whisper_recruiter_reviews enable row level security;

-- A reviewer can read + write their own review.
drop policy if exists "wrr read own" on public.whisper_recruiter_reviews;
create policy "wrr read own" on public.whisper_recruiter_reviews
  for select using (auth.uid() = reviewer_id or auth.uid() = recruiter_id);

drop policy if exists "wrr insert own" on public.whisper_recruiter_reviews;
create policy "wrr insert own" on public.whisper_recruiter_reviews
  for insert with check (auth.uid() = reviewer_id);

drop policy if exists "wrr update own" on public.whisper_recruiter_reviews;
create policy "wrr update own" on public.whisper_recruiter_reviews
  for update using (auth.uid() = reviewer_id);

drop policy if exists "wrr delete own" on public.whisper_recruiter_reviews;
create policy "wrr delete own" on public.whisper_recruiter_reviews
  for delete using (auth.uid() = reviewer_id);

-- Admins/owner read all reviews via the backend service role (bypasses RLS).

create index if not exists idx_recruiter_reviews_recruiter
  on public.whisper_recruiter_reviews (recruiter_id, created_at desc);

-- ---------------------------------------------------------------------------
-- View: aggregate recruiter ratings (average + count) for the admin dashboard.
-- ---------------------------------------------------------------------------
create or replace view public.whisper_recruiter_rating_summary as
select
  r.recruiter_id,
  count(*)::integer as review_count,
  round(avg(r.rating), 2) as average_rating,
  count(*) filter (where r.rating >= 4)::integer as positive_count,
  count(*) filter (where r.rating <= 2)::integer as negative_count
from public.whisper_recruiter_reviews r
group by r.recruiter_id;

grant select on public.whisper_recruiter_rating_summary to authenticated;
