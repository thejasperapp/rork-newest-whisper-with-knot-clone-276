-- ============================================================================
-- Custom communities — user-created topic hubs that live alongside the
-- built-in catalog. Posts match a community via its #slug hashtag or any of
-- its keywords (same matching rule as the catalog communities).
--
-- Run once in the Supabase SQL editor — safe to re-run.
-- ============================================================================

create table if not exists public.whisper_communities (
  id uuid primary key default gen_random_uuid(),
  -- URL id, e.g. "trail-runners". Lowercase letters, digits, hyphens.
  slug text not null unique,
  name text not null,
  tagline text not null default '',
  -- Two-stop gradient for the avatar disc + hero.
  color1 text not null default '#FB8333',
  color2 text not null default '#FFB86B',
  -- Caption keywords that pull posts into this community.
  keywords text[] not null default '{}',
  creator_id uuid references auth.users(id) on delete set null,
  creator_username text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists whisper_communities_created_idx
  on public.whisper_communities (created_at desc);

alter table public.whisper_communities enable row level security;

drop policy if exists "communities read all" on public.whisper_communities;
create policy "communities read all" on public.whisper_communities
  for select using (true);

drop policy if exists "communities insert own" on public.whisper_communities;
create policy "communities insert own" on public.whisper_communities
  for insert to authenticated with check (auth.uid() = creator_id);

drop policy if exists "communities update own" on public.whisper_communities;
create policy "communities update own" on public.whisper_communities
  for update to authenticated
  using (auth.uid() = creator_id) with check (auth.uid() = creator_id);

drop policy if exists "communities delete own" on public.whisper_communities;
create policy "communities delete own" on public.whisper_communities
  for delete to authenticated using (auth.uid() = creator_id);
