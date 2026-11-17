-- Whisper articles — admin-written posts shown on the public site.
-- Run once in Supabase → SQL Editor.

create table if not exists public.whisper_articles (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  excerpt text not null default '',
  cover_url text not null default '',
  category text not null default 'Training',
  author_name text not null default 'Whisper Team',
  paragraphs jsonb not null default '[]'::jsonb,
  published boolean not null default true,
  published_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.whisper_articles enable row level security;

-- Anyone (including signed-out visitors) can read published articles.
drop policy if exists "articles_public_read" on public.whisper_articles;
create policy "articles_public_read"
  on public.whisper_articles for select
  using (published = true);

-- Writes only happen through the billing backend with the service role.
create index if not exists whisper_articles_published_idx
  on public.whisper_articles (published, published_at desc);
