-- Dating v2 (Round 77) — trust + safety + the social calendar of dating.
-- Run ONCE in the Supabase SQL editor, AFTER supabase/blind-dating.sql.
-- Idempotent: safe to re-run.
--
-- Adds:
--   • whisper_dating_verifications — photo verification ("Verified dater 💘").
--       iOS performs an on-device liveness check (Vision face tracking + a
--       random head-turn prompt) and submits as `liveness` → auto-verified.
--       Web submits a live-camera selfie as `pending` → a moderator approves
--       from the admin console (whisper_dating_verification_review).
--   • whisper_dating_reports — real reports from the wrap/hub; reporting can
--       block in one move (writes the platform-wide whisper_blocks row).
--   • BLOCKS ENFORCED SERVER-SIDE — the queue pairing, the nearby list, and
--       the verified lookup all exclude anyone blocked in EITHER direction.
--   • whisper_dating_event_rsvps — "Tonight at 8" dating hours: RSVP counts
--       per local-evening event key; the finder shows who's coming.
--   • whisper_dating_intros — a 15-second voice or video intro on the card
--       (readable by every signed-in dater; write-own).
--   • Dealbreakers: whisper_dating_prefs gains `lifestyle` (my answers:
--       smoking · drinking · kids · faith · pets) and `dealbreakers` (which
--       answers I accept per topic). whisper_dating_fits() honors them, so
--       the pairing queue and the nearby list never surface a violation.

-- ─── Dealbreakers on preferences ─────────────────────────────────────────

alter table public.whisper_dating_prefs
  add column if not exists lifestyle jsonb not null default '{}'::jsonb;
alter table public.whisper_dating_prefs
  add column if not exists dealbreakers jsonb not null default '{}'::jsonb;

-- A's dealbreakers vs B's lifestyle answers. A dealbreaker is a topic key
-- mapped to the list of answers A accepts. B fails only when B has ANSWERED
-- that topic with something outside A's accepted list — an unanswered topic
-- passes (nobody is punished for leaving a field blank).
create or replace function public.whisper_dating_dealbreakers_ok(a_deal jsonb, b_life jsonb)
returns boolean
language sql immutable as $$
  select not exists (
    select 1
    from jsonb_each(coalesce(a_deal, '{}'::jsonb)) d
    where jsonb_typeof(d.value) = 'array'
      and jsonb_array_length(d.value) > 0
      and coalesce(b_life, '{}'::jsonb) ? d.key
      and nullif(trim(coalesce(b_life ->> d.key, '')), '') is not null
      and not (d.value ? (b_life ->> d.key))
  )
$$;

-- Does A's preference set accept B? (gender · age · distance · dealbreakers)
create or replace function public.whisper_dating_fits(
  a public.whisper_dating_prefs, b public.whisper_dating_prefs
) returns boolean
language sql stable as $$
  select (coalesce(array_length(a.seeking, 1), 0) = 0 or b.gender is null or b.gender = any(a.seeking))
     and (b.age is null or (b.age between coalesce(a.age_min, 18) and coalesce(a.age_max, 99)))
     and (coalesce(a.radius_km, 0) <= 0 or a.lat is null or b.lat is null
          or public.whisper_km(a.lat, a.lng, b.lat, b.lng) <= a.radius_km)
     and public.whisper_dating_dealbreakers_ok(a.dealbreakers, b.lifestyle)
$$;

-- ─── Blocks (platform table) — helper for the dating RPCs ────────────────

create table if not exists public.whisper_blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_user_id uuid not null,
  blocked_username text not null,
  created_at timestamptz not null default now(),
  unique (blocker_id, blocked_user_id)
);

create or replace function public.whisper_dating_blocked_between(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.whisper_blocks w
    where (w.blocker_id = a and w.blocked_user_id = b)
       or (w.blocker_id = b and w.blocked_user_id = a)
  )
$$;

-- ─── Photo verification ──────────────────────────────────────────────────

create table if not exists public.whisper_dating_verifications (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text,
  selfie_url text,
  status text not null default 'pending',    -- pending | verified | rejected
  method text not null default 'selfie',     -- liveness | selfie
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid
);

alter table public.whisper_dating_verifications enable row level security;
drop policy if exists "dating_verif_select_self" on public.whisper_dating_verifications;
create policy "dating_verif_select_self" on public.whisper_dating_verifications
  for select using (auth.uid() = user_id);
-- Writes go through the RPCs below.

create or replace function public.whisper_dating_verification_submit(
  p_selfie_url text,
  p_method text default 'selfie',
  p_liveness_passed boolean default false,
  p_username text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  new_status text;
  row public.whisper_dating_verifications;
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  -- On-device liveness (face tracked through a random head-turn prompt)
  -- auto-verifies; a plain selfie waits for a moderator.
  new_status := case when p_method = 'liveness' and p_liveness_passed then 'verified' else 'pending' end;
  insert into public.whisper_dating_verifications (user_id, username, selfie_url, status, method, created_at, reviewed_at, reviewed_by)
  values (me, nullif(trim(coalesce(p_username, '')), ''), p_selfie_url, new_status, coalesce(p_method, 'selfie'), now(),
          case when new_status = 'verified' then now() else null end, null)
  on conflict (user_id) do update
    set username = coalesce(excluded.username, public.whisper_dating_verifications.username),
        selfie_url = excluded.selfie_url,
        -- Never downgrade an already-verified dater by re-submitting.
        status = case when public.whisper_dating_verifications.status = 'verified' then 'verified' else excluded.status end,
        method = excluded.method,
        created_at = now(),
        reviewed_at = case when excluded.status = 'verified' then now() else public.whisper_dating_verifications.reviewed_at end
  returning * into row;
  return jsonb_build_object('status', row.status, 'method', row.method, 'created_at', row.created_at);
end $$;

-- Which of these usernames are verified daters? (Anyone signed in may ask;
-- only the boolean leaks — never the selfie.) Blocked-either-way users are
-- reported as unverified so a blocked person never even wears a badge to you.
create or replace function public.whisper_dating_verified(p_usernames text[])
returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(v.username), '{}'::text[])
  from public.whisper_dating_verifications v
  where v.status = 'verified'
    and v.username is not null
    and lower(v.username) = any (select lower(u) from unnest(coalesce(p_usernames, '{}'::text[])) u)
    and (auth.uid() is null or not public.whisper_dating_blocked_between(auth.uid(), v.user_id))
$$;

create or replace function public.whisper_dating_is_staff()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.whisper_profiles p
    where p.id = auth.uid()
      and (coalesce(p.is_admin, false) or coalesce(p.is_owner, false) or coalesce(p.is_moderator, false))
  )
$$;

-- Moderator queue + review.
create or replace function public.whisper_dating_verification_queue()
returns table (user_id uuid, username text, selfie_url text, method text, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not public.whisper_dating_is_staff() then
    raise exception 'staff only';
  end if;
  return query
    select v.user_id, v.username, v.selfie_url, v.method, v.created_at
    from public.whisper_dating_verifications v
    where v.status = 'pending'
    order by v.created_at asc
    limit 200;
end $$;

create or replace function public.whisper_dating_verification_review(p_user_id uuid, p_approve boolean)
returns text
language plpgsql security definer set search_path = public as $$
declare
  new_status text := case when p_approve then 'verified' else 'rejected' end;
begin
  if not public.whisper_dating_is_staff() then
    raise exception 'staff only';
  end if;
  update public.whisper_dating_verifications
     set status = new_status, reviewed_at = now(), reviewed_by = auth.uid()
   where user_id = p_user_id;
  return new_status;
end $$;

-- ─── Reports (+ one-move block) ──────────────────────────────────────────

create table if not exists public.whisper_dating_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_id uuid,
  reported_username text not null,
  room_code text,
  reason text not null,
  details text,
  created_at timestamptz not null default now()
);

alter table public.whisper_dating_reports enable row level security;
drop policy if exists "dating_reports_select_self" on public.whisper_dating_reports;
create policy "dating_reports_select_self" on public.whisper_dating_reports
  for select using (auth.uid() = reporter_id or public.whisper_dating_is_staff());

create or replace function public.whisper_dating_report(
  p_reported_username text,
  p_reason text,
  p_details text default null,
  p_room_code text default null,
  p_block boolean default true
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  target uuid;
  uname text := lower(trim(coalesce(p_reported_username, '')));
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  if uname = '' then
    raise exception 'missing username';
  end if;
  select p.id into target from public.whisper_profiles p where lower(p.username) = uname limit 1;

  insert into public.whisper_dating_reports (reporter_id, reported_id, reported_username, room_code, reason, details)
  values (me, target, uname, p_room_code, coalesce(nullif(trim(p_reason), ''), 'other'), nullif(trim(coalesce(p_details, '')), ''));

  if p_block and target is not null and target <> me then
    insert into public.whisper_blocks (blocker_id, blocked_user_id, blocked_username)
    values (me, target, uname)
    on conflict (blocker_id, blocked_user_id) do nothing;
    -- Drop any live pairing with them and pull both out of each other's way.
    delete from public.whisper_blind_queue q where q.user_id = me and q.partner_id = target;
  end if;

  return jsonb_build_object('reported', true, 'blocked', (p_block and target is not null), 'resolved', target is not null);
end $$;

-- ─── Dating hours — "Tonight at 8" RSVPs ─────────────────────────────────

create table if not exists public.whisper_dating_event_rsvps (
  event_key text not null,            -- ISO instant of the local 8pm, e.g. 2026-09-02T00:00Z
  user_id uuid not null references auth.users(id) on delete cascade,
  username text not null default 'someone',
  created_at timestamptz not null default now(),
  primary key (event_key, user_id)
);

alter table public.whisper_dating_event_rsvps enable row level security;
drop policy if exists "dating_rsvp_select_all" on public.whisper_dating_event_rsvps;
create policy "dating_rsvp_select_all" on public.whisper_dating_event_rsvps
  for select using (auth.uid() is not null);
drop policy if exists "dating_rsvp_insert_self" on public.whisper_dating_event_rsvps;
create policy "dating_rsvp_insert_self" on public.whisper_dating_event_rsvps
  for insert with check (auth.uid() = user_id);
drop policy if exists "dating_rsvp_delete_self" on public.whisper_dating_event_rsvps;
create policy "dating_rsvp_delete_self" on public.whisper_dating_event_rsvps
  for delete using (auth.uid() = user_id);

create or replace function public.whisper_dating_event_toggle(
  p_event_key text, p_going boolean, p_username text default 'someone'
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  n int;
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  if p_going then
    insert into public.whisper_dating_event_rsvps (event_key, user_id, username)
    values (p_event_key, me, coalesce(nullif(trim(p_username), ''), 'someone'))
    on conflict (event_key, user_id) do update set username = excluded.username;
  else
    delete from public.whisper_dating_event_rsvps where event_key = p_event_key and user_id = me;
  end if;
  -- Housekeeping: RSVPs older than two days are noise.
  delete from public.whisper_dating_event_rsvps where created_at < now() - interval '2 days';
  select count(*) into n from public.whisper_dating_event_rsvps where event_key = p_event_key;
  return jsonb_build_object('event_key', p_event_key, 'going', coalesce(n, 0), 'me', p_going);
end $$;

create or replace function public.whisper_dating_event_counts(p_keys text[])
returns table (event_key text, going int, me boolean)
language sql stable security definer set search_path = public as $$
  select k.key as event_key,
         (select count(*)::int from public.whisper_dating_event_rsvps r where r.event_key = k.key) as going,
         exists (select 1 from public.whisper_dating_event_rsvps r where r.event_key = k.key and r.user_id = auth.uid()) as me
  from unnest(coalesce(p_keys, '{}'::text[])) as k(key)
$$;

-- ─── Voice / video intros ────────────────────────────────────────────────

create table if not exists public.whisper_dating_intros (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text,
  url text not null,
  kind text not null default 'voice',       -- voice | video
  duration_s int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.whisper_dating_intros enable row level security;
drop policy if exists "dating_intros_select_all" on public.whisper_dating_intros;
create policy "dating_intros_select_all" on public.whisper_dating_intros
  for select using (auth.uid() is not null);
drop policy if exists "dating_intros_insert_self" on public.whisper_dating_intros;
create policy "dating_intros_insert_self" on public.whisper_dating_intros
  for insert with check (auth.uid() = user_id);
drop policy if exists "dating_intros_update_self" on public.whisper_dating_intros;
create policy "dating_intros_update_self" on public.whisper_dating_intros
  for update using (auth.uid() = user_id);
drop policy if exists "dating_intros_delete_self" on public.whisper_dating_intros;
create policy "dating_intros_delete_self" on public.whisper_dating_intros
  for delete using (auth.uid() = user_id);

-- ─── Nearby list: blocks + verified + lifestyle ──────────────────────────

drop function if exists public.whisper_dating_nearby();
create or replace function public.whisper_dating_nearby()
returns table (
  user_id uuid, username text, distance_km numeric,
  age int, gender text, intent text, city_label text,
  verified boolean, lifestyle jsonb
)
language plpgsql security definer set search_path = public as $$
declare
  me public.whisper_dating_prefs;
begin
  select * into me from public.whisper_dating_prefs p where p.user_id = auth.uid();
  if me.user_id is null then
    return;
  end if;
  return query
    select p.user_id, p.username,
           case when me.lat is not null and p.lat is not null
                then round(public.whisper_km(me.lat, me.lng, p.lat, p.lng)::numeric, 1)
                else null end as distance_km,
           p.age, p.gender, p.intent, p.city_label,
           exists (select 1 from public.whisper_dating_verifications v
                   where v.user_id = p.user_id and v.status = 'verified') as verified,
           coalesce(p.lifestyle, '{}'::jsonb) as lifestyle
    from public.whisper_dating_prefs p
    where p.user_id <> me.user_id
      and public.whisper_dating_fits(me, p)
      and public.whisper_dating_fits(p, me)
      and not public.whisper_dating_blocked_between(me.user_id, p.user_id)
    order by 3 nulls last
    limit 400;
end $$;

-- ─── Queue pairing: blocks + dealbreakers (via fits) + verified bonus ────

create or replace function public.whisper_blind_date_join(
  p_username text default 'someone',
  p_answers jsonb default '[]'::jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  my_prefs public.whisper_dating_prefs;
  mine public.whisper_blind_queue;
  best record;
  code text;
  waiting_count int;
begin
  if me is null then
    raise exception 'not signed in';
  end if;

  select * into my_prefs from public.whisper_dating_prefs where user_id = me;
  if my_prefs.user_id is null then
    my_prefs.user_id := me;
    my_prefs.seeking := '{}'::text[];
    my_prefs.age_min := 18;
    my_prefs.age_max := 99;
    my_prefs.radius_km := 0;
    my_prefs.lifestyle := '{}'::jsonb;
    my_prefs.dealbreakers := '{}'::jsonb;
  end if;

  delete from public.whisper_blind_queue q
  where (q.status = 'waiting' and q.last_seen < now() - interval '90 seconds')
     or (q.status = 'paired' and q.paired_at < now() - interval '30 minutes');

  insert into public.whisper_blind_queue (user_id, username, answers, status, joined_at, last_seen)
  values (me, coalesce(nullif(trim(p_username), ''), 'someone'),
          case when jsonb_typeof(coalesce(p_answers, '[]'::jsonb)) = 'array' then p_answers else '[]'::jsonb end,
          'waiting', now(), now())
  on conflict (user_id) do update
    set username = excluded.username,
        answers = excluded.answers,
        last_seen = now(),
        status = case when public.whisper_blind_queue.status = 'paired' then 'paired' else 'waiting' end
  returning * into mine;

  if mine.status = 'paired' then
    return jsonb_build_object(
      'status', 'paired', 'room_code', mine.room_code, 'partner_id', mine.partner_id,
      'partner_username', mine.partner_username, 'role', mine.role);
  end if;

  select q.*,
    (case when qp.user_id is null then 0.10 else
        (case when qp.intent is not null and my_prefs.intent is not null and qp.intent = my_prefs.intent then 0.30 else 0.0 end)
      + (case when qp.lat is not null and my_prefs.lat is not null
              then greatest(0.0, 0.25 * (1.0 - least(1.0,
                     public.whisper_km(my_prefs.lat, my_prefs.lng, qp.lat, qp.lng)
                     / greatest(1.0, coalesce(nullif(my_prefs.radius_km, 0), 100)::double precision))))
              else 0.05 end)
     end)
    + public.whisper_blind_answer_overlap(mine.answers, q.answers) * 0.45
    + least(0.10, extract(epoch from (now() - q.joined_at)) / 600.0 * 0.10)
    -- Verified daters get a small trust bonus in the pairing order.
    + (case when exists (select 1 from public.whisper_dating_verifications v
                         where v.user_id = q.user_id and v.status = 'verified') then 0.08 else 0.0 end) as score
  into best
  from public.whisper_blind_queue q
  left join public.whisper_dating_prefs qp on qp.user_id = q.user_id
  where q.user_id <> me
    and q.status = 'waiting'
    and q.last_seen > now() - interval '90 seconds'
    and not public.whisper_dating_blocked_between(me, q.user_id)
    and (qp.user_id is null
         or (public.whisper_dating_fits(my_prefs, qp) and public.whisper_dating_fits(qp, my_prefs)))
  order by score desc, q.joined_at asc
  limit 1
  for update of q skip locked;

  if not found then
    select count(*) into waiting_count
    from public.whisper_blind_queue
    where status = 'waiting' and user_id <> me and last_seen > now() - interval '90 seconds';
    return jsonb_build_object('status', 'waiting', 'waiting', coalesce(waiting_count, 0));
  end if;

  code := 'wsp-' || substr(encode(gen_random_bytes(4), 'hex'), 1, 4)
               || '-' || substr(encode(gen_random_bytes(4), 'hex'), 1, 4);

  update public.whisper_blind_queue
     set status = 'paired', room_code = code, partner_id = best.user_id,
         partner_username = best.username, role = 'host', paired_at = now(), last_seen = now()
   where user_id = me;
  update public.whisper_blind_queue
     set status = 'paired', room_code = code, partner_id = me,
         partner_username = mine.username, role = 'guest', paired_at = now()
   where user_id = best.user_id;

  return jsonb_build_object(
    'status', 'paired', 'room_code', code, 'partner_id', best.user_id,
    'partner_username', best.username, 'role', 'host');
end $$;

-- ─── Grants ──────────────────────────────────────────────────────────────

grant execute on function public.whisper_dating_dealbreakers_ok(jsonb, jsonb) to authenticated;
grant execute on function public.whisper_dating_blocked_between(uuid, uuid) to authenticated;
grant execute on function public.whisper_dating_verification_submit(text, text, boolean, text) to authenticated;
grant execute on function public.whisper_dating_verified(text[]) to authenticated;
grant execute on function public.whisper_dating_is_staff() to authenticated;
grant execute on function public.whisper_dating_verification_queue() to authenticated;
grant execute on function public.whisper_dating_verification_review(uuid, boolean) to authenticated;
grant execute on function public.whisper_dating_report(text, text, text, text, boolean) to authenticated;
grant execute on function public.whisper_dating_event_toggle(text, boolean, text) to authenticated;
grant execute on function public.whisper_dating_event_counts(text[]) to authenticated;
grant execute on function public.whisper_dating_nearby() to authenticated;
grant execute on function public.whisper_blind_date_join(text, jsonb) to authenticated;

-- Stories: video stories (Round 77) — a poster stays in image_url, the clip
-- rides video_url. Older clients ignore the column and show the poster.
alter table public.whisper_stories add column if not exists video_url text;
