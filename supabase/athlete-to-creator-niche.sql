-- Round 79 — retire the Athlete badge into a Creator NICHE.
--
-- "Athlete" is no longer its own paid badge. Every verified athlete becomes a
-- verified Creator wearing the niche "Athlete" in professional_category —
-- the light-gray line under the name on both apps. The legacy is_athlete flag
-- is left in place (older builds and analytics still read it); nothing here
-- is destructive and the file is safe to re-run forever.
--
-- Run once in the Supabase SQL editor AFTER account-types.sql.

begin;

alter table public.whisper_profiles add column if not exists professional_category text;
alter table public.whisper_profiles add column if not exists account_type text;
alter table public.whisper_profiles add column if not exists is_verified boolean default false;

-- 1) Verified athletes → verified creators with the Athlete niche.
update public.whisper_profiles
set
  is_verified = true,
  account_type = case
    when coalesce(account_type, '') in ('', 'personal', 'user', 'athlete') then 'creator'
    else account_type
  end,
  professional_category = coalesce(nullif(trim(professional_category), ''), 'Athlete')
where coalesce(is_athlete, false) = true;

-- 2) Pending athlete applications become verified-creator applications so the
--    same review queue (Creators) picks them up. Only when both tables exist.
do $$
begin
  if to_regclass('public.whisper_athlete_applications') is not null
     and to_regclass('public.whisper_verified_applications') is not null then
    insert into public.whisper_verified_applications (user_id, username, reason, status, created_at)
    select a.user_id,
           a.username,
           concat('Niche: Athlete. ', coalesce(a.reason, a.details, '')),
           a.status,
           a.created_at
    from public.whisper_athlete_applications a
    where a.status = 'pending'
      and not exists (
        select 1 from public.whisper_verified_applications v
        where v.user_id = a.user_id and v.status = 'pending'
      );
  end if;
exception when undefined_column then
  -- Older application schemas differ; the queue migration is best-effort.
  raise notice 'athlete→verified application copy skipped (schema mismatch)';
end $$;

-- 3) Badge purchases recorded against the athlete role keep their history but
--    are read as the verified (creator) badge from here on.
do $$
begin
  if to_regclass('public.whisper_badge_purchases') is not null then
    update public.whisper_badge_purchases set role = 'verified' where role = 'athlete';
  end if;
exception when undefined_column then
  raise notice 'badge purchase role rewrite skipped (schema mismatch)';
end $$;

commit;
