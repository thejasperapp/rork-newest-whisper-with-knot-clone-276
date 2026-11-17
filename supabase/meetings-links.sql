-- ============================================================================
-- Whisper Meetings — links that never die (run once in the Supabase SQL
-- editor; safe to re-run). Requires meetings-recovery.sql to have run first.
--
-- Meet's rule: a meeting link is never dead. Two changes:
--   1. join_whisper_meeting lets a signed-in link holder join ANY existing
--      meeting — scheduled, live, or ended — so an ended meeting reads as
--      "ended" (its notes, a Start-again button) instead of a false
--      "Meeting not found". Before this the RPC refused ended meetings, and
--      because the row read depends on membership, non-members saw nothing.
--   2. reopen_whisper_meeting flips an ended meeting back to live for any
--      signed-in link holder (the link IS the invitation), stamps a fresh
--      start, and records their membership — the same room, the same link,
--      the same notes history.
--
-- Guests (signed out) still read rooms through meetings-guest-access.sql.
-- ============================================================================

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

  -- The link is the invitation: any existing meeting can be joined. Ended
  -- meetings become readable (notes + "Start it again"); nothing else opens.
  if not exists (
    select 1 from public.whisper_meetings where id = p_meeting_id
  ) then
    raise exception 'meeting_not_found';
  end if;

  insert into public.whisper_meeting_participants (meeting_id, user_id, username)
  values (p_meeting_id, auth.uid(), left(coalesce(nullif(trim(p_username), ''), 'member'), 80))
  on conflict (meeting_id, user_id)
  do update set username = excluded.username;
end;
$$;

revoke all on function public.join_whisper_meeting(uuid, text) from public;
grant execute on function public.join_whisper_meeting(uuid, text) to authenticated;

create or replace function public.reopen_whisper_meeting(
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

  if not exists (
    select 1 from public.whisper_meetings where id = p_meeting_id
  ) then
    raise exception 'meeting_not_found';
  end if;

  -- Only an ended room flips; a live or scheduled one is left exactly as is.
  update public.whisper_meetings
     set status = 'live',
         started_at = now(),
         ended_at = null
   where id = p_meeting_id
     and status = 'ended';

  insert into public.whisper_meeting_participants (meeting_id, user_id, username)
  values (p_meeting_id, auth.uid(), left(coalesce(nullif(trim(p_username), ''), 'member'), 80))
  on conflict (meeting_id, user_id)
  do update set username = excluded.username;
end;
$$;

revoke all on function public.reopen_whisper_meeting(uuid, text) from public;
grant execute on function public.reopen_whisper_meeting(uuid, text) to authenticated;

notify pgrst, 'reload schema';
