-- WPP — Whisper Paid Partners (ad-revenue share for creators)
-- Run once in the Supabase SQL editor. Safe to re-run.
-- RUN ORDER: business-suite-v4.sql FIRST (this file's revenue function
-- reads the campaigns/ads/events tables it creates).
--
-- The YouTube/TikTok pool model: every month, 50% of REAL ad spend
-- (impressions × campaign CPM) becomes the creator pool. A creator's
-- month = min(their qualified views × tier RPM, their view-share of the
-- pool) — payouts can never exceed collected ad revenue, and tier RPMs
-- (Partner 1k+ ≈ $0.90 · Partner+ 10k+ ≈ $1.40 · Elite 100k+ ≈ $2.20 per
-- 1,000 views) act as per-creator caps. Months finalize on the 1st (UTC).
-- A "qualified view" = one signed-in viewer seeing a creator's post,
-- counted at most once per viewer/post/day, capped per viewer per day,
-- never self-views. The feed reports views through the wpp_track_views
-- RPC below; the backend reads the math with the service role and moves
-- the money through Stripe.

create table if not exists public.whisper_wpp_views (
  id bigint generated always as identity primary key,
  creator_user_id uuid not null,
  viewer_id uuid not null,
  post_id text not null,
  day date not null default ((now() at time zone 'utc'))::date,
  created_at timestamptz not null default now(),
  constraint whisper_wpp_views_unique unique (creator_user_id, viewer_id, post_id, day)
);

create index if not exists whisper_wpp_views_creator_idx
  on public.whisper_wpp_views (creator_user_id, created_at desc);
create index if not exists whisper_wpp_views_viewer_day_idx
  on public.whisper_wpp_views (viewer_id, day);

alter table public.whisper_wpp_views enable row level security;

-- Creators may read their own view rows (counts power the dashboard);
-- inserts only happen through the RPC below.
drop policy if exists "wpp_views_select_own" on public.whisper_wpp_views;
create policy "wpp_views_select_own"
  on public.whisper_wpp_views for select
  using (auth.uid() = creator_user_id);

-- Batch view reporting from the feed: parallel arrays of creator ids +
-- post ids. Deduped per viewer/post/day by the unique constraint,
-- self-views skipped, 30 marks per call, 500 marks per viewer per day.
create or replace function public.wpp_track_views(
  p_creators uuid[],
  p_posts text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer uuid := auth.uid();
  today date := ((now() at time zone 'utc'))::date;
  n int;
  i int;
  todays int;
begin
  if viewer is null then
    return;
  end if;
  n := least(
    coalesce(array_length(p_creators, 1), 0),
    coalesce(array_length(p_posts, 1), 0),
    30
  );
  if n = 0 then
    return;
  end if;
  select count(*) into todays
    from public.whisper_wpp_views
   where viewer_id = viewer and day = today;
  if todays >= 500 then
    return;
  end if;
  for i in 1..n loop
    if p_creators[i] is null
       or p_creators[i] = viewer
       or coalesce(p_posts[i], '') = '' then
      continue;
    end if;
    insert into public.whisper_wpp_views (creator_user_id, viewer_id, post_id, day)
    values (p_creators[i], viewer, left(p_posts[i], 80), today)
    on conflict on constraint whisper_wpp_views_unique do nothing;
  end loop;
end $$;

revoke all on function public.wpp_track_views(uuid[], text[]) from public;
grant execute on function public.wpp_track_views(uuid[], text[]) to authenticated;

-- Payout ledger — written by the backend (service role) when a creator
-- cashes out; creators can read their own history.
create table if not exists public.whisper_wpp_cashouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_cents bigint not null,
  views_counted bigint not null default 0,
  rpm_cents int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists whisper_wpp_cashouts_user_idx
  on public.whisper_wpp_cashouts (user_id, created_at desc);

alter table public.whisper_wpp_cashouts enable row level security;

drop policy if exists "wpp_cashouts_select_own" on public.whisper_wpp_cashouts;
create policy "wpp_cashouts_select_own"
  on public.whisper_wpp_cashouts for select
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Revenue math — one row per calendar month: the creator's qualified
-- views, everyone's qualified views, and the platform's ad revenue that
-- month (impressions × campaign CPM, in cents). The backend (service
-- role) turns these into pool shares; clients never call this directly.
-- ---------------------------------------------------------------------------

create or replace function public.wpp_creator_months(p_user uuid)
returns table (
  month timestamptz,
  my_views bigint,
  total_views bigint,
  revenue_cents bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with v as (
    select date_trunc('month', created_at) as m,
           count(*) as total,
           count(*) filter (where creator_user_id = p_user) as mine
      from public.whisper_wpp_views
     group by 1
  ),
  r as (
    select date_trunc('month', ev.created_at) as m,
           coalesce(sum(coalesce(c.cpm_cents, 500)), 0) / 1000 as rev
      from public.business_ad_events ev
      join public.business_ads a on a.id = ev.ad_id
      left join public.business_campaigns c on c.id = a.campaign_id
     where ev.kind = 'impression'
     group by 1
  )
  select coalesce(v.m, r.m) as month,
         coalesce(v.mine, 0) as my_views,
         coalesce(v.total, 0) as total_views,
         coalesce(r.rev, 0) as revenue_cents
    from v
    full outer join r on r.m = v.m
   order by 1;
$$;

revoke all on function public.wpp_creator_months(uuid) from public;
revoke all on function public.wpp_creator_months(uuid) from authenticated;
grant execute on function public.wpp_creator_months(uuid) to service_role;
