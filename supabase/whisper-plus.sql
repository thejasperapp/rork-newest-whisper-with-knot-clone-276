-- Whisper Plus — the paid rung between Whisper One and Verified Creator that
-- carries the Jasper Intelligence pro pack (unlimited chats, voice mode,
-- Imagine, /jasper everywhere, memory, priority). One boolean entitlement on
-- the profile row, flipped by the billing webhook on subscribe / cancel /
-- refund exactly like is_one. Safe to re-run.

alter table public.whisper_profiles
  add column if not exists is_plus boolean not null default false;

alter table public.whisper_profiles
  add column if not exists plus_since timestamptz;

comment on column public.whisper_profiles.is_plus is
  'Whisper Plus membership — the Jasper Intelligence pro pack. Set by billing, never by clients.';

-- Clients read it with the profile; only the service role (billing webhook,
-- admin refunds) may change it. The canonical self-update policy already
-- restricts column writes through the app; this trigger is the belt to that
-- suspender — a non-service-role write can never flip the flag.
create or replace function public.whisper_guard_plus_flag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (new.is_plus is distinct from old.is_plus or new.plus_since is distinct from old.plus_since)
     and coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    new.is_plus := old.is_plus;
    new.plus_since := old.plus_since;
  end if;
  return new;
end;
$$;

drop trigger if exists whisper_guard_plus_flag on public.whisper_profiles;
create trigger whisper_guard_plus_flag
  before update on public.whisper_profiles
  for each row execute function public.whisper_guard_plus_flag();
