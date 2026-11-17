-- Whisper Business — v4: the Meta Ads Manager structure
-- Run once in the Supabase SQL editor. Safe to re-run.
--
-- Exactly Meta's hierarchy:
--   Campaign (the WHY — objective + on/off)
--     └─ Ad set (the WHO/WHEN — audience, schedule, placement, daily pacing)
--          └─ Ad (the WHAT — creative: headline, media, CTA)
--
-- Additive: existing ads are auto-wrapped in their own campaign + ad set
-- so nothing breaks; serving respects the FULL funnel (ad active AND ad
-- set active/in-window/under-cap AND campaign active). Legacy targeting
-- columns on ads remain the fallback for unlinked ads.

-- ===========================================================================
-- Campaigns
-- ===========================================================================

create table if not exists public.business_campaigns (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  objective text not null default 'traffic'
    check (objective in ('awareness','traffic','engagement','leads','sales')),
  status text not null default 'active'
    check (status in ('active','paused','ended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists business_campaigns_user_idx
  on public.business_campaigns (user_id, status, created_at desc);

-- v4.1 — ad economics: every campaign bills at a CPM (cents per 1,000
-- impressions, default $5.00). Impressions × CPM = ad spend; spend draws
-- down the business's prepaid wallet below and IS the revenue that funds
-- WPP creator payouts.
alter table public.business_campaigns
  add column if not exists cpm_cents int not null default 500;

alter table public.business_campaigns enable row level security;

drop policy if exists "business_campaigns_select_own" on public.business_campaigns;
create policy "business_campaigns_select_own"
  on public.business_campaigns for select using (auth.uid() = user_id);
drop policy if exists "business_campaigns_insert_own" on public.business_campaigns;
create policy "business_campaigns_insert_own"
  on public.business_campaigns for insert with check (auth.uid() = user_id);
drop policy if exists "business_campaigns_update_own" on public.business_campaigns;
create policy "business_campaigns_update_own"
  on public.business_campaigns for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "business_campaigns_delete_own" on public.business_campaigns;
create policy "business_campaigns_delete_own"
  on public.business_campaigns for delete using (auth.uid() = user_id);

-- ===========================================================================
-- Ad sets
-- ===========================================================================

create table if not exists public.business_ad_sets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  campaign_id uuid not null references public.business_campaigns(id) on delete cascade,
  name text not null,
  status text not null default 'active'
    check (status in ('active','paused','ended')),
  target_roles text[] default null,
  placement text not null default 'feed'
    check (placement in ('feed','discover','both')),
  start_at timestamptz not null default now(),
  end_at timestamptz,
  daily_impression_cap int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists business_ad_sets_user_idx
  on public.business_ad_sets (user_id, status, created_at desc);
create index if not exists business_ad_sets_campaign_idx
  on public.business_ad_sets (campaign_id);

alter table public.business_ad_sets enable row level security;

drop policy if exists "business_ad_sets_select_own" on public.business_ad_sets;
create policy "business_ad_sets_select_own"
  on public.business_ad_sets for select using (auth.uid() = user_id);
drop policy if exists "business_ad_sets_insert_own" on public.business_ad_sets;
create policy "business_ad_sets_insert_own"
  on public.business_ad_sets for insert with check (auth.uid() = user_id);
drop policy if exists "business_ad_sets_update_own" on public.business_ad_sets;
create policy "business_ad_sets_update_own"
  on public.business_ad_sets for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "business_ad_sets_delete_own" on public.business_ad_sets;
create policy "business_ad_sets_delete_own"
  on public.business_ad_sets for delete using (auth.uid() = user_id);

-- ===========================================================================
-- Ads join the hierarchy
-- ===========================================================================

alter table public.business_ads
  add column if not exists campaign_id uuid references public.business_campaigns(id) on delete set null;
alter table public.business_ads
  add column if not exists ad_set_id uuid references public.business_ad_sets(id) on delete set null;

create index if not exists business_ads_campaign_idx
  on public.business_ads (campaign_id);
create index if not exists business_ads_set_idx
  on public.business_ads (ad_set_id);

-- Backfill: wrap every pre-v4 ad in its own campaign + ad set carrying
-- the ad's old targeting/schedule/pacing, so history and delivery are
-- unchanged the moment v4 lands.
do $$
declare
  r record;
  cid uuid;
  sid uuid;
begin
  for r in select * from public.business_ads where ad_set_id is null loop
    insert into public.business_campaigns (user_id, name, objective, status)
    values (r.user_id, r.name, 'traffic', 'active')
    returning id into cid;
    insert into public.business_ad_sets
      (user_id, campaign_id, name, status, target_roles, placement,
       start_at, end_at, daily_impression_cap)
    values
      (r.user_id, cid, r.name || ' — ad set', 'active', r.target_roles,
       r.placement, r.start_at, r.end_at, coalesce(r.daily_impression_cap, 0))
    returning id into sid;
    update public.business_ads
       set campaign_id = cid, ad_set_id = sid
     where id = r.id;
  end loop;
end $$;

-- ===========================================================================
-- v4.1 — Ad wallets: businesses prepay delivery (plus a $10 launch credit);
-- serving stops when the balance runs out. Top-ups are written by the
-- backend after Stripe checkout (service role); owners read their own rows.
-- ===========================================================================

create table if not exists public.whisper_ad_topups (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_cents bigint not null,
  source text not null default 'purchase'
    check (source in ('purchase','credit','adjustment')),
  stripe_session_id text unique,
  created_at timestamptz not null default now()
);

create index if not exists whisper_ad_topups_user_idx
  on public.whisper_ad_topups (user_id, created_at desc);

alter table public.whisper_ad_topups enable row level security;

drop policy if exists "ad_topups_select_own" on public.whisper_ad_topups;
create policy "ad_topups_select_own"
  on public.whisper_ad_topups for select
  using (auth.uid() = user_id);

-- Impressions × CPM lookups lean on this.
create index if not exists business_ad_events_kind_time_idx
  on public.business_ad_events (kind, created_at);

-- All-time ad spend for one business, in cents (impressions × the owning
-- campaign's CPM; unlinked legacy ads bill at the default $5.00 CPM).
create or replace function public.business_ad_spend_cents(p_user uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(coalesce(c.cpm_cents, 500)), 0) / 1000
    from public.business_ad_events ev
    join public.business_ads a on a.id = ev.ad_id
    left join public.business_campaigns c on c.id = a.campaign_id
   where a.user_id = p_user
     and ev.kind = 'impression';
$$;

-- Wallet balance = $10 launch credit + top-ups − all-time spend.
create or replace function public.business_wallet_balance_cents(p_user uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select 1000
       + coalesce((select sum(t.amount_cents)
                     from public.whisper_ad_topups t
                    where t.user_id = p_user), 0)
       - public.business_ad_spend_cents(p_user);
$$;

-- The signed-in owner's wallet card: balance, credit, top-ups, spend,
-- this month's spend + impressions.
create or replace function public.business_wallet_summary()
returns table (
  balance_cents bigint,
  launch_credit_cents int,
  topup_cents bigint,
  spend_cents bigint,
  month_spend_cents bigint,
  month_impressions bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with spend as (
    select coalesce(sum(coalesce(c.cpm_cents, 500)), 0) as all_ccpm,
           coalesce(sum(coalesce(c.cpm_cents, 500))
             filter (where ev.created_at >= date_trunc('month', now())), 0) as month_ccpm,
           count(*) filter (where ev.created_at >= date_trunc('month', now())) as month_imps
      from public.business_ad_events ev
      join public.business_ads a on a.id = ev.ad_id
      left join public.business_campaigns c on c.id = a.campaign_id
     where a.user_id = auth.uid()
       and ev.kind = 'impression'
  ),
  tops as (
    select coalesce(sum(amount_cents), 0) as t
      from public.whisper_ad_topups
     where user_id = auth.uid()
  )
  select 1000 + (select t from tops) - (select all_ccpm from spend) / 1000,
         1000,
         (select t from tops),
         (select all_ccpm from spend) / 1000,
         (select month_ccpm from spend) / 1000,
         (select month_imps from spend);
$$;

revoke all on function public.business_wallet_summary() from public;
grant execute on function public.business_wallet_summary() to authenticated;

-- ===========================================================================
-- Serving v4 — full-funnel delivery (same signature; old builds keep working)
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
  with viewer as (
    select coalesce(wp.is_athlete, false)   as athletes,
           coalesce(wp.is_coach, false)     as coaches,
           coalesce(wp.is_verified, false)  as creators,
           coalesce(wp.is_recruiter, false) as recruiters,
           coalesce(wp.is_brand, false)     as brands
      from public.whisper_profiles wp
     where wp.user_id = auth.uid()
     limit 1
  ),
  eligible as (
    select a.id,
           a.headline,
           a.body,
           a.image_url,
           a.cta_label,
           a.cta_url,
           a.profile_id,
           -- Effective delivery settings: the ad set rules when linked,
           -- the ad's legacy columns otherwise.
           (case when s.id is not null then s.placement else a.placement end) as eff_placement,
           (case when s.id is not null then s.start_at else a.start_at end) as eff_start,
           (case when s.id is not null then s.end_at else a.end_at end) as eff_end,
           (case when s.id is not null then s.target_roles else a.target_roles end) as eff_roles,
           (case when s.id is not null then s.daily_impression_cap else a.daily_impression_cap end) as eff_cap,
           s.id as set_id
      from public.business_ads a
      left join public.business_ad_sets s on s.id = a.ad_set_id
      left join public.business_campaigns c on c.id = a.campaign_id
     where a.status = 'active'
       and (s.id is null or s.status = 'active')
       and (c.id is null or c.status = 'active')
       -- v4.1: delivery pauses the moment the owner's ad wallet is empty —
       -- impressions are billed, never given away.
       and public.business_wallet_balance_cents(a.user_id) > 0
  )
  select e.id,
         e.headline,
         e.body,
         e.image_url,
         e.cta_label,
         e.cta_url,
         coalesce(p.name, 'Sponsor') as business_name,
         p.logo_url as business_logo_url,
         p.website as business_website
    from eligible e
    left join public.business_profiles p on p.id = e.profile_id
   where (e.eff_placement = p_placement or e.eff_placement = 'both')
     and e.eff_start <= now()
     and (e.eff_end is null or e.eff_end > now())
     and (
       e.eff_roles is null
       or cardinality(e.eff_roles) = 0
       or exists (
         select 1 from viewer v
          where ('athletes'   = any(e.eff_roles) and v.athletes)
             or ('coaches'    = any(e.eff_roles) and v.coaches)
             or ('creators'   = any(e.eff_roles) and v.creators)
             or ('recruiters' = any(e.eff_roles) and v.recruiters)
             or ('brands'     = any(e.eff_roles) and v.brands)
       )
     )
     and (
       e.eff_cap <= 0
       or (
         -- Ad-set-level pacing counts impressions across ALL ads in the
         -- set (Meta's daily pacing); unlinked ads count their own.
         select count(*)
           from public.business_ad_events ev
           join public.business_ads a2 on a2.id = ev.ad_id
          where (e.set_id is not null and a2.ad_set_id = e.set_id
                 or e.set_id is null and ev.ad_id = e.id)
            and ev.kind = 'impression'
            and ev.created_at >= date_trunc('day', now())
       ) < e.eff_cap
     )
   order by random()
   limit greatest(1, least(coalesce(p_limit, 6), 12));
$$;

revoke all on function public.business_active_ads(text, int) from public;
grant execute on function public.business_active_ads(text, int) to authenticated;
