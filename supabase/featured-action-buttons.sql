-- Add action_buttons column to featured profiles.
-- Lets the admin attach multiple typed CTA buttons to a spotlight:
--   email, calendar (internal Whisper shared calendar), external link,
--   or the default in-app profile view.
-- Run once in the Supabase SQL editor (safe to re-run).

alter table public.whisper_featured_profiles
  add column if not exists action_buttons jsonb not null default '[]'::jsonb;

-- Backfill: any existing row with a cta_label/cta_url gets a single
-- synthesized button so the public card keeps rendering the old CTA.
update public.whisper_featured_profiles
  set action_buttons = jsonb_build_array(
    jsonb_build_object(
      'label', coalesce(cta_label, ''),
      'type', case when cta_url is null or cta_url = '' then 'profile' else 'link' end,
      'href', coalesce(cta_url, '')
    )
  )
  where (action_buttons = '[]'::jsonb)
    and (cta_label is not null and cta_label <> '');
