-- ============================================================================
-- Badge approval trigger v2 — points the approval hook at the CURRENT
-- backend deployment. The v1 trigger (badge-payments.sql) was aimed at a
-- retired host, so approvals made from the Supabase table editor / iOS
-- dashboard fired their activation email at a stale worker.
--
-- Run once in the Supabase SQL editor (replaces the function in place).
-- The Bearer value must match the BROADCAST_SECRET project env.
-- ============================================================================

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
      -- Permanent project alias — always tracks the newest backend deploy.
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

-- Triggers already exist from badge-payments.sql; re-create defensively so
-- this file works on a fresh database too.
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
