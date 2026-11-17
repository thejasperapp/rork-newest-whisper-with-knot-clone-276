-- Directors sub-badge for the Whisper media team.
-- Adds an `is_director` flag to both the auth `profiles` table and the
-- public `whisper_profiles` table so the director role resolves the same
-- way the recruiter role does (boolean on both tables, read by the apps).

alter table public.profiles
  add column if not exists is_director boolean not null default false;

alter table public.whisper_profiles
  add column if not exists is_director boolean not null default false;

-- Directors can read/write their own profile rows (RLS already allows this
-- for the owner, but be explicit so a director-only account — no other
-- badge — can still edit their own whisper_profiles row).
drop policy if exists "whisper_profiles director self" on public.whisper_profiles;
create policy "whisper_profiles director self"
  on public.whisper_profiles for all
  using (auth.uid() = user_id and is_director = true)
  with check (auth.uid() = user_id and is_director = true);
