-- ─────────────────────────────────────────────────────────────────────────
-- Live v2 — Stream Manager + real moderation + go-live alerts.
--
--   • whisper_live_moderators — channel-level mods (per HOST, like Twitch;
--     a mod moderates every live that host runs).
--   • whisper_live_bans      — channel-level bans (host + mods manage).
--   • whisper_live_timeouts  — per-room timeouts (host + mods manage).
--   • whisper_live_alerts    — "went live" rows fanned out to followers.
--   • whisper_live_rooms     — gains banned_words[] + peak_listeners.
--
-- Run once in the Supabase SQL editor. Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────

-- ── Room columns ─────────────────────────────────────────────────────────

alter table public.whisper_live_rooms
  add column if not exists banned_words text[] not null default '{}';

alter table public.whisper_live_rooms
  add column if not exists peak_listeners integer not null default 0;

-- ── Moderators (channel-level) ───────────────────────────────────────────

create table if not exists public.whisper_live_moderators (
  host_id uuid not null,
  mod_user_id uuid not null,
  mod_username text not null default '',
  created_at timestamptz not null default now(),
  primary key (host_id, mod_user_id)
);

alter table public.whisper_live_moderators enable row level security;

do $$ begin
  create policy "live mods read" on public.whisper_live_moderators
    for select to authenticated using (true);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "live mods host insert" on public.whisper_live_moderators
    for insert to authenticated with check (auth.uid() = host_id);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "live mods host delete" on public.whisper_live_moderators
    for delete to authenticated using (auth.uid() = host_id);
exception when duplicate_object then null; end $$;

-- ── Bans (channel-level; host OR that host's mods manage) ────────────────

create table if not exists public.whisper_live_bans (
  host_id uuid not null,
  banned_user_id uuid not null,
  banned_username text not null default '',
  created_at timestamptz not null default now(),
  primary key (host_id, banned_user_id)
);

alter table public.whisper_live_bans enable row level security;

do $$ begin
  create policy "live bans read" on public.whisper_live_bans
    for select to authenticated using (true);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "live bans manage insert" on public.whisper_live_bans
    for insert to authenticated with check (
      auth.uid() = host_id
      or exists (
        select 1 from public.whisper_live_moderators m
        where m.host_id = whisper_live_bans.host_id
          and m.mod_user_id = auth.uid()
      )
    );
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "live bans manage delete" on public.whisper_live_bans
    for delete to authenticated using (
      auth.uid() = host_id
      or exists (
        select 1 from public.whisper_live_moderators m
        where m.host_id = whisper_live_bans.host_id
          and m.mod_user_id = auth.uid()
      )
    );
exception when duplicate_object then null; end $$;

-- ── Timeouts (per room; host OR the room host's mods manage) ─────────────

create table if not exists public.whisper_live_timeouts (
  room_id uuid not null,
  user_id uuid not null,
  username text not null default '',
  until timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

alter table public.whisper_live_timeouts enable row level security;

do $$ begin
  create policy "live timeouts read" on public.whisper_live_timeouts
    for select to authenticated using (true);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "live timeouts manage insert" on public.whisper_live_timeouts
    for insert to authenticated with check (
      exists (
        select 1 from public.whisper_live_rooms r
        where r.id = whisper_live_timeouts.room_id
          and (
            r.host_id = auth.uid()
            or exists (
              select 1 from public.whisper_live_moderators m
              where m.host_id = r.host_id and m.mod_user_id = auth.uid()
            )
          )
      )
    );
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "live timeouts manage update" on public.whisper_live_timeouts
    for update to authenticated using (
      exists (
        select 1 from public.whisper_live_rooms r
        where r.id = whisper_live_timeouts.room_id
          and (
            r.host_id = auth.uid()
            or exists (
              select 1 from public.whisper_live_moderators m
              where m.host_id = r.host_id and m.mod_user_id = auth.uid()
            )
          )
      )
    );
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "live timeouts manage delete" on public.whisper_live_timeouts
    for delete to authenticated using (
      exists (
        select 1 from public.whisper_live_rooms r
        where r.id = whisper_live_timeouts.room_id
          and (
            r.host_id = auth.uid()
            or exists (
              select 1 from public.whisper_live_moderators m
              where m.host_id = r.host_id and m.mod_user_id = auth.uid()
            )
          )
      )
    );
exception when duplicate_object then null; end $$;

-- ── Go-live alerts (fanned out to followers when a host goes live) ───────

create table if not exists public.whisper_live_alerts (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null,
  host_username text not null default '',
  room_id uuid not null,
  room_name text not null default '',
  follower_id uuid not null,
  created_at timestamptz not null default now()
);

create index if not exists whisper_live_alerts_follower_idx
  on public.whisper_live_alerts (follower_id, created_at desc);

alter table public.whisper_live_alerts enable row level security;

do $$ begin
  create policy "live alerts follower read" on public.whisper_live_alerts
    for select to authenticated using (auth.uid() = follower_id);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "live alerts host insert" on public.whisper_live_alerts
    for insert to authenticated with check (auth.uid() = host_id);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "live alerts follower delete" on public.whisper_live_alerts
    for delete to authenticated using (auth.uid() = follower_id);
exception when duplicate_object then null; end $$;
