-- ─────────────────────────────────────────────────────────────────────────────
-- Account types — personal vs professional (creator / business), the
-- Instagram-style split. Signup offers the choice, Settings → Account type
-- switches it anytime, and professional accounts carry a public category
-- plus optional contact details shown on their profile.
--
-- NOTE: whisper_profiles.account_type ALREADY exists in original schemas with
-- legacy values ('user' | 'coach' | 'athlete' | …). This migration NORMALIZES
-- those into the new vocabulary BEFORE adding the check constraint:
--   · 'coach'          → 'creator' (they already hold pro tools; category "Coach")
--   · everything else  → 'personal'
-- Coach/athlete FEATURES are driven by is_coach / is_athlete flags — untouched.
--
-- Safe to re-run: additive + idempotent.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.whisper_profiles
  add column if not exists account_type text,
  add column if not exists professional_category text,
  add column if not exists contact_email text,
  add column if not exists contact_phone text;

-- Default for new rows.
alter table public.whisper_profiles
  alter column account_type set default 'personal';

-- Normalize legacy values into the new vocabulary.
update public.whisper_profiles
set professional_category = coalesce(professional_category, 'Coach')
where account_type = 'coach';

update public.whisper_profiles
set account_type = 'creator'
where account_type = 'coach';

update public.whisper_profiles
set account_type = 'personal'
where account_type is null
   or account_type not in ('personal', 'creator', 'business');

-- Keep the type honest — personal, creator, or business only.
do $$
begin
  if exists (
    select 1 from pg_constraint where conname = 'whisper_profiles_account_type_check'
  ) then
    alter table public.whisper_profiles
      drop constraint whisper_profiles_account_type_check;
  end if;
  alter table public.whisper_profiles
    add constraint whisper_profiles_account_type_check
    check (account_type in ('personal', 'creator', 'business'));
end $$;

comment on column public.whisper_profiles.account_type is
  'personal | creator | business — professional accounts (creator/business) get category labels, contact buttons, and the pro dashboards.';
comment on column public.whisper_profiles.professional_category is
  'Public category label professional accounts wear on their profile (e.g. Fitness coach, Restaurant, Content creator).';
