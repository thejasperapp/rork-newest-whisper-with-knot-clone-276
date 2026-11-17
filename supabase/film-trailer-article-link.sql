-- Featured Film Friday: trailer support + article/film link + author username.
-- Run once in the Supabase SQL editor.

-- Add trailer_url to films — a short trailer the director uploads alongside
-- the full film. Shown on any article written about the film.
alter table public.whisper_films
  add column if not exists trailer_url text;

-- Cache the author's username on the article row so the byline can link to
-- their profile without a join. Backfilled below for existing rows.
alter table public.whisper_articles
  add column if not exists author_username text;

-- Link an article to a film so the article can render the film's trailer
-- (or, for clipped articles, the clipped section of the film).
alter table public.whisper_articles
  add column if not exists film_id uuid references public.whisper_films(id) on delete set null;

-- For clipped articles: the spot in the film the article is about. When set,
-- the article shows that section of the film instead of the trailer.
alter table public.whisper_articles
  add column if not exists clip_time_seconds integer;

-- Index for looking up articles by film.
create index if not exists whisper_articles_film_idx
  on public.whisper_articles (film_id);

-- Backfill author_username from whisper_profiles for existing articles.
update public.whisper_articles a
  set author_username = p.username
  from public.whisper_profiles p
  where a.author_user_id = p.user_id
    and (a.author_username is null or a.author_username = '');
