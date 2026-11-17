-- ============================================================================
-- Whisper verified-badge payments + application reviews
-- (run once in the Supabase SQL editor)
--
-- Flow: user applies → an admin approves (web dashboard, iOS dashboard, or
-- directly in the table editor) → the applicant gets a branded "activate your
-- badge" email with the payment link → they pay the annual subscription →
-- the Stripe webhook flips is_coach / is_athlete / is_verified.
-- Perks are NEVER granted at approval time — only after payment confirms.
--
-- The trigger below is pre-filled with the project's broadcast key so
-- table-editor and iOS approvals email the payment link automatically.
-- ============================================================================

-- 1. Ledger of paid badge subscriptions (mirrors whisper_one_members).
create table if not exists public.whisper_badge_members (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  email text,
  role text not null check (role in ('coach','athlete','verified')),
  plan text not null,
  status text not null default 'active' check (status in ('active','past_due','cancelled')),
  stripe_customer_id text,
  stripe_subscription_id text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- If the table already exists from an earlier run, widen the role check so
-- 'verified' badges can be recorded too.
alter table public.whisper_badge_members
  drop constraint if exists whisper_badge_members_role_check;
alter table public.whisper_badge_members
  add constraint whisper_badge_members_role_check
  check (role in ('coach','athlete','verified'));

alter table public.whisper_badge_members enable row level security;

drop policy if exists "wbm read own" on public.whisper_badge_members;
create policy "wbm read own" on public.whisper_badge_members
  for select using (auth.uid() = user_id);
-- No insert/update policies: only the backend (service role) writes here.

-- 2. Email hook: when an application flips to 'approved', ping the billing
--    backend so it emails the applicant their payment link.
--
--    The trigger SKIPS updates made by the service role — those come from the
--    web admin dashboard (mydailywhisper.com/admin/applications), which sends
--    the email itself. This prevents double emails while still covering
--    approvals made directly in the Supabase table editor or from iOS.
create extension if not exists pg_net;

create or replace function public.notify_badge_approved()
returns trigger
language plpgsql
security definer
as $$
declare
  badge_role text;
  jwt_role text;
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    -- Skip when the billing backend (service role) made this update — it
    -- already sent the email itself.
    begin
      jwt_role := coalesce(
        current_setting('request.jwt.claims', true)::jsonb ->> 'role', ''
      );
    exception when others then
      jwt_role := '';
    end;
    if jwt_role = 'service_role' then
      return new;
    end if;

    badge_role := case tg_table_name
      when 'whisper_coach_applications' then 'coach'
      when 'whisper_athlete_applications' then 'athlete'
      when 'whisper_verification_requests' then 'verified'
    end;
    perform net.http_post(
      -- Permanent project alias — always tracks the newest backend deploy
      -- (keeps this v1 file safe to re-run without reverting the v2 fix).
      url := 'https://mdt742q5xnsko5i7owb0v-backend.rork.app/badges/approved-hook',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer 81ce3ef274ffc4ae5dbb07d6b8baabb746a5b25f5aea8682'
      ),
      body := jsonb_build_object(
        'userId', new.user_id,
        'email', new.email,
        'role', badge_role
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists coach_approved_email on public.whisper_coach_applications;
create trigger coach_approved_email
  after update on public.whisper_coach_applications
  for each row execute function public.notify_badge_approved();

drop trigger if exists athlete_approved_email on public.whisper_athlete_applications;
create trigger athlete_approved_email
  after update on public.whisper_athlete_applications
  for each row execute function public.notify_badge_approved();

drop trigger if exists verified_approved_email on public.whisper_verification_requests;
create trigger verified_approved_email
  after update on public.whisper_verification_requests
  for each row execute function public.notify_badge_approved();

-- 3. OPTIONAL one-time cleanup: strip perks from anyone who has a role flag
--    but NO active paid badge subscription. Run this once if badges were
--    granted for free under the old approval flow. Review the SELECT first!
--
-- select p.id, p.is_coach, p.is_athlete, p.is_verified
--   from public.profiles p
--  where (p.is_coach or p.is_athlete or p.is_verified)
--    and not exists (select 1 from public.whisper_badge_members m
--                     where m.user_id = p.id and m.status = 'active');
--
-- update public.profiles p
--    set is_coach = false, is_athlete = false, is_verified = false
--  where (p.is_coach or p.is_athlete or p.is_verified)
--    and not exists (select 1 from public.whisper_badge_members m
--                     where m.user_id = p.id and m.status = 'active');
--
-- update public.whisper_profiles wp
--    set is_coach = false, is_athlete = false
--  where (wp.is_coach or wp.is_athlete)
--    and not exists (select 1 from public.whisper_badge_members m
--                     where m.user_id = wp.user_id and m.status = 'active');
