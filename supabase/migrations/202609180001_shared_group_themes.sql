-- Shared appearance is isolated from owner-only roster/name updates.
create table if not exists public.whisper_group_themes (
  group_id uuid primary key references public.whisper_group_threads(id) on delete cascade,
  theme jsonb not null,
  revision bigint not null default 1 check (revision > 0),
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  operation_id uuid not null
);
alter table public.whisper_group_themes enable row level security;
revoke all on public.whisper_group_themes from anon, authenticated;
grant select on public.whisper_group_themes to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='whisper_group_themes' and policyname='group_theme_member_read') then
    create policy group_theme_member_read on public.whisper_group_themes for select to authenticated using (
      exists (select 1 from public.whisper_group_threads g where g.id=group_id and (g.owner_id=auth.uid() or auth.uid()=any(g.member_ids)))
    );
  end if;
end $$;
create or replace function public.whisper_set_group_theme(p_group_id uuid, p_expected_revision bigint, p_theme jsonb, p_operation_id uuid)
returns public.whisper_group_themes language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  g public.whisper_group_threads;
  current_theme public.whisper_group_themes;
  result public.whisper_group_themes;
begin
  if actor is null then raise exception 'Sign in required' using errcode='42501'; end if;
  select * into g from public.whisper_group_threads where id=p_group_id for update;
  if not found or not (g.owner_id=actor or actor=any(g.member_ids)) then
    raise exception 'Group unavailable' using errcode='42501';
  end if;
  if p_operation_id is null or p_expected_revision is null or p_expected_revision < 0
    or p_theme is null or jsonb_typeof(p_theme) <> 'object' or octet_length(p_theme::text)>1024
    or (p_theme->>'version') is distinct from '1'
    or coalesce(p_theme->>'preset','') not in ('classic','midnight','rose','ocean','forest','sand','dusk','cherry','lavender','mint','coffee','sky','lantern','tide','nocturne','wildflower','blueprint','terracotta')
    or jsonb_typeof(p_theme->'title') is distinct from 'string'
    or length(coalesce(p_theme->>'title','')) not between 1 and 48
    or ((p_theme ? 'accent_hex') and p_theme->'accent_hex' <> 'null'::jsonb and coalesce(p_theme->>'accent_hex','') !~ '^#[0-9a-fA-F]{6}$')
    or exists (select 1 from jsonb_object_keys(p_theme) as k where k not in ('version','preset','title','accent_hex')) then
    raise exception 'Invalid theme' using errcode='22023';
  end if;
  select * into current_theme from public.whisper_group_themes where group_id=p_group_id;
  if found and current_theme.operation_id=p_operation_id then
    if current_theme.updated_by<>actor or current_theme.theme<>p_theme then raise exception 'Invalid operation' using errcode='22023'; end if;
    return current_theme;
  end if;
  if coalesce(current_theme.revision,0)<>p_expected_revision then
    raise exception 'Theme changed. Refresh and try again.' using errcode='40001';
  end if;
  insert into public.whisper_group_themes(group_id,theme,revision,updated_by,operation_id)
    values(p_group_id,p_theme,coalesce(current_theme.revision,0)+1,actor,p_operation_id)
    on conflict(group_id) do update set theme=excluded.theme, revision=excluded.revision,
      updated_by=excluded.updated_by, updated_at=now(), operation_id=excluded.operation_id
    returning * into result;
  return result;
end $$;
revoke all on function public.whisper_set_group_theme(uuid,bigint,jsonb,uuid) from public, anon;
grant execute on function public.whisper_set_group_theme(uuid,bigint,jsonb,uuid) to authenticated;
do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='whisper_group_themes') then
    alter publication supabase_realtime add table public.whisper_group_themes;
  end if;
end $$;
