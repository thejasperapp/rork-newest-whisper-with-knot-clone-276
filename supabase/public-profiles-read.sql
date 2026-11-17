-- ============================================================
-- Public profile read access — fixes usernames not populating
-- on mobile.
--
-- Why: the web app resolves author usernames through queries that
-- read the canonical `whisper_profiles` table, but the iOS app was
-- falling back to `public.profiles` rows. When the two tables drift
-- (e.g. a user changed their handle in Whisper but `profiles` still
-- holds the old one), iOS displayed the wrong username.
--
-- This script makes the SECURITY DEFINER helper `whisper_public_profiles`
-- prefer `whisper_profiles` and fall back to `profiles` only when a
-- user has no Whisper profile row. Public-read policies on both
-- tables are kept permissive so direct mobile queries also work.
--
-- Run in Supabase Studio → SQL editor.
-- ============================================================

alter table public.profiles enable row level security;
alter table public.whisper_profiles enable row level security;

drop policy if exists "profiles public read" on public.profiles;
create policy "profiles public read"
  on public.profiles
  for select
  using (true);

drop policy if exists "wprof read all" on public.whisper_profiles;
create policy "wprof read all"
  on public.whisper_profiles
  for select
  using (true);

grant select on public.profiles to anon, authenticated;
grant select on public.whisper_profiles to anon, authenticated;

-- Safe public-columns lookup that bypasses restrictive RLS.
-- Accepts text ids (some legacy rows carry non-uuid / mixed-case ids).
-- Prefers the canonical Whisper profile row; falls back to auth profiles.
create or replace function public.whisper_public_profiles(uids text[])
returns table (
  id text,
  username text,
  display_name text,
  profile_image_url text,
  is_verified boolean
)
language sql
security definer
set search_path = public
stable
as $$
  with normalized as (
    select lower(u) as uid from unnest(uids) as u
  ),
  whisper_rows as (
    select
      wp.user_id::text as id,
      wp.username,
      wp.display_name,
      wp.profile_image_url,
      false as is_verified
    from public.whisper_profiles wp
    where lower(wp.user_id::text) = any (select uid from normalized)
  ),
  legacy_rows as (
    select
      p.id::text as id,
      p.username,
      p.display_name,
      p.profile_image_url,
      p.is_verified
    from public.profiles p
    where lower(p.id::text) = any (select uid from normalized)
  )
  select
    coalesce(w.id, l.id) as id,
    coalesce(w.username, l.username) as username,
    coalesce(w.display_name, l.display_name) as display_name,
    coalesce(w.profile_image_url, l.profile_image_url) as profile_image_url,
    coalesce(l.is_verified, false) as is_verified
  from whisper_rows w
  full outer join legacy_rows l
    on lower(w.id) = lower(l.id)
  where coalesce(w.username, l.username) is not null;
$$;

grant execute on function public.whisper_public_profiles(text[]) to anon, authenticated;
