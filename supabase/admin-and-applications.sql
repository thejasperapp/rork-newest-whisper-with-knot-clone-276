-- ============================================================================
-- Whisper application tables + status dropdowns + admins/moderators table
-- (run once in the Supabase SQL editor — safe to re-run)
--
-- What this does:
--  1. Creates the three application tables if they don't exist yet
--     (coach, athlete, verified-creator).
--  2. Converts every `status` column from plain text to a proper enum
--     (pending / approved / denied) so the Supabase table editor shows a
--     CLICKABLE DROPDOWN instead of free text. (A boolean can't hold three
--     states — an enum is the right tool and gives you the picker.)
--  3. Creates a `whisper_admins` table (owner / admin / moderator) with a
--     role dropdown. Adding or removing a row automatically flips the
--     matching flags on `profiles`, so iOS, web, and the billing backend all
--     honor it instantly.
--
-- NOTE: approvals made in the table editor still fire the payment-link email
-- via the existing `notify_badge_approved` trigger from badge-payments.sql.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Enum types (dropdowns in the Supabase table editor)
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.whisper_application_status as enum ('pending','approved','denied');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.whisper_admin_role as enum ('owner','admin','moderator');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 1. Application tables (created only if missing — existing data is kept)
-- ---------------------------------------------------------------------------
create table if not exists public.whisper_coach_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  username text not null,
  email text,
  full_name text not null default '',
  credentials text,
  specialties text[],
  experience_years integer,
  website text,
  bio text,
  social text,
  status public.whisper_application_status not null default 'pending',
  created_at timestamptz not null default now()
);

create table if not exists public.whisper_athlete_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  username text not null,
  email text,
  full_name text not null default '',
  sport text,
  level text,
  team text,
  prs text,
  bio text,
  social text,
  status public.whisper_application_status not null default 'pending',
  created_at timestamptz not null default now()
);

create table if not exists public.whisper_verification_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  username text not null,
  email text,
  full_name text not null default '',
  category text,
  reason text,
  links text,
  followers integer,
  status public.whisper_application_status not null default 'pending',
  created_at timestamptz not null default now()
);

-- RLS: applicants can submit and read their own row; admins act through the
-- backend (service role), which bypasses RLS.
alter table public.whisper_coach_applications enable row level security;
alter table public.whisper_athlete_applications enable row level security;
alter table public.whisper_verification_requests enable row level security;

drop policy if exists "wca insert own" on public.whisper_coach_applications;
create policy "wca insert own" on public.whisper_coach_applications
  for insert with check (auth.uid() = user_id);
drop policy if exists "wca read own" on public.whisper_coach_applications;
create policy "wca read own" on public.whisper_coach_applications
  for select using (auth.uid() = user_id);

drop policy if exists "waa insert own" on public.whisper_athlete_applications;
create policy "waa insert own" on public.whisper_athlete_applications
  for insert with check (auth.uid() = user_id);
drop policy if exists "waa read own" on public.whisper_athlete_applications;
create policy "waa read own" on public.whisper_athlete_applications
  for select using (auth.uid() = user_id);

drop policy if exists "wvr insert own" on public.whisper_verification_requests;
create policy "wvr insert own" on public.whisper_verification_requests
  for insert with check (auth.uid() = user_id);
drop policy if exists "wvr read own" on public.whisper_verification_requests;
create policy "wvr read own" on public.whisper_verification_requests
  for select using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 2. Convert existing text `status` columns to the enum (dropdown).
--    Skips tables that were just created with the enum already in place.
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
  c record;
begin
  foreach t in array array[
    'whisper_coach_applications',
    'whisper_athlete_applications',
    'whisper_verification_requests'
  ] loop
    if exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = t
         and column_name = 'status' and udt_name <> 'whisper_application_status'
    ) then
      -- Drop any old CHECK constraints that reference status.
      for c in
        select conname from pg_constraint
         where conrelid = format('public.%I', t)::regclass
           and contype = 'c'
           and pg_get_constraintdef(oid) ilike '%status%'
      loop
        execute format('alter table public.%I drop constraint %I', t, c.conname);
      end loop;

      execute format('alter table public.%I alter column status drop default', t);
      execute format(
        'alter table public.%I alter column status type public.whisper_application_status '
        || 'using (case when status in (''pending'',''approved'',''denied'') '
        || 'then status else ''pending'' end)::public.whisper_application_status',
        t
      );
      execute format(
        'alter table public.%I alter column status set default ''pending''::public.whisper_application_status',
        t
      );
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Re-attach the approval-email triggers (covers tables created above).
--    Only runs if badge-payments.sql was applied (which defines the function).
-- ---------------------------------------------------------------------------
do $$ begin
  if exists (select 1 from pg_proc where proname = 'notify_badge_approved') then
    drop trigger if exists coach_approved_email on public.whisper_coach_applications;
    create trigger coach_approved_email
      after update on public.whisper_coach_applications
      for each row execute function public.notify_badge_approved();

    drop trigger if exists athlete_approved_email on public.whisper_athlete_applications;
    create trigger athlete_approved_email
      after update on public.whisper_athlete_applications
      for each row execute function public.notify_badge_approved();

    drop trigger if exists verified_approved_email on public.whisper_verification_requests;
    create trigger verified_approved_email
      after update on public.whisper_verification_requests
      for each row execute function public.notify_badge_approved();
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Admins / moderators table. The `role` column is an enum, so the table
--    editor gives you an owner/admin/moderator dropdown. Insert a row to
--    grant access, delete it to revoke — triggers keep `profiles` in sync.
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists is_owner boolean not null default false;
alter table public.profiles add column if not exists is_admin boolean not null default false;
alter table public.profiles add column if not exists is_moderator boolean not null default false;

create table if not exists public.whisper_admins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  username text,
  email text,
  role public.whisper_admin_role not null default 'moderator',
  created_at timestamptz not null default now()
);

alter table public.whisper_admins enable row level security;

drop policy if exists "wadm read own" on public.whisper_admins;
create policy "wadm read own" on public.whisper_admins
  for select using (auth.uid() = user_id);
-- No insert/update/delete policies: only the backend (service role) or the
-- Supabase dashboard writes here.

-- Keep the profiles flags in sync so iOS + web keep working unchanged.
create or replace function public.sync_whisper_admin_flags()
returns trigger
language plpgsql
security definer
as $$
begin
  if tg_op = 'DELETE' then
    update public.profiles
       set is_owner = false, is_admin = false, is_moderator = false
     where id = old.user_id;
    return old;
  end if;
  update public.profiles
     set is_owner     = (new.role = 'owner'),
         is_admin     = (new.role = 'admin'),
         is_moderator = (new.role = 'moderator')
   where id = new.user_id;
  return new;
end;
$$;

drop trigger if exists whisper_admins_sync on public.whisper_admins;
create trigger whisper_admins_sync
  after insert or update or delete on public.whisper_admins
  for each row execute function public.sync_whisper_admin_flags();

-- Seed the table from anyone who already has a flag on their profile.
do $$ begin
  insert into public.whisper_admins (user_id, username, role)
  select p.id,
         p.username,
         (case when p.is_owner then 'owner'
               when p.is_admin then 'admin'
               else 'moderator' end)::public.whisper_admin_role
    from public.profiles p
   where coalesce(p.is_owner, false)
      or coalesce(p.is_admin, false)
      or coalesce(p.is_moderator, false)
  on conflict (user_id) do nothing;
exception when undefined_column then
  -- profiles has no username column — seed without it.
  insert into public.whisper_admins (user_id, role)
  select p.id,
         (case when p.is_owner then 'owner'
               when p.is_admin then 'admin'
               else 'moderator' end)::public.whisper_admin_role
    from public.profiles p
   where coalesce(p.is_owner, false)
      or coalesce(p.is_admin, false)
      or coalesce(p.is_moderator, false)
  on conflict (user_id) do nothing;
end $$;
