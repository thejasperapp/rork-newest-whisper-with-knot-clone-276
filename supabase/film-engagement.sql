-- Film engagement — YouTube-style likes, dislikes, comments, and shares.
-- Works alongside the existing whisper_film_timestamps (review markers).

-- Reactions: one per user per film (like or dislike). NULL-weight rows are
-- not allowed — delete the row to "take back" a reaction.
create table if not exists public.whisper_film_reactions (
  id uuid primary key default gen_random_uuid(),
  film_id uuid not null references public.whisper_films(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  weight text not null check (weight in ('like', 'dislike')),
  created_at timestamptz not null default now(),
  unique (film_id, user_id)
);

alter table public.whisper_film_reactions enable row level security;

-- Public can read all reactions (counts are visible to everyone).
drop policy if exists "reactions public read" on public.whisper_film_reactions;
create policy "reactions public read"
  on public.whisper_film_reactions for select
  using (true);

-- Authenticated users can set their own reaction.
drop policy if exists "reactions author insert" on public.whisper_film_reactions;
create policy "reactions author insert"
  on public.whisper_film_reactions for insert
  with check (auth.uid() = user_id);

-- Authors can update or delete their own reaction.
drop policy if exists "reactions author update" on public.whisper_film_reactions;
create policy "reactions author update"
  on public.whisper_film_reactions for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "reactions author delete" on public.whisper_film_reactions;
create policy "reactions author delete"
  on public.whisper_film_reactions for delete
  using (auth.uid() = user_id);

create index if not exists idx_film_reactions_film
  on public.whisper_film_reactions (film_id);

-- Comments: threaded one level deep (reply_to_comment_id for nested replies).
create table if not exists public.whisper_film_comments (
  id uuid primary key default gen_random_uuid(),
  film_id uuid not null references public.whisper_films(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) > 0 and char_length(body) <= 2000),
  reply_to_comment_id uuid references public.whisper_film_comments(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.whisper_film_comments enable row level security;

-- Public can read all comments.
drop policy if exists "comments public read" on public.whisper_film_comments;
create policy "comments public read"
  on public.whisper_film_comments for select
  using (true);

-- Authenticated users can comment.
drop policy if exists "comments author insert" on public.whisper_film_comments;
create policy "comments author insert"
  on public.whisper_film_comments for insert
  with check (auth.uid() = user_id);

-- Authors can delete their own comments.
drop policy if exists "comments author delete" on public.whisper_film_comments;
create policy "comments author delete"
  on public.whisper_film_comments for delete
  using (auth.uid() = user_id);

-- Authors can edit their own comment body.
drop policy if exists "comments author update" on public.whisper_film_comments;
create policy "comments author update"
  on public.whisper_film_comments for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists idx_film_comments_film
  on public.whisper_film_comments (film_id, created_at);

-- View: aggregated reaction counts per film (for fast reads).
create or replace view public.whisper_film_reaction_counts as
  select
    film_id,
    count(*) filter (where weight = 'like') as like_count,
    count(*) filter (where weight = 'dislike') as dislike_count
  from public.whisper_film_reactions
  group by film_id;

grant select on public.whisper_film_reaction_counts to anon, authenticated;
