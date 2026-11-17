-- Whisper Business — full business suite (v2)
-- Run once in the Supabase SQL editor. Safe to re-run.
--
-- v1: business_deals — each signed-in user's private sponsorship pipeline.
-- v2: business_profiles + business_ads + business_ad_events — companies
--     manage a business identity, create ads, serve them into the Whisper
--     feed, and read real impression/click analytics.
--
-- RLS keeps every table owner-only; ad serving + tracking go through
-- narrowly-scoped RPCs so viewers never read the raw tables.

create table if not exists public.business_deals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  brand_name text not null,
  contact text,
  creator_username text,
  value_cents bigint not null default 0,
  stage text not null default 'lead'
    check (stage in ('lead','pitched','negotiating','active','completed')),
  next_step text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists business_deals_user_idx
  on public.business_deals (user_id, stage);

alter table public.business_deals enable row level security;

drop policy if exists "business_deals_select_own" on public.business_deals;
create policy "business_deals_select_own"
  on public.business_deals for select
  using (auth.uid() = user_id);

drop policy if exists "business_deals_insert_own" on public.business_deals;
create policy "business_deals_insert_own"
  on public.business_deals for insert
  with check (auth.uid() = user_id);

drop policy if exists "business_deals_update_own" on public.business_deals;
create policy "business_deals_update_own"
  on public.business_deals for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "business_deals_delete_own" on public.business_deals;
create policy "business_deals_delete_own"
  on public.business_deals for delete
  using (auth.uid() = user_id);

-- ===========================================================================
-- v2 — Business profiles (the company identity behind ads)
-- ===========================================================================

create table if not exists public.business_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  category text,
  website text,
  email text,
  phone text,
  logo_url text,
  about text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists business_profiles_user_idx
  on public.business_profiles (user_id);

alter table public.business_profiles enable row level security;

drop policy if exists "business_profiles_select_own" on public.business_profiles;
create policy "business_profiles_select_own"
  on public.business_profiles for select
  using (auth.uid() = user_id);

drop policy if exists "business_profiles_insert_own" on public.business_profiles;
create policy "business_profiles_insert_own"
  on public.business_profiles for insert
  with check (auth.uid() = user_id);

drop policy if exists "business_profiles_update_own" on public.business_profiles;
create policy "business_profiles_update_own"
  on public.business_profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "business_profiles_delete_own" on public.business_profiles;
create policy "business_profiles_delete_own"
  on public.business_profiles for delete
  using (auth.uid() = user_id);

-- ===========================================================================
-- v2 — Ads (creative + placement + budget + status)
-- ===========================================================================

create table if not exists public.business_ads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id uuid references public.business_profiles(id) on delete set null,
  name text not null,
  headline text not null,
  body text,
  image_url text,
  cta_label text not null default 'Learn more',
  cta_url text,
  placement text not null default 'feed'
    check (placement in ('feed','discover','both')),
  status text not null default 'draft'
    check (status in ('draft','active','paused','ended')),
  daily_budget_cents bigint not null default 0,
  total_budget_cents bigint not null default 0,
  start_at timestamptz not null default now(),
  end_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists business_ads_user_idx
  on public.business_ads (user_id, status, created_at desc);
create index if not exists business_ads_serve_idx
  on public.business_ads (status, placement, start_at);

alter table public.business_ads enable row level security;

drop policy if exists "business_ads_select_own" on public.business_ads;
create policy "business_ads_select_own"
  on public.business_ads for select
  using (auth.uid() = user_id);

drop policy if exists "business_ads_insert_own" on public.business_ads;
create policy "business_ads_insert_own"
  on public.business_ads for insert
  with check (auth.uid() = user_id);

drop policy if exists "business_ads_update_own" on public.business_ads;
create policy "business_ads_update_own"
  on public.business_ads for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "business_ads_delete_own" on public.business_ads;
create policy "business_ads_delete_own"
  on public.business_ads for delete
  using (auth.uid() = user_id);

-- ===========================================================================
-- v2 — Ad events (impressions + clicks; inserted via RPC only)
-- ===========================================================================

create table if not exists public.business_ad_events (
  id bigint generated always as identity primary key,
  ad_id uuid not null references public.business_ads(id) on delete cascade,
  viewer_id uuid,
  kind text not null check (kind in ('impression','click')),
  created_at timestamptz not null default now()
);

create index if not exists business_ad_events_ad_idx
  on public.business_ad_events (ad_id, kind, created_at desc);
create index if not exists business_ad_events_viewer_idx
  on public.business_ad_events (ad_id, viewer_id, kind, created_at desc);

alter table public.business_ad_events enable row level security;

-- Ad owners can read their own events; nobody inserts directly (RPC only).
drop policy if exists "business_ad_events_select_owner" on public.business_ad_events;
create policy "business_ad_events_select_owner"
  on public.business_ad_events for select
  using (exists (
    select 1 from public.business_ads a
     where a.id = ad_id and a.user_id = auth.uid()
  ));

-- ===========================================================================
-- v2 — Serving: signed-in users pull the active rotation for a placement
-- ===========================================================================

create or replace function public.business_active_ads(
  p_placement text default 'feed',
  p_limit int default 6
)
returns table (
  id uuid,
  headline text,
  body text,
  image_url text,
  cta_label text,
  cta_url text,
  business_name text,
  business_logo_url text,
  business_website text
)
language sql
security definer
set search_path = public
as $$
  select a.id,
         a.headline,
         a.body,
         a.image_url,
         a.cta_label,
         a.cta_url,
         coalesce(p.name, 'Sponsor') as business_name,
         p.logo_url as business_logo_url,
         p.website as business_website
    from public.business_ads a
    left join public.business_profiles p on p.id = a.profile_id
   where a.status = 'active'
     and (a.placement = p_placement or a.placement = 'both')
     and a.start_at <= now()
     and (a.end_at is null or a.end_at > now())
   order by random()
   limit greatest(1, least(coalesce(p_limit, 6), 12));
$$;

revoke all on function public.business_active_ads(text, int) from public;
grant execute on function public.business_active_ads(text, int) to authenticated;

-- ===========================================================================
-- v2 — Tracking: impression/click with a 30-minute impression dedupe
-- ===========================================================================

create or replace function public.business_track_ad(
  p_ad uuid,
  p_kind text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_ad is null or p_kind not in ('impression','click') then
    return;
  end if;
  -- One impression per viewer per ad per 30 minutes keeps counts honest.
  if p_kind = 'impression' and auth.uid() is not null and exists (
    select 1 from public.business_ad_events
     where ad_id = p_ad
       and viewer_id = auth.uid()
       and kind = 'impression'
       and created_at > now() - interval '30 minutes'
  ) then
    return;
  end if;
  insert into public.business_ad_events (ad_id, viewer_id, kind)
  values (p_ad, auth.uid(), p_kind);
end $$;

revoke all on function public.business_track_ad(uuid, text) from public;
grant execute on function public.business_track_ad(uuid, text) to authenticated;

-- ===========================================================================
-- v2 — Analytics: daily impressions/clicks for MY ads (last 30 days)
-- ===========================================================================

create or replace function public.business_ad_daily_stats()
returns table (
  ad_id uuid,
  day date,
  impressions bigint,
  clicks bigint
)
language sql
security definer
set search_path = public
as $$
  select e.ad_id,
         (e.created_at at time zone 'utc')::date as day,
         count(*) filter (where e.kind = 'impression') as impressions,
         count(*) filter (where e.kind = 'click') as clicks
    from public.business_ad_events e
    join public.business_ads a on a.id = e.ad_id
   where a.user_id = auth.uid()
     and e.created_at > now() - interval '30 days'
   group by 1, 2
   order by 2;
$$;

revoke all on function public.business_ad_daily_stats() from public;
grant execute on function public.business_ad_daily_stats() to authenticated;

-- ===========================================================================
-- v3 — Audience targeting, scheduling & daily caps (additive, safe to re-run)
-- ===========================================================================

alter table public.business_ads
  add column if not exists target_roles text[] default null;
alter table public.business_ads
  add column if not exists daily_impression_cap int not null default 0;

-- Serving v3: same signature (old app builds keep working) — adds
--   · audience targeting resolved SERVER-side from the viewer's
--     whisper_profiles role flags (untargeted ads reach everyone)
--   · a per-day impression cap (0 = unlimited)
--   · the existing schedule window (start_at / end_at)
create or replace function public.business_active_ads(
  p_placement text default 'feed',
  p_limit int default 6
)
returns table (
  id uuid,
  headline text,
  body text,
  image_url text,
  cta_label text,
  cta_url text,
  business_name text,
  business_logo_url text,
  business_website text
)
language sql
security definer
set search_path = public
as $$
  with viewer as (
    select coalesce(wp.is_athlete, false)   as athletes,
           coalesce(wp.is_coach, false)     as coaches,
           coalesce(wp.is_verified, false)  as creators,
           coalesce(wp.is_recruiter, false) as recruiters,
           coalesce(wp.is_brand, false)     as brands
      from public.whisper_profiles wp
     where wp.user_id = auth.uid()
     limit 1
  )
  select a.id,
         a.headline,
         a.body,
         a.image_url,
         a.cta_label,
         a.cta_url,
         coalesce(p.name, 'Sponsor') as business_name,
         p.logo_url as business_logo_url,
         p.website as business_website
    from public.business_ads a
    left join public.business_profiles p on p.id = a.profile_id
   where a.status = 'active'
     and (a.placement = p_placement or a.placement = 'both')
     and a.start_at <= now()
     and (a.end_at is null or a.end_at > now())
     and (
       a.target_roles is null
       or cardinality(a.target_roles) = 0
       or exists (
         select 1 from viewer v
          where ('athletes'   = any(a.target_roles) and v.athletes)
             or ('coaches'    = any(a.target_roles) and v.coaches)
             or ('creators'   = any(a.target_roles) and v.creators)
             or ('recruiters' = any(a.target_roles) and v.recruiters)
             or ('brands'     = any(a.target_roles) and v.brands)
       )
     )
     and (
       a.daily_impression_cap <= 0
       or (
         select count(*)
           from public.business_ad_events e
          where e.ad_id = a.id
            and e.kind = 'impression'
            and e.created_at >= date_trunc('day', now())
       ) < a.daily_impression_cap
     )
   order by random()
   limit greatest(1, least(coalesce(p_limit, 6), 12));
$$;

revoke all on function public.business_active_ads(text, int) from public;
grant execute on function public.business_active_ads(text, int) to authenticated;

-- Analytics window widened to 90 days so the dashboard can offer
-- 7 / 14 / 30 / 90-day ranges client-side.
create or replace function public.business_ad_daily_stats()
returns table (
  ad_id uuid,
  day date,
  impressions bigint,
  clicks bigint
)
language sql
security definer
set search_path = public
as $$
  select e.ad_id,
         (e.created_at at time zone 'utc')::date as day,
         count(*) filter (where e.kind = 'impression') as impressions,
         count(*) filter (where e.kind = 'click') as clicks
    from public.business_ad_events e
    join public.business_ads a on a.id = e.ad_id
   where a.user_id = auth.uid()
     and e.created_at > now() - interval '90 days'
   group by 1, 2
   order by 2;
$$;

revoke all on function public.business_ad_daily_stats() from public;
grant execute on function public.business_ad_daily_stats() to authenticated;
