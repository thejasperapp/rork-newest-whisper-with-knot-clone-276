-- Keep unknown/malformed descriptors readable via client fallback, but reject new nonnumeric versions.
do $$ begin
  if not exists(select 1 from pg_constraint where conrelid='public.whisper_group_themes'::regclass and conname='group_theme_numeric_version') then
    alter table public.whisper_group_themes add constraint group_theme_numeric_version
      check (jsonb_typeof(theme->'version') = 'number' and theme->'version' = '1'::jsonb) not valid;
  end if;
end $$;
