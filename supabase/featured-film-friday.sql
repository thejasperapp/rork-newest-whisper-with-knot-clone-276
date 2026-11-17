-- Featured Film Friday — short films produced by the Whisper media team
-- (Directors). Films are published by directors/mods/admins/owners; users
-- with blogging permissions (coaches/athletes/verified creators) can
-- timestamp moments and generate clip placeholders for articles.

create table if not exists public.whisper_films (
  id uuid primary key default gen_random_uuid(),
  director_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  synopsis text,
  video_url text not null,
  poster_url text,
  duration_seconds integer,
  featured_date date,           -- the Friday this film is featured
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.whisper_films enable row level security;

-- Public can read published films.
drop policy if exists "films public read" on public.whisper_films;
create policy "films public read"
  on public.whisper_films for select
  using (published = true);

-- Directors, mods, admins, owners can manage films.
-- (Enforced in the backend via requireAdmin / is_director check — the RLS
--  here is a secondary gate so a director can insert their own films.)
drop policy if exists "films director insert" on public.whisper_films;
create policy "films director insert"
  on public.whisper_films for insert
  with check (auth.uid() = director_id);

drop policy if exists "films director update" on public.whisper_films;
create policy "films director update"
  on public.whisper_films for update
  using (auth.uid() = director_id)
  with check (auth.uid() = director_id);

drop policy if exists "films director delete" on public.whisper_films;
create policy "films director delete"
  on public.whisper_films for delete
  using (auth.uid() = director_id);

-- Film timestamps — a blogger marks a moment in a film they found
-- interesting. Each timestamp can generate a clip placeholder (a poster
-- frame URL + the timecode) that substitutes for the cover image in an
-- article paragraph.

create table if not exists public.whisper_film_timestamps (
  id uuid primary key default gen_random_uuid(),
  film_id uuid not null references public.whisper_films(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null,                   -- the blogger's note on why it's interesting
  time_seconds integer not null,         -- the spot in the film
  poster_url text,                       -- generated clip frame placeholder
  created_at timestamptz not null default now()
);

alter table public.whisper_film_timestamps enable row level security;

-- Public can read all timestamps (so articles can embed them).
drop policy if exists "timestamps public read" on public.whisper_film_timestamps;
create policy "timestamps public read"
  on public.whisper_film_timestamps for select
  using (true);

-- Authenticated users with blogging permissions can create timestamps.
drop policy if exists "timestamps author insert" on public.whisper_film_timestamps;
create policy "timestamps author insert"
  on public.whisper_film_timestamps for insert
  with check (auth.uid() = user_id);

-- Authors can delete their own timestamps.
drop policy if exists "timestamps author delete" on public.whisper_film_timestamps;
create policy "timestamps author delete"
  on public.whisper_film_timestamps for delete
  using (auth.uid() = user_id);

create index if not exists idx_film_timestamps_film
  on public.whisper_film_timestamps (film_id, time_seconds);
create index if not exists idx_films_featured
  on public.whisper_films (featured_date desc, created_at desc)
  where published = true;
