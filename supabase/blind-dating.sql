-- Blind dating (Round 76) — preferences + radius, the pairing queue that
-- matches strangers into blind video dates, and the date records that
-- carry private decisions + Jasper's recap.
--
-- Privacy by construction:
--   • Coordinates are stored COARSE (clients round to 2 decimals ≈ 1 km)
--     and NEVER leave the server — other people only ever see a rounded
--     distance through whisper_dating_nearby().
--   • Decisions are private until BOTH people have decided; the partner's
--     answer is only returned once yours is in.
--   • Queue rows are self-readable only; every write goes through RPCs.
-- Safe to re-run.

create extension if not exists pgcrypto;

-- ─── Preferences ─────────────────────────────────────────────────────────

create table if not exists public.whisper_dating_prefs (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text,
  gender text,                                   -- woman | man | nonbinary
  seeking text[] not null default '{}'::text[],  -- empty = everyone
  age int,
  age_min int not null default 18,
  age_max int not null default 99,
  radius_km int not null default 50,             -- 0 = anywhere
  intent text,                                   -- relationship | casual | friends | open
  lat double precision,
  lng double precision,
  city_label text,
  updated_at timestamptz not null default now()
);

alter table public.whisper_dating_prefs enable row level security;

drop policy if exists "dating_prefs_select_self" on public.whisper_dating_prefs;
create policy "dating_prefs_select_self" on public.whisper_dating_prefs
  for select using (auth.uid() = user_id);
drop policy if exists "dating_prefs_insert_self" on public.whisper_dating_prefs;
create policy "dating_prefs_insert_self" on public.whisper_dating_prefs
  for insert with check (auth.uid() = user_id);
drop policy if exists "dating_prefs_update_self" on public.whisper_dating_prefs;
create policy "dating_prefs_update_self" on public.whisper_dating_prefs
  for update using (auth.uid() = user_id);
drop policy if exists "dating_prefs_delete_self" on public.whisper_dating_prefs;
create policy "dating_prefs_delete_self" on public.whisper_dating_prefs
  for delete using (auth.uid() = user_id);

-- Great-circle distance in km (haversine).
create or replace function public.whisper_km(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision
) returns double precision
language sql immutable as $$
  select 6371.0 * 2.0 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2.0), 2)
    + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2.0), 2)
  ))
$$;

-- Does A's preference set accept B? (gender · age · distance)
create or replace function public.whisper_dating_fits(
  a public.whisper_dating_prefs, b public.whisper_dating_prefs
) returns boolean
language sql stable as $$
  select (coalesce(array_length(a.seeking, 1), 0) = 0 or b.gender is null or b.gender = any(a.seeking))
     and (b.age is null or (b.age between coalesce(a.age_min, 18) and coalesce(a.age_max, 99)))
     and (coalesce(a.radius_km, 0) <= 0 or a.lat is null or b.lat is null
          or public.whisper_km(a.lat, a.lng, b.lat, b.lng) <= a.radius_km)
$$;

-- People inside MY radius who would also include ME — with a rounded
-- distance only. Raw coordinates never leave the server.
create or replace function public.whisper_dating_nearby()
returns table (
  user_id uuid, username text, distance_km numeric,
  age int, gender text, intent text, city_label text
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
           p.age, p.gender, p.intent, p.city_label
    from public.whisper_dating_prefs p
    where p.user_id <> me.user_id
      and public.whisper_dating_fits(me, p)
      and public.whisper_dating_fits(p, me)
    order by 3 nulls last
    limit 400;
end $$;

-- ─── The blind-date queue ────────────────────────────────────────────────

create table if not exists public.whisper_blind_queue (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null default 'someone',
  answers jsonb not null default '[]'::jsonb,   -- [{prompt, answer}] private icebreaker answers
  status text not null default 'waiting',       -- waiting | paired
  room_code text,
  partner_id uuid,
  partner_username text,
  role text,                                    -- host | guest
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  paired_at timestamptz
);

alter table public.whisper_blind_queue enable row level security;
drop policy if exists "blind_queue_select_self" on public.whisper_blind_queue;
create policy "blind_queue_select_self" on public.whisper_blind_queue
  for select using (auth.uid() = user_id);
-- No insert/update/delete policies: every write goes through the RPCs.

-- Word + prompt overlap between two private answer sets (0..1).
create or replace function public.whisper_blind_answer_overlap(a jsonb, b jsonb)
returns numeric
language plpgsql immutable as $$
declare
  shared_words int := 0;
  words_a int := 0;
  words_b int := 0;
  shared_prompts int := 0;
  jacc numeric := 0;
begin
  if a is null or b is null or jsonb_typeof(a) <> 'array' or jsonb_typeof(b) <> 'array' then
    return 0;
  end if;
  with wa as (
    select distinct lower(w) as w
    from jsonb_array_elements(a) e,
         regexp_split_to_table(coalesce(e->>'answer', ''), '[^A-Za-z0-9]+') w
    where length(w) > 3
  ), wb as (
    select distinct lower(w) as w
    from jsonb_array_elements(b) e,
         regexp_split_to_table(coalesce(e->>'answer', ''), '[^A-Za-z0-9]+') w
    where length(w) > 3
  )
  select (select count(*) from wa join wb using (w)),
         (select count(*) from wa),
         (select count(*) from wb)
    into shared_words, words_a, words_b;
  select count(*) into shared_prompts
  from (select distinct lower(coalesce(e->>'prompt', '')) p from jsonb_array_elements(a) e) pa
  join (select distinct lower(coalesce(e->>'prompt', '')) p from jsonb_array_elements(b) e) pb using (p)
  where pa.p <> '';
  if (words_a + words_b - shared_words) > 0 then
    jacc := shared_words::numeric / (words_a + words_b - shared_words)::numeric;
  end if;
  return least(1.0, 0.7 * jacc + 0.3 * least(3, shared_prompts)::numeric / 3.0);
end $$;

-- Join the queue (or refresh my row) and try to pair right now.
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
  end if;

  -- Sweep: silent waiters (no heartbeat for 90s) and old pairings.
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

  -- The best compatible stranger who's waiting right now (row-locked so two
  -- searchers can never grab the same person).
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
    + least(0.10, extract(epoch from (now() - q.joined_at)) / 600.0 * 0.10) as score
  into best
  from public.whisper_blind_queue q
  left join public.whisper_dating_prefs qp on qp.user_id = q.user_id
  where q.user_id <> me
    and q.status = 'waiting'
    and q.last_seen > now() - interval '90 seconds'
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

  -- The date record is opened by the clients with the ROOM ID both apps
  -- hash the code to (source = 'queue'), so decisions + recap key off one row.
  return jsonb_build_object(
    'status', 'paired', 'room_code', code, 'partner_id', best.user_id,
    'partner_username', best.username, 'role', 'host');
end $$;

-- Heartbeat + re-check: the waiting side also searches, so whoever polls
-- first pairs the two.
create or replace function public.whisper_blind_date_poll()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  mine public.whisper_blind_queue;
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  update public.whisper_blind_queue set last_seen = now() where user_id = me returning * into mine;
  if mine.user_id is null then
    return jsonb_build_object('status', 'none');
  end if;
  if mine.status = 'paired' then
    return jsonb_build_object(
      'status', 'paired', 'room_code', mine.room_code, 'partner_id', mine.partner_id,
      'partner_username', mine.partner_username, 'role', mine.role);
  end if;
  return public.whisper_blind_date_join(mine.username, mine.answers);
end $$;

create or replace function public.whisper_blind_date_leave()
returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.whisper_blind_queue where user_id = auth.uid();
end $$;

-- How many people are waiting right now (the header's live dot).
create or replace function public.whisper_blind_queue_count()
returns int
language sql security definer set search_path = public stable as $$
  select count(*)::int from public.whisper_blind_queue
  where status = 'waiting' and last_seen > now() - interval '90 seconds'
    and user_id is distinct from auth.uid()
$$;

-- ─── Date records + private decisions ────────────────────────────────────

create table if not exists public.whisper_blind_dates (
  id uuid primary key default gen_random_uuid(),
  room_code text not null unique,
  host_id uuid not null,
  guest_id uuid,
  source text not null default 'invite',   -- invite | queue
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  revealed boolean not null default false,
  recap jsonb,
  created_at timestamptz not null default now()
);

alter table public.whisper_blind_dates enable row level security;
drop policy if exists "blind_dates_select_participants" on public.whisper_blind_dates;
create policy "blind_dates_select_participants" on public.whisper_blind_dates
  for select using (auth.uid() = host_id or auth.uid() = guest_id);

create table if not exists public.whisper_blind_date_decisions (
  room_code text not null,
  user_id uuid not null,
  decision text not null,                  -- again | friends | pass
  created_at timestamptz not null default now(),
  primary key (room_code, user_id)
);

alter table public.whisper_blind_date_decisions enable row level security;
drop policy if exists "blind_decisions_select_self" on public.whisper_blind_date_decisions;
create policy "blind_decisions_select_self" on public.whisper_blind_date_decisions
  for select using (auth.uid() = user_id);

-- Open (or claim) the record for a room: the first person becomes host,
-- the second becomes guest. Idempotent. p_source: invite | queue.
drop function if exists public.whisper_blind_date_open(text);
create or replace function public.whisper_blind_date_open(p_room_code text, p_source text default 'invite')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  row public.whisper_blind_dates;
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  select * into row from public.whisper_blind_dates where room_code = p_room_code;
  if row.id is null then
    insert into public.whisper_blind_dates (room_code, host_id, source)
    values (p_room_code, me, case when p_source = 'queue' then 'queue' else 'invite' end)
    on conflict (room_code) do nothing;
    select * into row from public.whisper_blind_dates where room_code = p_room_code;
  end if;
  if row.host_id <> me and row.guest_id is null then
    update public.whisper_blind_dates set guest_id = me where room_code = p_room_code
    returning * into row;
  end if;
  return jsonb_build_object('id', row.id, 'room_code', row.room_code,
                            'host_id', row.host_id, 'guest_id', row.guest_id,
                            'started_at', row.started_at);
end $$;

-- Record my decision; the partner's answer only comes back once BOTH are in.
create or replace function public.whisper_blind_date_decide(p_room_code text, p_decision text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  d public.whisper_blind_dates;
  partner uuid;
  theirs text;
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  if p_decision not in ('again', 'friends', 'pass') then
    raise exception 'bad decision';
  end if;
  perform public.whisper_blind_date_open(p_room_code);
  select * into d from public.whisper_blind_dates where room_code = p_room_code;
  if d.host_id <> me and d.guest_id is distinct from me then
    raise exception 'not a participant';
  end if;
  insert into public.whisper_blind_date_decisions (room_code, user_id, decision)
  values (p_room_code, me, p_decision)
  on conflict (room_code, user_id) do update set decision = excluded.decision, created_at = now();
  partner := case when d.host_id = me then d.guest_id else d.host_id end;
  if partner is not null then
    select decision into theirs from public.whisper_blind_date_decisions
    where room_code = p_room_code and user_id = partner;
  end if;
  return jsonb_build_object(
    'mine', p_decision,
    'theirs', theirs,
    'mutual', (theirs = 'again' and p_decision = 'again'));
end $$;

-- Jasper's recap + the end stamp (participants only).
create or replace function public.whisper_blind_date_finish(
  p_room_code text, p_revealed boolean default false, p_recap jsonb default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  perform public.whisper_blind_date_open(p_room_code);
  update public.whisper_blind_dates
     set ended_at = coalesce(ended_at, now()),
         revealed = revealed or coalesce(p_revealed, false),
         recap = coalesce(p_recap, recap)
   where room_code = p_room_code and (host_id = me or guest_id = me);
end $$;

-- My past dates, newest first — the partner's decision only once both decided.
create or replace function public.whisper_blind_date_history()
returns setof jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'room_code', d.room_code,
    'source', d.source,
    'started_at', d.started_at,
    'ended_at', d.ended_at,
    'revealed', d.revealed,
    'partner_id', p.partner_id,
    'partner_username', coalesce(pr.username, 'someone'),
    'my_decision', md.decision,
    'their_decision', case when md.decision is not null then td.decision else null end,
    'mutual', (md.decision = 'again' and td.decision = 'again'),
    'recap', d.recap)
  from public.whisper_blind_dates d
  cross join lateral (select case when d.host_id = auth.uid() then d.guest_id else d.host_id end as partner_id) p
  left join public.whisper_profiles pr on pr.user_id = p.partner_id
  left join public.whisper_blind_date_decisions md on md.room_code = d.room_code and md.user_id = auth.uid()
  left join public.whisper_blind_date_decisions td on td.room_code = d.room_code and td.user_id = p.partner_id
  where d.host_id = auth.uid() or d.guest_id = auth.uid()
  order by d.started_at desc
  limit 60
$$;

-- ─── Grants ──────────────────────────────────────────────────────────────

revoke all on function public.whisper_dating_nearby() from public, anon;
revoke all on function public.whisper_blind_date_join(text, jsonb) from public, anon;
revoke all on function public.whisper_blind_date_poll() from public, anon;
revoke all on function public.whisper_blind_date_leave() from public, anon;
revoke all on function public.whisper_blind_queue_count() from public, anon;
revoke all on function public.whisper_blind_date_open(text, text) from public, anon;
revoke all on function public.whisper_blind_date_decide(text, text) from public, anon;
revoke all on function public.whisper_blind_date_finish(text, boolean, jsonb) from public, anon;
revoke all on function public.whisper_blind_date_history() from public, anon;

grant execute on function public.whisper_dating_nearby() to authenticated;
grant execute on function public.whisper_blind_date_join(text, jsonb) to authenticated;
grant execute on function public.whisper_blind_date_poll() to authenticated;
grant execute on function public.whisper_blind_date_leave() to authenticated;
grant execute on function public.whisper_blind_queue_count() to authenticated;
grant execute on function public.whisper_blind_date_open(text, text) to authenticated;
grant execute on function public.whisper_blind_date_decide(text, text) to authenticated;
grant execute on function public.whisper_blind_date_finish(text, boolean, jsonb) to authenticated;
grant execute on function public.whisper_blind_date_history() to authenticated;
