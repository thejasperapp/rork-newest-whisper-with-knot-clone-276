-- =========================================================
-- Device tokens for APNs push fan-out
-- =========================================================
create table if not exists public.whisper_device_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  bundle_id text,
  sandbox boolean,
  platform text not null default 'ios',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Backfill columns if an older version of the table already exists
alter table public.whisper_device_tokens
  add column if not exists bundle_id text,
  add column if not exists sandbox boolean,
  add column if not exists platform text not null default 'ios',
  add column if not exists active boolean not null default true,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create index if not exists whisper_device_tokens_user_idx
  on public.whisper_device_tokens (user_id) where active = true;

alter table public.whisper_device_tokens enable row level security;

drop policy if exists "wdt insert own" on public.whisper_device_tokens;
create policy "wdt insert own" on public.whisper_device_tokens
  for insert with check (auth.uid() = user_id);

drop policy if exists "wdt update own" on public.whisper_device_tokens;
create policy "wdt update own" on public.whisper_device_tokens
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "wdt select own" on public.whisper_device_tokens;
create policy "wdt select own" on public.whisper_device_tokens
  for select using (auth.uid() = user_id);

drop policy if exists "wdt delete own" on public.whisper_device_tokens;
create policy "wdt delete own" on public.whisper_device_tokens
  for delete using (auth.uid() = user_id);

-- The Edge Function uses the service-role key so RLS is bypassed for the
-- function's own SELECT / UPDATE — these policies only matter for the app.

-- =========================================================
-- Presence (Active now / Active 5 min ago)
-- =========================================================
create table if not exists public.whisper_presence (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_seen_at timestamptz not null default now()
);

alter table public.whisper_presence enable row level security;

drop policy if exists "presence read all" on public.whisper_presence;
create policy "presence read all" on public.whisper_presence
  for select using (true);

drop policy if exists "presence upsert self" on public.whisper_presence;
create policy "presence upsert self" on public.whisper_presence
  for insert with check (auth.uid() = user_id);

drop policy if exists "presence update self" on public.whisper_presence;
create policy "presence update self" on public.whisper_presence
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index if not exists whisper_presence_last_seen_idx
  on public.whisper_presence (last_seen_at desc);

-- =========================================================
-- Reels flag on whisper_posts
-- Distinguishes TikTok-style swipeable reels from regular
-- profile videos. Reels render only inside the reels surfaces
-- (feed carousel, Explore Reels chip, Profile Reels tab) and
-- are hidden from the regular feed/grid.
-- =========================================================
alter table public.whisper_posts
  add column if not exists is_reel boolean not null default false;

create index if not exists whisper_posts_is_reel_idx
  on public.whisper_posts (is_reel, created_at desc) where is_reel = true;

-- =========================================================
-- Comment threads (replies) + comment likes
-- =========================================================
alter table public.whisper_post_comments
  add column if not exists parent_comment_id uuid references public.whisper_post_comments(id) on delete cascade,
  add column if not exists likes_count int not null default 0;

create index if not exists whisper_comments_parent_idx
  on public.whisper_post_comments (parent_comment_id, created_at asc)
  where parent_comment_id is not null;

create table if not exists public.whisper_comment_likes (
  comment_id uuid not null references public.whisper_post_comments(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

alter table public.whisper_comment_likes enable row level security;

drop policy if exists "wcl read all" on public.whisper_comment_likes;
create policy "wcl read all" on public.whisper_comment_likes
  for select using (true);

drop policy if exists "wcl insert own" on public.whisper_comment_likes;
create policy "wcl insert own" on public.whisper_comment_likes
  for insert with check (auth.uid() = user_id);

drop policy if exists "wcl delete own" on public.whisper_comment_likes;
create policy "wcl delete own" on public.whisper_comment_likes
  for delete using (auth.uid() = user_id);

-- Keep whisper_post_comments.likes_count in sync via trigger
create or replace function public.whisper_comment_likes_bump() returns trigger
language plpgsql as $
begin
  if (tg_op = 'INSERT') then
    update public.whisper_post_comments
      set likes_count = likes_count + 1
      where id = new.comment_id;
  elsif (tg_op = 'DELETE') then
    update public.whisper_post_comments
      set likes_count = greatest(likes_count - 1, 0)
      where id = old.comment_id;
  end if;
  return null;
end;
$;

drop trigger if exists whisper_comment_likes_bump_trg on public.whisper_comment_likes;
create trigger whisper_comment_likes_bump_trg
  after insert or delete on public.whisper_comment_likes
  for each row execute function public.whisper_comment_likes_bump();

-- =========================================================
-- Coach proposals (Whisper coach -> Jasper client)
--
-- Whisper writes a row, deep-links the client into Jasper via
-- `jasper://coach-proposal/<id>`. Jasper renders a diff sheet and
-- flips status to accepted / declined / modified, applying the
-- patch to its own jasper_* tables. Coach name is read by joining
-- the public.profiles row on coach_user_id (normalized, not stored).
-- =========================================================
create table if not exists public.whisper_coach_proposals (
  id uuid primary key default gen_random_uuid(),
  coach_user_id  uuid not null references auth.users(id) on delete cascade,
  client_user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in (
    'macros','diet_plan','workout','exercise_swap','note'
  )),
  target_id uuid,
  patch jsonb not null default '{}'::jsonb,
  note text,
  status text not null default 'pending' check (status in (
    'pending','accepted','declined','modified','expired'
  )),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  responded_at timestamptz,
  expires_at   timestamptz not null default (now() + interval '7 days')
);

-- If an older shape exists with coach_username NOT NULL, relax it so
-- new inserts don't have to send it (Jasper joins profiles instead).
do $
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'whisper_coach_proposals'
      and column_name = 'coach_username'
  ) then
    execute 'alter table public.whisper_coach_proposals alter column coach_username drop not null';
  end if;
end$;
alter table public.whisper_coach_proposals
  alter column expires_at set default (now() + interval '7 days');

create index if not exists whisper_coach_proposals_client_idx
  on public.whisper_coach_proposals (client_user_id, status, created_at desc);
create index if not exists whisper_coach_proposals_coach_idx
  on public.whisper_coach_proposals (coach_user_id, status, created_at desc);
create index if not exists whisper_coach_proposals_expiry_idx
  on public.whisper_coach_proposals (status, expires_at)
  where status = 'pending';

alter table public.whisper_coach_proposals enable row level security;

drop policy if exists "coach insert proposal for accepted client"
  on public.whisper_coach_proposals;
create policy "coach insert proposal for accepted client"
  on public.whisper_coach_proposals for insert to authenticated
  with check (
    coach_user_id = auth.uid()
    and exists (
      select 1 from public.whisper_coach_requests r
      where r.coach_user_id  = auth.uid()
        and r.client_user_id = whisper_coach_proposals.client_user_id
        and r.status = 'accepted'
    )
  );

drop policy if exists "coach read own proposals" on public.whisper_coach_proposals;
create policy "coach read own proposals"
  on public.whisper_coach_proposals for select to authenticated
  using (coach_user_id = auth.uid());

drop policy if exists "client read own proposals" on public.whisper_coach_proposals;
create policy "client read own proposals"
  on public.whisper_coach_proposals for select to authenticated
  using (client_user_id = auth.uid());

drop policy if exists "client respond own proposals" on public.whisper_coach_proposals;
create policy "client respond own proposals"
  on public.whisper_coach_proposals for update to authenticated
  using (client_user_id = auth.uid())
  with check (client_user_id = auth.uid());

-- Column-level guard: when the *client* updates the row, they may
-- only change status, responded_at, patch, updated_at. Anything
-- else (kind, target_id, note, ids, expires_at) must stay put.
create or replace function public.whisper_coach_proposals_guard() returns trigger
language plpgsql as $
begin
  if auth.uid() is null then
    -- service-role / cron — allow.
    return new;
  end if;
  if auth.uid() = old.coach_user_id then
    -- coach can rewrite their own proposal freely.
    return new;
  end if;
  if auth.uid() = old.client_user_id then
    if new.coach_user_id   is distinct from old.coach_user_id
    or new.client_user_id  is distinct from old.client_user_id
    or new.kind            is distinct from old.kind
    or new.target_id       is distinct from old.target_id
    or new.note            is distinct from old.note
    or new.created_at      is distinct from old.created_at
    or new.expires_at      is distinct from old.expires_at then
      raise exception 'client may only update status, responded_at, patch';
    end if;
    new.updated_at := now();
    return new;
  end if;
  raise exception 'not allowed to update this proposal';
end;
$;

drop trigger if exists whisper_coach_proposals_guard_trg on public.whisper_coach_proposals;
create trigger whisper_coach_proposals_guard_trg
  before update on public.whisper_coach_proposals
  for each row execute function public.whisper_coach_proposals_guard();

-- Expiry job: any proposal still 'pending' past expires_at flips to 'expired'.
-- Requires the pg_cron extension; safe to re-run.
create extension if not exists pg_cron;

create or replace function public.whisper_coach_proposals_expire() returns void
language sql as $
  update public.whisper_coach_proposals
     set status = 'expired', updated_at = now()
   where status = 'pending'
     and expires_at < now();
$;

-- Schedule hourly. cron.schedule is idempotent on (jobname).
select cron.unschedule('whisper_coach_proposals_expire')
 where exists (
   select 1 from cron.job where jobname = 'whisper_coach_proposals_expire'
 );
select cron.schedule(
  'whisper_coach_proposals_expire',
  '0 * * * *',
  $select public.whisper_coach_proposals_expire();$
);
