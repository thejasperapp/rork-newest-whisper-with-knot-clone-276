-- Blogger badge — a dedicated role for users who post articles and film
-- reviews. Distinct from coaches/athletes/verified creators: a blogger's
-- sole purpose on Whisper is writing. The flag is set manually by the
-- founder/admin, exactly like `is_director` and `is_recruiter`.

alter table public.profiles
  add column if not exists is_blogger boolean not null default false;

alter table public.whisper_profiles
  add column if not exists is_blogger boolean not null default false;

-- Bloggers can read/write their own whisper_profiles row.
drop policy if exists "whisper_profiles blogger self" on public.whisper_profiles;
create policy "whisper_profiles blogger self"
  on public.whisper_profiles for all
  using (auth.uid() = user_id and is_blogger = true)
  with check (auth.uid() = user_id and is_blogger = true);
