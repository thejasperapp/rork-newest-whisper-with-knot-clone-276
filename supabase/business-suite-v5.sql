-- ============================================================================
-- Whisper Business v5 — the researched Meta-parity upgrade.
-- Run once in the Supabase SQL editor AFTER business-suite-v4.sql.
-- Safe to re-run.
--
-- What lands here:
--   1. Real media on ads — uploaded photos OR videos (ad-media storage bucket)
--   2. Placements as a real multi-select: Feed · Reels · Comments
--   3. Detailed targeting: roles (v3) + follower-size band per ad set
--   4. Budgets: campaign lifetime budget cap (delivery stops at the cap)
--   5. Auto-recharge: saved card tops the wallet up when it runs low
--      (settings written ONLY by the backend service role)
--   6. Ad Library — a PUBLIC, searchable registry of every live ad,
--      exactly like Meta's transparency library
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1 · Ads carry real media now — image or video
-- ---------------------------------------------------------------------------
alter table public.business_ads
  add column if not exists media_type text not null default 'image'
    check (media_type in ('image','video'));
alter table public.business_ads
  add column if not exists video_url text;

-- ---------------------------------------------------------------------------
-- 2 + 3 · Ad sets: placements array + follower-band targeting
-- ---------------------------------------------------------------------------
alter table public.business_ad_sets
  add column if not exists placements text[];
alter table public.business_ad_sets
  add column if not exists follower_min int not null default 0;
alter table public.business_ad_sets
  add column if not exists follower_max int;

-- Backfill: legacy single placement becomes the array once.
update public.business_ad_sets
   set placements = case
     when placement = 'both' then array['feed','discover']
     else array[placement]
   end
 where placements is null;

-- ---------------------------------------------------------------------------
-- 4 · Campaign lifetime budget (cents; null = no cap)
-- ---------------------------------------------------------------------------
alter table public.business_campaigns
  add column if not exists lifetime_budget_cents bigint;

-- ---------------------------------------------------------------------------
-- 5 · Auto-recharge settings — read-only to the owner; the backend
--     (service role) writes rows and executes off-session charges.
-- ---------------------------------------------------------------------------
create table if not exists public.whisper_ad_autorecharge (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default false,
  threshold_cents int not null default 500,
  amount_cents int not null default 2500,
  stripe_customer_id text,
  stripe_pm_id text,
  pm_brand text,
  pm_last4 text,
  pending_session_id text,
  last_charged_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.whisper_ad_autorecharge enable row level security;

drop policy if exists "ad_autorecharge_select_own" on public.whisper_ad_autorecharge;
create policy "ad_autorecharge_select_own"
  on public.whisper_ad_autorecharge for select
  using (auth.uid() = user_id);
-- No insert/update/delete policies: the service role bypasses RLS.

-- ---------------------------------------------------------------------------
-- Storage: the ad-media bucket — public read, owners upload to their folder
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('ad-media', 'ad-media', true)
on conflict (id) do update set public = true;

drop policy if exists "ad_media_public_read" on storage.objects;
create policy "ad_media_public_read" on storage.objects
  for select using (bucket_id = 'ad-media');

drop policy if exists "ad_media_owner_insert" on storage.objects;
create policy "ad_media_owner_insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'ad-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "ad_media_owner_update" on storage.objects;
create policy "ad_media_owner_update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'ad-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "ad_media_owner_delete" on storage.objects;
create policy "ad_media_owner_delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'ad-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- 6 · Serving v5 — placements array (feed · reels · comments), follower
--     band, campaign lifetime budget. Same signature as v4 so every
--     shipped client keeps working; the return table gains media columns
--     (drop + recreate because the row type changed).
-- ---------------------------------------------------------------------------
drop function if exists public.business_active_ads(text, int);

create function public.business_active_ads(
  p_placement text default 'feed',
  p_limit int default 6
)
returns table (
  id uuid,
  headline text,
  body text,
  image_url text,
  video_url text,
  media_type text,
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
  viewer_reach as (
    select count(*)::int as followers
      from public.whisper_follows f
     where f.following_id = auth.uid()
  ),
  eligible as (
    select a.id,
           a.headline,
           a.body,
           a.image_url,
           a.video_url,
           coalesce(a.media_type, 'image') as media_type,
           a.cta_label,
           a.cta_url,
           a.profile_id,
           -- Effective delivery settings: ad-set rules when linked,
           -- the ad's legacy columns otherwise.
           (case
              when s.id is not null then
                coalesce(
                  s.placements,
                  case when s.placement = 'both' then array['feed','discover']
                       else array[s.placement] end
                )
              else
                case when a.placement = 'both' then array['feed','discover']
                     else array[a.placement] end
            end) as eff_placements,
           (case when s.id is not null then s.start_at else a.start_at end) as eff_start,
           (case when s.id is not null then s.end_at else a.end_at end) as eff_end,
           (case when s.id is not null then s.target_roles else a.target_roles end) as eff_roles,
           (case when s.id is not null then s.daily_impression_cap else a.daily_impression_cap end) as eff_cap,
           coalesce(s.follower_min, 0) as eff_follower_min,
           s.follower_max as eff_follower_max,
           s.id as set_id,
           c.id as campaign_id,
           coalesce(c.cpm_cents, 500) as cpm_cents,
           c.lifetime_budget_cents
      from public.business_ads a
      left join public.business_ad_sets s on s.id = a.ad_set_id
      left join public.business_campaigns c on c.id = a.campaign_id
     where a.status = 'active'
       and (s.id is null or s.status = 'active')
       and (c.id is null or c.status = 'active')
       -- Delivery pauses the moment the owner's ad wallet is empty.
       and public.business_wallet_balance_cents(a.user_id) > 0
  )
  select e.id,
         e.headline,
         e.body,
         e.image_url,
         e.video_url,
         e.media_type,
         e.cta_label,
         e.cta_url,
         coalesce(p.name, 'Sponsor') as business_name,
         p.logo_url as business_logo_url,
         p.website as business_website
    from eligible e
    left join public.business_profiles p on p.id = e.profile_id
   where p_placement = any(e.eff_placements)
     and e.eff_start <= now()
     and (e.eff_end is null or e.eff_end > now())
     -- Role targeting (v3)
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
     -- Follower-band targeting (v5) — only enforced on linked ad sets.
     and (
       (e.eff_follower_min <= 0 and e.eff_follower_max is null)
       or exists (
         select 1 from viewer_reach vr
          where vr.followers >= e.eff_follower_min
            and (e.eff_follower_max is null or vr.followers <= e.eff_follower_max)
       )
     )
     -- Campaign lifetime budget (v5): stop when spend reaches the cap.
     and (
       e.lifetime_budget_cents is null
       or (
         (select count(*)
            from public.business_ad_events ev
            join public.business_ads a3 on a3.id = ev.ad_id
           where a3.campaign_id = e.campaign_id
             and ev.kind = 'impression'
         ) * e.cpm_cents / 1000
       ) < e.lifetime_budget_cents
     )
     -- Daily pacing (v3/v4)
     and (
       e.eff_cap <= 0
       or (
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

-- ---------------------------------------------------------------------------
-- Ad Library — PUBLIC transparency registry of every ad currently live,
-- searchable by advertiser or headline. No viewer targeting, no caps, no
-- tracking: it shows what's running, exactly like Meta's Ad Library.
-- ---------------------------------------------------------------------------
create or replace function public.business_ads_library(
  p_query text default null,
  p_limit int default 40
)
returns table (
  id uuid,
  headline text,
  body text,
  image_url text,
  video_url text,
  media_type text,
  cta_label text,
  cta_url text,
  business_name text,
  business_logo_url text,
  objective text,
  placements text[],
  started_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select a.id,
         a.headline,
         a.body,
         a.image_url,
         a.video_url,
         coalesce(a.media_type, 'image') as media_type,
         a.cta_label,
         a.cta_url,
         coalesce(p.name, 'Sponsor') as business_name,
         p.logo_url as business_logo_url,
         coalesce(c.objective, 'traffic') as objective,
         (case
            when s.id is not null then
              coalesce(
                s.placements,
                case when s.placement = 'both' then array['feed','discover']
                     else array[s.placement] end
              )
            else
              case when a.placement = 'both' then array['feed','discover']
                   else array[a.placement] end
          end) as placements,
         coalesce(s.start_at, a.start_at, a.created_at) as started_at
    from public.business_ads a
    left join public.business_ad_sets s on s.id = a.ad_set_id
    left join public.business_campaigns c on c.id = a.campaign_id
    left join public.business_profiles p on p.id = a.profile_id
   where a.status = 'active'
     and (s.id is null or s.status = 'active')
     and (c.id is null or c.status = 'active')
     and coalesce(s.start_at, a.start_at, a.created_at) <= now()
     and (coalesce(s.end_at, a.end_at) is null or coalesce(s.end_at, a.end_at) > now())
     and (
       p_query is null
       or btrim(p_query) = ''
       or coalesce(p.name, '') ilike '%' || btrim(p_query) || '%'
       or a.headline ilike '%' || btrim(p_query) || '%'
     )
   order by coalesce(s.start_at, a.start_at, a.created_at) desc
   limit greatest(1, least(coalesce(p_limit, 40), 100));
$$;

revoke all on function public.business_ads_library(text, int) from public;
grant execute on function public.business_ads_library(text, int) to anon, authenticated;
