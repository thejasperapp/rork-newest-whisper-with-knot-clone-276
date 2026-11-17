-- Community categorization v2 + private groups.
-- Run once in the Supabase SQL editor. Safe to re-run.
--
-- 1) Posts carry their community as DATA (picked in the composer) instead of
--    a hashtag folded into the caption.
-- 2) whisper_communities gains a visibility column ("public" | "private").
-- 3) whisper_community_members powers invite-only private groups.

-- ── 1. Explicit community on posts ─────────────────────────────────────────
alter table public.whisper_posts add column if not exists community_id text;
alter table public.whisper_posts add column if not exists community_name text;
create index if not exists whisper_posts_community_idx
  on public.whisper_posts (community_id)
  where community_id is not null;

-- ── 2. Community visibility ────────────────────────────────────────────────
alter table public.whisper_communities
  add column if not exists visibility text not null default 'public';

-- ── 3. Private-group membership + invites ──────────────────────────────────
create table if not exists public.whisper_community_members (
  community_slug text not null,
  user_id uuid not null,
  username text not null default '',
  role text not null default 'member',      -- 'owner' | 'member'
  status text not null default 'member',    -- 'member' | 'invited'
  invited_by text not null default '',
  created_at timestamptz not null default now(),
  primary key (community_slug, user_id)
);

alter table public.whisper_community_members enable row level security;

-- Membership checks without policy recursion.
create or replace function public.whisper_is_group_member(slug text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.whisper_community_members
    where community_slug = slug
      and user_id = auth.uid()
  );
$$;

create or replace function public.whisper_owns_community(slug text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.whisper_communities
    where whisper_communities.slug = whisper_owns_community.slug
      and creator_id = auth.uid()
  );
$$;

drop policy if exists "group members read" on public.whisper_community_members;
create policy "group members read" on public.whisper_community_members
  for select using (
    user_id = auth.uid()
    or public.whisper_is_group_member(community_slug)
    or public.whisper_owns_community(community_slug)
  );

-- Owners add themselves (owner row) and invite others (invited rows).
drop policy if exists "group owner writes" on public.whisper_community_members;
create policy "group owner writes" on public.whisper_community_members
  for insert with check (
    public.whisper_owns_community(community_slug)
    and (user_id = auth.uid() or status = 'invited')
  );

-- Invitees flip their own row invited -> member.
drop policy if exists "member accepts own invite" on public.whisper_community_members;
create policy "member accepts own invite" on public.whisper_community_members
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Leave/decline your own row; owners remove anyone.
drop policy if exists "member leaves or owner removes" on public.whisper_community_members;
create policy "member leaves or owner removes" on public.whisper_community_members
  for delete using (
    user_id = auth.uid()
    or public.whisper_owns_community(community_slug)
  );
