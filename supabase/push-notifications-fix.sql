-- ============================================================
-- Whisper push notification delivery fixes  (run once)
-- ============================================================
-- What this fixes:
--   1. Device-token schema drift: the app and the fan-out function
--      disagreed on columns (environment vs sandbox/active), so new
--      devices could fail to register entirely.
--   2. Tokens stuck pointing at a PREVIOUS account that signed in on
--      the same device. RLS blocks a plain upsert from reassigning a
--      row owned by another user, so the token silently kept ringing
--      the old account — the "I message a friend and my own phone
--      buzzes" bug. Fixed with SECURITY DEFINER claim functions: a
--      push token belongs to the DEVICE, so whoever is signed in now
--      owns it.
--   3. Creates whisper_voip_tokens (CallKit native ringing) and
--      whisper_call_push_dedupe (one push per call) used by the
--      whisper-push-fanout edge function.
--   4. Reactivates tokens that were wrongly killed by APNs
--      environment mix-ups (the fan-out now self-heals those).

-- ------------------------------------------------------------
-- 1) Device tokens: table + every column any version ever used
-- ------------------------------------------------------------
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

alter table public.whisper_device_tokens
  add column if not exists bundle_id text,
  add column if not exists sandbox boolean,
  add column if not exists platform text not null default 'ios',
  add column if not exists active boolean not null default true,
  add column if not exists environment text,
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

-- Give previously-deactivated tokens another chance: the fan-out now
-- retries the opposite APNs host before declaring a token dead, so
-- tokens killed by sandbox/production mix-ups will recover.
update public.whisper_device_tokens set active = true where active = false;

-- Backfill sandbox from the legacy environment column where possible.
update public.whisper_device_tokens
   set sandbox = (environment = 'sandbox')
 where sandbox is null and environment is not null;

-- ------------------------------------------------------------
-- 2) Claim function: reassign the token to the CURRENT account
-- ------------------------------------------------------------
create or replace function public.whisper_claim_device_token(
  p_token text,
  p_bundle_id text default null,
  p_sandbox boolean default null,
  p_platform text default 'ios'
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if p_token is null or length(p_token) < 8 or length(p_token) > 512 then
    raise exception 'invalid token';
  end if;
  -- The device token physically belongs to this device; whoever is
  -- signed in NOW owns it. Delete any row left by a previous account.
  delete from public.whisper_device_tokens where token = p_token;
  insert into public.whisper_device_tokens
    (token, user_id, bundle_id, sandbox, platform, active, created_at, updated_at)
  values
    (p_token, auth.uid(), p_bundle_id, p_sandbox, coalesce(p_platform, 'ios'), true, now(), now());
end;
$$;

grant execute on function public.whisper_claim_device_token(text, text, boolean, text) to authenticated;

-- ------------------------------------------------------------
-- 3) VoIP (CallKit) tokens — native incoming-call UI pushes
-- ------------------------------------------------------------
create table if not exists public.whisper_voip_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  bundle_id text,
  environment text not null default 'sandbox',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists whisper_voip_tokens_user_idx
  on public.whisper_voip_tokens (user_id);

alter table public.whisper_voip_tokens enable row level security;

drop policy if exists "wvt insert own" on public.whisper_voip_tokens;
create policy "wvt insert own" on public.whisper_voip_tokens
  for insert with check (auth.uid() = user_id);

drop policy if exists "wvt update own" on public.whisper_voip_tokens;
create policy "wvt update own" on public.whisper_voip_tokens
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "wvt select own" on public.whisper_voip_tokens;
create policy "wvt select own" on public.whisper_voip_tokens
  for select using (auth.uid() = user_id);

drop policy if exists "wvt delete own" on public.whisper_voip_tokens;
create policy "wvt delete own" on public.whisper_voip_tokens
  for delete using (auth.uid() = user_id);

create or replace function public.whisper_claim_voip_token(
  p_token text,
  p_bundle_id text default null,
  p_environment text default 'sandbox'
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if p_token is null or length(p_token) < 8 or length(p_token) > 512 then
    raise exception 'invalid token';
  end if;
  delete from public.whisper_voip_tokens where token = p_token;
  insert into public.whisper_voip_tokens
    (token, user_id, bundle_id, environment, created_at, updated_at)
  values
    (p_token, auth.uid(), p_bundle_id, coalesce(p_environment, 'sandbox'), now(), now());
end;
$$;

grant execute on function public.whisper_claim_voip_token(text, text, text) to authenticated;

-- ------------------------------------------------------------
-- 4) Call push dedupe — guarantees ONE ring push per call id
--    even across edge-function cold starts. Service-role only.
-- ------------------------------------------------------------
create table if not exists public.whisper_call_push_dedupe (
  call_id text primary key,
  created_at timestamptz not null default now()
);

alter table public.whisper_call_push_dedupe enable row level security;
-- No client policies on purpose: only the service-role fan-out touches it.

create index if not exists whisper_call_push_dedupe_created_idx
  on public.whisper_call_push_dedupe (created_at);
