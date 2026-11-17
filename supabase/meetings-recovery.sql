-- ============================================================================
-- Whisper Meetings — RECOVERY + hardening (run this INSTEAD of
-- meetings-hardening.sql, which is now superseded).
--
-- Why this exists: the previous hardening policies referenced each other
-- across tables (meetings checked participants, participants checked
-- meetings). Postgres rejects that at query time with "infinite recursion
-- detected in policy" (42P17), which broke creating, scheduling, and reading
-- meetings for everyone.
--
-- The fix: membership/host checks live in SECURITY DEFINER functions, which
-- read the tables without re-entering row-level security — no recursion,
-- same privacy guarantees:
--   - Meetings are readable only by their host and people who joined the link.
--   - The roster is readable by the host and members.
--   - Transcripts are readable only by the host and members; each user can
--     insert only their own speech.
--   - Joining goes through the guarded join_whisper_meeting RPC.
--
-- Run once in the Supabase SQL editor. Safe to re-run.
-- ============================================================================

-- ─── 1. Non-recursive access checks ─────────────────────────────────────────

create or replace function public.is_whisper_meeting_host(p_meeting_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.whisper_meetings m
    where m.id = p_meeting_id
      and m.host_id = auth.uid()
  );
$$;

create or replace function public.is_whisper_meeting_member(p_meeting_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.whisper_meeting_participants p
    where p.meeting_id = p_meeting_id
      and p.user_id = auth.uid()
  );
$$;

revoke all on function public.is_whisper_meeting_host(uuid) from public;
revoke all on function public.is_whisper_meeting_member(uuid) from public;
grant execute on function public.is_whisper_meeting_host(uuid) to authenticated;
grant execute on function public.is_whisper_meeting_member(uuid) to authenticated;

-- ─── 2. Guarded join RPC (the private link IS the invitation) ────────────────

create or replace function public.join_whisper_meeting(
  p_meeting_id uuid,
  p_username text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required';
  end if;

  -- Link holders can join scheduled or live meetings; the host can always
  -- record their own membership (e.g. reopening an ended meeting's notes).
  if not exists (
    select 1
    from public.whisper_meetings
    where id = p_meeting_id
      and (status in ('scheduled', 'live') or host_id = auth.uid())
  ) then
    raise exception 'meeting_unavailable';
  end if;

  insert into public.whisper_meeting_participants (meeting_id, user_id, username)
  values (p_meeting_id, auth.uid(), left(coalesce(nullif(trim(p_username), ''), 'member'), 80))
  on conflict (meeting_id, user_id)
  do update set username = excluded.username;
end;
$$;

revoke all on function public.join_whisper_meeting(uuid, text) from public;
grant execute on function public.join_whisper_meeting(uuid, text) to authenticated;

-- ─── 3. Scheduled meetings keep started_at null until the host starts ───────

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'whisper_meetings'
      and column_name = 'started_at'
      and is_nullable = 'NO'
  ) then
    alter table public.whisper_meetings alter column started_at drop not null;
  end if;
end $$;

-- ─── 4. Replace the recursive policies ───────────────────────────────────────

alter table public.whisper_meetings enable row level security;
alter table public.whisper_meeting_participants enable row level security;
alter table public.whisper_meeting_transcripts enable row level security;

drop policy if exists "wm_select" on public.whisper_meetings;
drop policy if exists "wm_insert" on public.whisper_meetings;
drop policy if exists "wm_update" on public.whisper_meetings;
drop policy if exists "wmp_select" on public.whisper_meeting_participants;
drop policy if exists "wmp_insert" on public.whisper_meeting_participants;
drop policy if exists "wmt_select" on public.whisper_meeting_transcripts;
drop policy if exists "wmt_insert" on public.whisper_meeting_transcripts;

-- Meetings: host reads directly (also satisfies INSERT ... RETURNING);
-- link members read through the definer check — no policy recursion.
create policy "wm_select"
on public.whisper_meetings
for select to authenticated
using (
  host_id = auth.uid()
  or public.is_whisper_meeting_member(id)
);

create policy "wm_insert"
on public.whisper_meetings
for insert to authenticated
with check (host_id = auth.uid());

create policy "wm_update"
on public.whisper_meetings
for update to authenticated
using (host_id = auth.uid())
with check (host_id = auth.uid());

-- Roster: yourself, the host, and fellow members can see who joined.
-- Direct inserts stay closed; membership is granted by the RPC above.
create policy "wmp_select"
on public.whisper_meeting_participants
for select to authenticated
using (
  user_id = auth.uid()
  or public.is_whisper_meeting_host(meeting_id)
  or public.is_whisper_meeting_member(meeting_id)
);

create policy "wmp_insert"
on public.whisper_meeting_participants
for insert to authenticated
with check (false);

-- Transcripts: private to the host and people who joined the link.
create policy "wmt_select"
on public.whisper_meeting_transcripts
for select to authenticated
using (
  public.is_whisper_meeting_host(meeting_id)
  or public.is_whisper_meeting_member(meeting_id)
);

create policy "wmt_insert"
on public.whisper_meeting_transcripts
for insert to authenticated
with check (
  user_id = auth.uid()
  and (
    public.is_whisper_meeting_member(meeting_id)
    or public.is_whisper_meeting_host(meeting_id)
  )
);

-- ─── 5. Make PostgREST pick up the new functions immediately ─────────────────

notify pgrst, 'reload schema';
