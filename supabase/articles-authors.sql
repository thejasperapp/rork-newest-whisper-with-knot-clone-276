-- Article authorship for coaches, athletes, and verified creators.
-- Run once in the Supabase SQL editor (safe to re-run).

alter table public.whisper_articles
  add column if not exists author_user_id uuid;

create index if not exists whisper_articles_author_idx
  on public.whisper_articles (author_user_id);
