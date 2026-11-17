-- ─────────────────────────────────────────────────────────────────────────
-- Live v3 — DATABASE-LEVEL moderation enforcement.
--
-- Live v2 created the moderation tables (mods / bans / timeouts / banned
-- words) but enforcement lived in the web client. This migration moves the
-- wall into Postgres so NO client — web, iOS, or a hand-rolled API call —
-- can speak in a room it's banned or timed out from:
--
--   • chat INSERT now blocks channel-banned users, active timeouts, and
--     messages containing the room's banned words.
--   • chat DELETE/UPDATE extend to the host's channel MODS (web + iOS
--     mod tools ride real policies, not client goodwill).
--   • go-live alerts get a dedupe guard (one alert per room per follower)
--     and join the realtime publication so bells ring instantly.
--
-- Self-contained: re-creates the v2 tables if they're missing, so it's
-- safe to run even if live-v2.sql hasn't been applied yet. Run once in
-- the Supabase SQL editor; safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────

-- ── Ensure the v2 schema exists (no-ops when live-v2.sql already ran) ────

alter table public.whisper_live_rooms
  add column if not exists banned_words text[] not null default '{}';

alter table public.whisper_live_rooms
  add column if not exists peak_listeners integer not null default 0;

create table if not exists public.whisper_live_moderators (
  host_id uuid not null,
  mod_user_id uuid not null,
  mod_username text not null default '',
  created_at timestamptz not null default now(),
  primary key (host_id, mod_user_id)
);
alter table public.whisper_live_moderators enable row level security;

create table if not exists public.whisper_live_bans (
  host_id uuid not null,
  banned_user_id uuid not null,
  banned_username text not null default '',
  created_at timestamptz not null default now(),
  primary key (host_id, banned_user_id)
);
alter table public.whisper_live_bans enable row level security;

create table if not exists public.whisper_live_timeouts (
  room_id uuid not null,
  user_id uuid not null,
  username text not null default '',
  until timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (room_id, user_id)
);
alter table public.whisper_live_timeouts enable row level security;

create table if not exists public.whisper_live_alerts (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null,
  host_username text not null default '',
  room_id uuid not null,
  room_name text not null default '',
  follower_id uuid not null,
  created_at timestamptz not null default now()
);
alter table public.whisper_live_alerts enable row level security;

-- ── THE WALL: banned / timed-out / banned-word senders stopped in Postgres

drop policy if exists whisper_live_chat_insert on public.whisper_live_chat_messages;
create policy whisper_live_chat_insert on public.whisper_live_chat_messages
  for insert to authenticated with check (
    auth.uid() = user_id
    -- channel ban (per host — follows the host across all their lives)
    and not exists (
      select 1
      from public.whisper_live_rooms r
      join public.whisper_live_bans b on b.host_id = r.host_id
      where r.id = whisper_live_chat_messages.room_id
        and b.banned_user_id = auth.uid()
    )
    -- active room timeout
    and not exists (
      select 1 from public.whisper_live_timeouts t
      where t.room_id = whisper_live_chat_messages.room_id
        and t.user_id = auth.uid()
        and t.until > now()
    )
    -- room banned words (stored lowercase; substring match like the client)
    and not exists (
      select 1
      from public.whisper_live_rooms r2, unnest(r2.banned_words) as w(word)
      where r2.id = whisper_live_chat_messages.room_id
        and lower(whisper_live_chat_messages.body) like '%' || w.word || '%'
    )
  );

-- ── Mods can delete + pin, with real policies (host + self kept) ─────────

drop policy if exists whisper_live_chat_delete on public.whisper_live_chat_messages;
create policy whisper_live_chat_delete on public.whisper_live_chat_messages
  for delete to authenticated using (
    auth.uid() = user_id
    or exists (
      select 1 from public.whisper_live_rooms r
      where r.id = whisper_live_chat_messages.room_id
        and (
          r.host_id = auth.uid()
          or exists (
            select 1 from public.whisper_live_moderators m
            where m.host_id = r.host_id and m.mod_user_id = auth.uid()
          )
        )
    )
  );

drop policy if exists whisper_live_chat_update on public.whisper_live_chat_messages;
create policy whisper_live_chat_update on public.whisper_live_chat_messages
  for update to authenticated using (
    auth.uid() = user_id
    or exists (
      select 1 from public.whisper_live_rooms r
      where r.id = whisper_live_chat_messages.room_id
        and (
          r.host_id = auth.uid()
          or exists (
            select 1 from public.whisper_live_moderators m
            where m.host_id = r.host_id and m.mod_user_id = auth.uid()
          )
        )
    )
  );

-- ── Go-live alerts: dedupe + instant delivery ────────────────────────────

-- One alert per room per follower — repeated go-live flips can't spam.
create unique index if not exists whisper_live_alerts_room_follower_uniq
  on public.whisper_live_alerts (room_id, follower_id);

-- Realtime so the bell can ring the moment the row lands.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'whisper_live_alerts'
  ) then
    alter publication supabase_realtime add table public.whisper_live_alerts;
  end if;
end $$;
