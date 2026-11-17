-- Featured profiles: admin-curated spotlight cards (like the Hudson coach
-- card) shown on the public Coaches page and the Athlete/Creator role pages.
-- Writes happen only through the billing backend (service role). Published
-- rows are publicly readable so the marketing pages can render them.

create table if not exists public.whisper_featured_profiles (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('coach', 'athlete', 'creator', 'recruiter')),
  name text not null,
  -- Optional link to a real Whisper account (selected by username in admin).
  username text,
  user_id uuid,
  photo_url text not null default '',
  -- Coach tier (1-3); null for athletes/creators.
  tier int check (tier between 1 and 3),
  -- e.g. "Bodybuilding" (coach), "Sprinting" (athlete), "Fitness content" (creator)
  discipline text,
  age text,
  chips jsonb not null default '[]'::jsonb,
  paragraphs jsonb not null default '[]'::jsonb,
  highlights jsonb not null default '[]'::jsonb,
  testimonials jsonb not null default '[]'::jsonb,
  -- Typed CTA buttons (email, calendar, link, profile). Empty falls back to cta_label/cta_url.
  action_buttons jsonb not null default '[]'::jsonb,
  cta_label text,
  sort_order int not null default 0,
  published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists whisper_featured_profiles_kind_idx
  on public.whisper_featured_profiles (kind, published, sort_order);

alter table public.whisper_featured_profiles enable row level security;

-- Public marketing pages read published rows with the anon key.
drop policy if exists "featured profiles are publicly readable"
  on public.whisper_featured_profiles;
create policy "featured profiles are publicly readable"
  on public.whisper_featured_profiles
  for select
  using (published = true);

-- No insert/update/delete policies: mutations go through the backend, which
-- uses the service role key and its own admin check.
