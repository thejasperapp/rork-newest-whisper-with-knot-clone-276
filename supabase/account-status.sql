-- Unified account status — every promotion lives on whisper_profiles.
-- Run once in the Supabase SQL editor. Safe to re-run.
--
-- Both apps now read ONE row for every role/badge gate:
--   whisper_profiles: is_coach, is_athlete, is_recruiter, is_brand,
--                     is_verified, is_moderator, is_admin, is_owner
--
-- Backfills copy what already lives on profiles / whisper_brand_profiles,
-- and triggers keep the mirrors in sync going forward, so promoting a user
-- anywhere (admin tools, badge payments, brand signup) always shows up on
-- their whisper profile row.

-- 1) Columns ---------------------------------------------------------------

alter table public.whisper_profiles add column if not exists is_coach     boolean not null default false;
alter table public.whisper_profiles add column if not exists is_athlete   boolean not null default false;
alter table public.whisper_profiles add column if not exists is_recruiter boolean not null default false;
alter table public.whisper_profiles add column if not exists is_brand     boolean not null default false;
alter table public.whisper_profiles add column if not exists is_verified  boolean not null default false;
alter table public.whisper_profiles add column if not exists is_moderator boolean not null default false;
alter table public.whisper_profiles add column if not exists is_admin     boolean not null default false;
alter table public.whisper_profiles add column if not exists is_owner     boolean not null default false;

-- 2) Backfill from profiles (badge + role flags; profiles.id = auth uid) ----

do $$
begin
  update public.whisper_profiles wp
     set is_verified  = wp.is_verified  or coalesce(p.is_verified,  false),
         is_moderator = wp.is_moderator or coalesce(p.is_moderator, false),
         is_admin     = wp.is_admin     or coalesce(p.is_admin,     false),
         is_owner     = wp.is_owner     or coalesce(p.is_owner,     false),
         is_coach     = wp.is_coach     or coalesce(p.is_coach,     false),
         is_athlete   = wp.is_athlete   or coalesce(p.is_athlete,   false),
         is_recruiter = wp.is_recruiter or coalesce(p.is_recruiter, false)
    from public.profiles p
   where p.id = wp.user_id;
exception when others then
  null; -- older schema (missing column / different key) — mirror what exists
end $$;

-- Fallback join on username for schemas where profiles.id isn't the auth uid.
do $$
begin
  update public.whisper_profiles wp
     set is_verified  = wp.is_verified  or coalesce(p.is_verified,  false),
         is_moderator = wp.is_moderator or coalesce(p.is_moderator, false),
         is_admin     = wp.is_admin     or coalesce(p.is_admin,     false),
         is_owner     = wp.is_owner     or coalesce(p.is_owner,     false)
    from public.profiles p
   where lower(p.username) = lower(wp.username)
     and (coalesce(p.is_verified, false) or coalesce(p.is_moderator, false)
          or coalesce(p.is_admin, false) or coalesce(p.is_owner, false));
exception when others then
  null;
end $$;

-- 3) Backfill brand flag from brand profiles --------------------------------

do $$
begin
  update public.whisper_profiles wp
     set is_brand = true
   where exists (
     select 1 from public.whisper_brand_profiles b where b.user_id = wp.user_id
   );
exception when others then
  null;
end $$;

-- 4) Keep badge flags in sync when profiles change ---------------------------

create or replace function public.whisper_mirror_profile_flags()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    update public.whisper_profiles
       set is_verified  = coalesce(new.is_verified,  false),
           is_moderator = coalesce(new.is_moderator, false),
           is_admin     = coalesce(new.is_admin,     false),
           is_owner     = coalesce(new.is_owner,     false)
     where user_id = new.id;
  exception when others then
    null; -- never let the mirror break a profiles write
  end;
  return new;
end $$;

drop trigger if exists whisper_mirror_profile_flags_tg on public.profiles;
create trigger whisper_mirror_profile_flags_tg
after insert or update on public.profiles
for each row execute function public.whisper_mirror_profile_flags();

-- 5) Keep the brand flag in sync with brand profiles -------------------------

create or replace function public.whisper_mirror_brand_flag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    if tg_op = 'DELETE' then
      update public.whisper_profiles set is_brand = false where user_id = old.user_id;
      return old;
    end if;
    update public.whisper_profiles set is_brand = true where user_id = new.user_id;
  exception when others then
    null;
  end;
  return new;
end $$;

drop trigger if exists whisper_mirror_brand_flag_tg on public.whisper_brand_profiles;
create trigger whisper_mirror_brand_flag_tg
after insert or update or delete on public.whisper_brand_profiles
for each row execute function public.whisper_mirror_brand_flag();
